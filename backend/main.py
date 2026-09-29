"""
后端入口：定义 App 要调用的网页接口（API）。

启动方法（在 backend 文件夹里运行）：
    uv run fastapi dev main.py
然后用浏览器打开 http://127.0.0.1:8000/docs 测试接口（部署到 Render 后 /docs 会关闭）。

接口一览：
    GET  /health    检查后端是否在运行（Render 也用它做健康检查）
    GET  /quota     查询这台设备今天还能识别几次、生成几次食谱
    POST /analyze   上传餐食照片，识别食物和营养
    POST /recipes   根据目标和忌口生成一日三餐

防护（后端放到公网后，任何人都能访问这个地址，所以要防止被人刷爆账单）：
    1. 门卫（limits.Gatekeeper）：只看请求头就先挡掉两类请求，不读请求体、不占内存
       - 没带正确 X-App-Key 的（密钥藏在 App 里，有心人能抠出来，所以只是第一道门）
       - 请求体太大的（识别最多 5 MB 出头，其他接口 32 KB）
    2. 四道次数限制（limits.Guard）：每台设备每天、每 IP 每天、全站每天、每 IP 每分钟
       每调用一次 AI 算一次（食谱重做也算一次）；没花钱的失败把次数还回去
    3. 并发闸门（limits.Gate）：同时最多 2 个请求在处理照片和调用 AI，其余排队，避免撑爆 512 MB 内存
    4. 真正的硬上限在 Claude 控制台里设的「每月花费上限」，上面这些都只是减速带
"""

import ipaddress
import logging
import os
import re
from typing import Annotated, Literal

from fastapi import FastAPI, File, Form, Header, HTTPException, Request, UploadFile

from food_ai import MAX_UPLOAD_BYTES, MODEL, ON_RENDER, AIError, AnalyzeResult, analyze_food_photo
from limits import Busy, Gate, Gatekeeper, Guard, LimitExceeded, ResultCache, Ticket
from recipes_ai import RecipeRequest, RecipesResult, generate_recipes

# 让各模块的日志（用时、token 用量）显示在终端里
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
# 开发模式会监视文件改动，它的「检测到 N 处变化」提示没什么用，关掉
logging.getLogger("watchfiles").setLevel(logging.WARNING)
logger = logging.getLogger("main")


def env_int(name: str, default: int) -> int:
    """从环境变量读一个正整数；没设就用默认值。方便在 Render 后台调整，不用改代码。
    填错了要在启动时就报错，不然错误的上限会悄悄生效"""
    raw = os.getenv(name)
    if raw is None or raw.strip() == "":
        return default
    try:
        value = int(raw)
    except ValueError:
        raise SystemExit(f"环境变量 {name} 必须是整数，现在是 {raw!r}")
    if value < 1:
        raise SystemExit(f"环境变量 {name} 必须大于 0，现在是 {value}")
    return value


# ---------- 费用控制 ----------
# 每 24 小时的次数上限，每调用一次 AI 算一次。全站上限是最后一道减速带：
#   识别：100 次 × 约 2 美分 ≈ 2 美元/天；食谱：40 次 × 约 3 美分 ≈ 1.2 美元/天
#   （极端情况下每次都顶到输出上限，一天最多约 7 美元，所以 Claude 控制台的每月上限才是真正的兜底）
ANALYZE_PER_DEVICE = env_int("ANALYZE_PER_DEVICE", 15)
ANALYZE_PER_IP = env_int("ANALYZE_PER_IP", 60)  # 同一个 Wi-Fi 下的几个人共用一个 IP，所以放宽到设备上限的几倍
ANALYZE_PER_SITE = env_int("ANALYZE_PER_SITE", 100)
RECIPES_PER_DEVICE = env_int("RECIPES_PER_DEVICE", 5)
RECIPES_PER_IP = env_int("RECIPES_PER_IP", 20)
RECIPES_PER_SITE = env_int("RECIPES_PER_SITE", 40)

analyze_guard = Guard(
    per_device=ANALYZE_PER_DEVICE, per_ip=ANALYZE_PER_IP, per_ip_per_minute=6, per_site=ANALYZE_PER_SITE
)
recipe_guard = Guard(
    per_device=RECIPES_PER_DEVICE, per_ip=RECIPES_PER_IP, per_ip_per_minute=4, per_site=RECIPES_PER_SITE
)
gate = Gate(slots=2, wait_seconds=25)
recipe_cache = ResultCache(ttl_seconds=24 * 3600)

