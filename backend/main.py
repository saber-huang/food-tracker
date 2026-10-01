"""
后端入口：定义 App 要调用的网页接口（API）。

启动方法（在 backend 文件夹里运行）：
    uv run fastapi dev main.py
然后用浏览器打开 http://127.0.0.1:8000/docs 测试接口（部署到 Render 后 /docs 会关闭）。

接口一览：
    GET  /health    检查后端是否在运行（Render 也用它做健康检查）
    GET  /quota     查询这台设备今天还能识别几次、生成几次食谱
    POST /analyze   上传同一餐的 1～4 张照片，识别食物和营养（几张照片合并成一份结果）
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

from food_ai import MAX_PHOTOS, MAX_UPLOAD_BYTES, MODEL, ON_RENDER, AIError, AnalyzeResult, analyze_food_photos
import messages
from limits import Busy, Gate, Gatekeeper, Guard, LimitExceeded, ResultCache, Ticket
from messages import Lang
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
    body_limits={"/analyze": MAX_UPLOAD_BYTES + 64 * 1024},  # 所有照片加起来 + multipart 格式本身的少量开销
    default_body_limit=32 * 1024,  # 其他接口的请求都很小
    open_paths=("/", "/health"),  # 不需要密钥的路径（Render 用 /health 做健康检查）
)

# App 在请求头 X-Device-ID 里带上自己的设备 ID（第一次启动时随机生成），用来计次
DeviceID = Annotated[str | None, Header(alias="X-Device-ID", description="App 的设备 ID（第一次启动时随机生成）")]
DEVICE_ID_PATTERN = re.compile(r"^[A-Za-z0-9-]{8,64}$")


def rate_limit_address(raw: str) -> str | None:
    """把一个 IP 地址换成计次用的写法；不是合法的 IP 就返回 None。
    - IPv4：就是这个地址本身（一户人家的几台设备通常共用一个公网 IPv4）
    - IPv6：按前 64 位（/64）算一个地址。一户人家通常分到一整段 /64，里面的地址可以随便换，
      如果按完整地址计次，换一个地址就能绕过「每个 IP」的限制
    - ::ffff:1.2.3.4 这种写法其实是 IPv4，按 IPv4 算"""
    try:
        ip = ipaddress.ip_address(raw.strip())
    except ValueError:
        return None
    if ip.version == 6:
        if ip.ipv4_mapped:
            return str(ip.ipv4_mapped)
        return str(ipaddress.ip_network(f"{ip}/64", strict=False))
    return str(ip)


_warned_missing_cf_header = False


def client_ip(request: Request) -> str:
    """计次用的来访者地址。
    在 Render 上，请求先经过 Cloudflare，再经过 Render 的转发层才到这里。Cloudflare 会把来访者的真实地址
    写进 CF-Connecting-IP 请求头，并且不让来访者自己伪造它（带着伪造值的请求会被 Cloudflare 直接拦下，已实测），
    所以在 Render 上优先用它；没带这个头时，退回 uvicorn 按可信代理列表从 X-Forwarded-For 里推算的地址。
    注意：以前「同一台电脑分别用 IPv4 和 IPv6 访问，共用了同一个每分钟次数」的测试不成立。
    Render 的域名只有 IPv4 地址，curl -6 实际走的还是 IPv4，两次请求本来就来自同一个地址。
    要检查「不同来访者各算各的」，得用两个真正不同的网络（比如电脑的 Wi-Fi 和手机的蜂窝数据）。
    2026-09-30 在 Render 的日志里确认过：没有出现下面那条「没有带合法的 CF-Connecting-IP」的记录，
    访问日志里记下的也是来访者自己的公网地址（不是转发层的地址），两种方式得到的地址一致。
    本地开发没有 Cloudflare，直接用 uvicorn 给出的地址。"""
    global _warned_missing_cf_header
    if ON_RENDER:
        if (cf := request.headers.get("cf-connecting-ip")) and (address := rate_limit_address(cf)):
            return address
        # 正常情况下每个请求都带这个头；没带说明请求没经过 Cloudflare，记一次日志方便排查（只记第一次，免得刷屏）
        if not _warned_missing_cf_header:
            _warned_missing_cf_header = True
            logger.warning("请求没有带合法的 CF-Connecting-IP，改用转发层给出的地址计次")
    host = request.client.host if request.client else "unknown"
    return rate_limit_address(host) or host


def keys_for(request: Request, device_id: str | None) -> tuple[str, str]:
    """计次用的两把钥匙：设备钥匙（没有合法设备 ID 时退化成 IP）和 IP 钥匙"""
    ip_key = "ip:" + client_ip(request)
    if device_id and DEVICE_ID_PATTERN.match(device_id):
        return "device:" + device_id, ip_key
    return ip_key, ip_key


def request_lang(request: Request) -> Lang:
    """提示用中文还是英文：看 App 在 X-App-Lang 请求头里说的语言，没说就用中文（见 messages.py）"""
    return messages.lang_from_header(request.headers.get("x-app-lang"))


def acquire(guard: Guard, request: Request, device_id: str | None, feature: str) -> Ticket:
    """扣一次次数；任何一道限制用完了就返回 429，不调用 AI。feature 是 "analyze" 或 "recipes"。"""
    device_key, ip_key = keys_for(request, device_id)
    try:
        return guard.acquire(device_key, ip_key)
    except LimitExceeded as e:
        hours = max(1, -(-e.retry_after // 3600))  # 向上取整
        detail = messages.text(
            f"limit_{e.scope}", request_lang(request), feature=feature, limit=guard.per_device, hours=hours
        )
        raise HTTPException(status_code=429, detail=detail, headers={"Retry-After": str(e.retry_after)})


def run_ai(guard: Guard, tickets: list[Ticket], work, lang: Lang):
    """在并发闸门里执行 AI 调用。tickets 是这次请求扣掉的次数凭证（食谱重做时会有两张）。
    没花钱的失败把最后一次的次数还回去；前面已经完成的调用花过钱了，不退。
    lang 是出错说明用的语言。"""
    try:
        with gate.enter():
            return work()
    except Busy:
        for ticket in tickets:
            guard.refund(ticket)
        raise HTTPException(status_code=503, detail=messages.text("busy", lang), headers={"Retry-After": "20"})
    except AIError as e:
        if not e.billed:
            guard.refund(tickets[-1])
        # 出错时统一返回 {"detail": "给用户看的说明"}，App 直接显示这句话就行
        raise HTTPException(status_code=e.status_code, detail=e.message_for(lang))
    except Exception:
        # 意料之外的错误：记进日志，对外仍然用统一的格式；不确定花没花钱，次数不退
        logger.exception("处理请求时出错")
        raise HTTPException(status_code=500, detail=messages.text("server_error", lang))


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
    more_photos: Annotated[
        list[UploadFile] | None, File(description=f"同一餐的其他照片（最多 {MAX_PHOTOS - 1} 张，可以不传）")
    ] = None,
    lang: Annotated[Literal["zh", "en"], Form(description="结果语言：zh 中文，en 英文")] = "zh",
    device_id: DeviceID = None,
):
    """识别一餐的照片（1～4 张）：几张照片当作同一餐，同一份食物只算一次。
    返回每种食物的营养数据和整餐合计。一次识别不管几张照片，都只算一次。
    只传 photo 的旧版 App 照常工作。"""
    photos = [photo, *(more_photos or [])]
    # 张数不对在扣次数之前就拒绝：不调用 AI，也不占次数
    if len(photos) > MAX_PHOTOS:
        raise HTTPException(status_code=400, detail=messages.text("too_many_photos", request_lang(request), max=MAX_PHOTOS))
    ticket = acquire(analyze_guard, request, device_id, "analyze")

    def work():
        # 读照片放在闸门里做：同时最多 2 个请求把照片读进内存。
        # 所有照片加起来不能超过 MAX_UPLOAD_BYTES：每张多读 1 个字节，读到的比剩下的额度还多，说明太大了。
        # 读不到合格的照片就把次数还回去
        mb = MAX_UPLOAD_BYTES // 1024 // 1024
        budget = MAX_UPLOAD_BYTES
        datas: list[bytes] = []
        for upload in photos:
            data = upload.file.read(budget + 1)
            if not data:
                raise AIError(400, "no_photo", billed=False)
            if len(data) > budget:
                raise AIError(413, "photo_too_big" if len(photos) == 1 else "photos_too_big", billed=False, mb=mb)
            budget -= len(data)
            datas.append(data)
        return analyze_food_photos(datas, lang)

    return run_ai(analyze_guard, [ticket], work, request_lang(request))


@app.post("/recipes", response_model=RecipesResult)
def recipes(body: RecipeRequest, request: Request, device_id: DeviceID = None):
    """根据目标、每日营养目标、偏好和忌口生成食谱。相同的请求 24 小时内直接返回缓存。"""
    device_key, ip_key = keys_for(request, device_id)

    # 「换一个」（带 exclude_names）要求结果不同，所以不用缓存
    cache_key = None if body.exclude_names else ResultCache.key_for(body.cache_payload())
    if cache_key and (cached := recipe_cache.get(cache_key)) is not None:
        return cached.model_copy(update={"from_cache": True, "remaining_today": recipe_guard.remaining(device_key, ip_key)})

    tickets = [acquire(recipe_guard, request, device_id, "recipes")]

    def allow_retry() -> bool:
        # AI 没避开忌口时可以重做一次，但重做也是一次调用，也要算次数；次数不够就不重做
        try:
            tickets.append(recipe_guard.acquire(device_key, ip_key))
            return True
        except LimitExceeded:
            return False

    result = run_ai(recipe_guard, tickets, lambda: generate_recipes(body, allow_retry=allow_retry), request_lang(request))
    result.remaining_today = recipe_guard.remaining(device_key, ip_key)
    if cache_key:
        recipe_cache.set(cache_key, result)
    return result
