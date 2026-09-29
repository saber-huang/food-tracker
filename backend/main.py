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
    1. App 密钥：请求头 X-App-Key 要和环境变量 APP_SHARED_SECRET 一致，挡住随手乱试的人
       （密钥藏在 App 里，有心人能抠出来，所以它只是第一道门，不是保险箱）
    2. 四道次数限制（见 limits.py）：每 IP 每分钟、每台设备每天、每 IP 每天、全站每天
    3. 并发闸门：同时最多 2 个请求在处理照片和调用 AI，其余排队，避免撑爆 512 MB 内存
    4. 真正的硬上限在 Claude 控制台里设的「每月花费上限」，上面这些都只是减速带
"""

import hmac
import logging
import os
import re
from typing import Annotated, Literal

from fastapi import FastAPI, File, Form, Header, HTTPException, Request, UploadFile

from food_ai import MAX_UPLOAD_BYTES, MODEL, ON_RENDER, AIError, AnalyzeResult, analyze_food_photo
from limits import Busy, Gate, Guard, LimitExceeded, ResultCache, Ticket
from recipes_ai import RecipeRequest, RecipesResult, generate_recipes

# 让各模块的日志（用时、token 用量）显示在终端里
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
# 开发模式会监视文件改动，它的「检测到 N 处变化」提示没什么用，关掉
logging.getLogger("watchfiles").setLevel(logging.WARNING)
logger = logging.getLogger("main")


def env_int(name: str, default: int) -> int:
    """从环境变量读一个整数；没设就用默认值。方便在 Render 后台调整，不用改代码"""
    try:
        return int(os.getenv(name, default))
    except ValueError:
        return default


# ---------- 费用控制 ----------
# 每 24 小时的次数上限。全站上限是最后一道防线：不管来多少人，一天最多花这么多钱
#   识别：100 次 × 约 2 美分 ≈ 2 美元/天；食谱：40 次 × 约 3 美分 ≈ 1.2 美元/天
ANALYZE_PER_DEVICE = env_int("ANALYZE_PER_DEVICE", 15)
ANALYZE_PER_IP = env_int("ANALYZE_PER_IP", 40)
ANALYZE_PER_SITE = env_int("ANALYZE_PER_SITE", 100)
RECIPES_PER_DEVICE = env_int("RECIPES_PER_DEVICE", 5)
RECIPES_PER_IP = env_int("RECIPES_PER_IP", 15)
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

# App 在请求头里带上的信息
DeviceID = Annotated[str | None, Header(alias="X-Device-ID", description="App 的设备 ID（第一次启动时随机生成）")]
AppKey = Annotated[str | None, Header(alias="X-App-Key", description="App 密钥")]
DEVICE_ID_PATTERN = re.compile(r"^[A-Za-z0-9-]{8,64}$")


def check_app_key(app_key: str | None) -> None:
    """设了 APP_SHARED_SECRET 时，请求头里的密钥必须一致。用 compare_digest 比较，避免被人按耗时猜出密钥"""
    if not APP_SHARED_SECRET:
        return
    if not app_key or not hmac.compare_digest(app_key, APP_SHARED_SECRET):
        raise HTTPException(status_code=401, detail="请更新 App 到最新版本")


def client_ip(request: Request) -> str:
    """来访者的真实 IP。
    在 Render 上，请求会经过 Cloudflare 转发，Cloudflare 会把真实 IP 写在 CF-Connecting-IP 里，
    而且会覆盖来访者自己伪造的同名头；本地开发时直接用连接的地址。"""
    if ON_RENDER and (ip := request.headers.get("cf-connecting-ip")):
        return ip.strip()
    return request.client.host if request.client else "unknown"


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


def run_ai(guard: Guard, ticket: Ticket, work):
    """在并发闸门里执行 AI 调用。没花钱的失败会把次数还回去。"""
    try:
        with gate.enter():
            return work()
    except Busy:
        guard.refund(ticket)
        raise HTTPException(status_code=503, detail="服务器正忙，请稍后再试", headers={"Retry-After": "20"})
    except AIError as e:
        if not e.billed:
            guard.refund(ticket)
        # 出错时统一返回 {"detail": "给用户看的说明"}，App 直接显示这句话就行
        raise HTTPException(status_code=e.status_code, detail=e.message)


@app.get("/")
def home():
    """首页。"""
    return {"message": "后端正在运行。"}


@app.get("/health")
def health():
    """检查后端是否在运行，并显示当前用的模型。"""
    return {"status": "ok", "model": MODEL}


@app.get("/quota")
def quota(request: Request, device_id: DeviceID = None, app_key: AppKey = None):
    """这台设备今天还能识别几次、生成几次食谱。"""
    check_app_key(app_key)
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
    app_key: AppKey = None,
):
    """识别照片里的食物，返回每种食物的营养数据和整餐合计。"""
    check_app_key(app_key)
    ticket = acquire(analyze_guard, request, device_id, "拍照识别")

    # 多读 1 个字节：如果读到的比上限还多，说明照片太大。读不到合格的照片就把次数还回去
    data = photo.file.read(MAX_UPLOAD_BYTES + 1)
    if not data:
        analyze_guard.refund(ticket)
        raise HTTPException(status_code=400, detail="没有收到照片")
    if len(data) > MAX_UPLOAD_BYTES:
        analyze_guard.refund(ticket)
        raise HTTPException(status_code=413, detail=f"照片太大了，请上传 {MAX_UPLOAD_BYTES // 1024 // 1024} MB 以内的照片")

    return run_ai(analyze_guard, ticket, lambda: analyze_food_photo(data, lang))


@app.post("/recipes", response_model=RecipesResult)
def recipes(body: RecipeRequest, request: Request, device_id: DeviceID = None, app_key: AppKey = None):
    """根据目标、每日营养目标、偏好和忌口生成食谱。相同的请求 24 小时内直接返回缓存。"""
    check_app_key(app_key)
    device_key, ip_key = keys_for(request, device_id)

    # 「换一个」（带 exclude_names）要求结果不同，所以不用缓存
    cache_key = None if body.exclude_names else ResultCache.key_for(body.cache_payload())
    if cache_key and (cached := recipe_cache.get(cache_key)) is not None:
        return cached.model_copy(update={"from_cache": True, "remaining_today": recipe_guard.remaining(device_key, ip_key)})

    ticket = acquire(recipe_guard, request, device_id, "食谱推荐")
    result = run_ai(recipe_guard, ticket, lambda: generate_recipes(body))
    result.remaining_today = recipe_guard.remaining(device_key, ip_key)
    if cache_key:
        recipe_cache.set(cache_key, result)
    return result