# App 密钥：设了环境变量才检查；本地开发时不设，方便用 /docs 测试
APP_SHARED_SECRET = os.getenv("APP_SHARED_SECRET", "")
if ON_RENDER and not APP_SHARED_SECRET:
    logger.warning("没有设置 APP_SHARED_SECRET，任何人都可以调用这个后端")

app = FastAPI(
    title="饮食记录 App 后端",
    description="上传餐食照片识别营养，或根据目标生成一日三餐食谱。",
    version="0.3.0",
    # 部署到网上后关掉接口文档页面，不给陌生人看内部结构
    docs_url=None if ON_RENDER else "/docs",
    redoc_url=None if ON_RENDER else "/redoc",
    openapi_url=None if ON_RENDER else "/openapi.json",
)
# 门卫放在最外层：先查密钥和请求体大小，再交给下面的接口处理
app.add_middleware(
    Gatekeeper,
    secret=APP_SHARED_SECRET,
    body_limits={"/analyze": MAX_UPLOAD_BYTES + 64 * 1024},  # 照片 + multipart 格式本身的少量开销
    default_body_limit=32 * 1024,  # 其他接口的请求都很小
    open_paths=("/", "/health"),  # 不需要密钥的路径（Render 用 /health 做健康检查）
)

# App 在请求头 X-Device-ID 里带上自己的设备 ID（第一次启动时随机生成），用来计次
DeviceID = Annotated[str | None, Header(alias="X-Device-ID", description="App 的设备 ID（第一次启动时随机生成）")]
DEVICE_ID_PATTERN = re.compile(r"^[A-Za-z0-9-]{8,64}$")


def is_public_ip(host: str) -> bool:
    """是不是公网地址（内网、本机、保留地址都不算）"""
    try:
        return ipaddress.ip_address(host).is_global
    except ValueError:
        return False


def client_ip(request: Request) -> str:
    """来访者的真实 IP。
    在 Render 上，请求经过 Cloudflare 和 Render 的转发层；uvicorn 按启动参数 --forwarded-allow-ips
    里的可信代理列表，从 X-Forwarded-For 里找出真实来访者，放进 request.client.host
    （来访者自己伪造的 X-Forwarded-For 会被忽略）。
    万一解析出来的仍是内网地址（说明可信列表漏了一跳），退一步用 Cloudflare 写入的 CF-Connecting-IP。
    公网来访者伪造不了这条退路：他们的地址本来就是公网地址，不会走到这一步。"""
    host = request.client.host if request.client else "unknown"
    if ON_RENDER and not is_public_ip(host):
        if forwarded := request.headers.get("cf-connecting-ip"):
            return forwarded.strip()
    return host


def keys_for(request: Request, device_id: str | None) -> tuple[str, str]:
    """计次用的两把钥匙：设备钥匙（没有合法设备 ID 时退化成 IP）和 IP 钥匙"""
    ip_key = "ip:" + client_ip(request)
    if device_id and DEVICE_ID_PATTERN.match(device_id):
        return "device:" + device_id, ip_key
    return ip_key, ip_key


def acquire(guard: Guard, request: Request, device_id: str | None, what: str) -> Ticket:
    """扣一次次数；任何一道限制用完了就返回 429，不调用 AI"""
    device_key, ip_key = keys_for(request, device_id)
    try:
        return guard.acquire(device_key, ip_key)
    except LimitExceeded as e:
        hours = max(1, -(-e.retry_after // 3600))  # 向上取整
        detail = {
            "burst": f"{what}太频繁了，请稍等一分钟再试",
            "device": f"今天的{what}次数用完了（每 24 小时最多 {guard.per_device} 次），大约 {hours} 小时后可以再用",
            "ip": f"当前网络下今天的{what}次数用完了，大约 {hours} 小时后可以再用",
            "site": f"今天全站的{what}次数已经用完，请明天再试",
        }[e.scope]
        raise HTTPException(status_code=429, detail=detail, headers={"Retry-After": str(e.retry_after)})


def run_ai(guard: Guard, tickets: list[Ticket], work):
    """在并发闸门里执行 AI 调用。tickets 是这次请求扣掉的次数凭证（食谱重做时会有两张）。
    没花钱的失败把最后一次的次数还回去；前面已经完成的调用花过钱了，不退。"""
    try:
        with gate.enter():
            return work()
    except Busy:
        for ticket in tickets:
            guard.refund(ticket)
        raise HTTPException(status_code=503, detail="服务器正忙，请稍后再试", headers={"Retry-After": "20"})
    except AIError as e:
        if not e.billed:
            guard.refund(tickets[-1])
        # 出错时统一返回 {"detail": "给用户看的说明"}，App 直接显示这句话就行
        raise HTTPException(status_code=e.status_code, detail=e.message)
    except Exception:
        # 意料之外的错误：记进日志，对外仍然用统一的格式；不确定花没花钱，次数不退
        logger.exception("处理请求时出错")
        raise HTTPException(status_code=500, detail="服务器出错，请稍后再试")


@app.get("/")
def home():
    """首页。"""
    return {"message": "后端正在运行。"}


@app.get("/health")
def health():
    """检查后端是否在运行。本地开发时顺便显示当前用的模型；线上不显示，少透露一点内部信息。"""
    if ON_RENDER:
        return {"status": "ok"}
    return {"status": "ok", "model": MODEL}


@app.get("/quota")
def quota(request: Request, device_id: DeviceID = None):
    """这台设备今天还能识别几次、生成几次食谱。"""
    device_key, ip_key = keys_for(request, device_id)
    return {
        "analyze_remaining": analyze_guard.remaining(device_key, ip_key),
        "analyze_per_day": ANALYZE_PER_DEVICE,
        "recipes_remaining": recipe_guard.remaining(device_key, ip_key),
        "recipes_per_day": RECIPES_PER_DEVICE,
    }


@app.post("/analyze", response_model=AnalyzeResult)
def analyze(
    request: Request,
    photo: Annotated[UploadFile, File(description="餐食照片（JPG、PNG 或 HEIC）")],
    lang: Annotated[Literal["zh", "en"], Form(description="结果语言：zh 中文，en 英文")] = "zh",
    device_id: DeviceID = None,
):
    """识别照片里的食物，返回每种食物的营养数据和整餐合计。"""
    ticket = acquire(analyze_guard, request, device_id, "拍照识别")

    def work():
        # 读照片放在闸门里做：同时最多 2 个请求把照片读进内存
        # 多读 1 个字节：如果读到的比上限还多，说明照片太大。读不到合格的照片就把次数还回去
        data = photo.file.read(MAX_UPLOAD_BYTES + 1)
        if not data:
            raise AIError(400, "没有收到照片", billed=False)
        if len(data) > MAX_UPLOAD_BYTES:
            raise AIError(413, f"照片太大了，请上传 {MAX_UPLOAD_BYTES // 1024 // 1024} MB 以内的照片", billed=False)
        return analyze_food_photo(data, lang)

    return run_ai(analyze_guard, [ticket], work)


@app.post("/recipes", response_model=RecipesResult)
def recipes(body: RecipeRequest, request: Request, device_id: DeviceID = None):
    """根据目标、每日营养目标、偏好和忌口生成食谱。相同的请求 24 小时内直接返回缓存。"""
    device_key, ip_key = keys_for(request, device_id)

    # 「换一个」（带 exclude_names）要求结果不同，所以不用缓存
    cache_key = None if body.exclude_names else ResultCache.key_for(body.cache_payload())
    if cache_key and (cached := recipe_cache.get(cache_key)) is not None:
        return cached.model_copy(update={"from_cache": True, "remaining_today": recipe_guard.remaining(device_key, ip_key)})

    tickets = [acquire(recipe_guard, request, device_id, "食谱推荐")]

    def allow_retry() -> bool:
        # AI 没避开忌口时可以重做一次，但重做也是一次调用，也要算次数；次数不够就不重做
        try:
            tickets.append(recipe_guard.acquire(device_key, ip_key))
            return True
        except LimitExceeded:
            return False

    result = run_ai(recipe_guard, tickets, lambda: generate_recipes(body, allow_retry=allow_retry))
    result.remaining_today = recipe_guard.remaining(device_key, ip_key)
    if cache_key:
        recipe_cache.set(cache_key, result)
    return result
