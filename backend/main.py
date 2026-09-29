"""
后端入口：定义 App 要调用的网页接口（API）。

启动方法（在 backend 文件夹里运行）：
    uv run fastapi dev main.py
然后用浏览器打开 http://127.0.0.1:8000/docs 测试接口。

接口一览：
    GET  /health    检查后端是否在运行
    GET  /quota     查询这台设备今天还能识别几次、生成几次食谱
    POST /analyze   上传餐食照片，识别食物和营养
    POST /recipes   根据目标和忌口生成一日三餐
"""

import logging
import re
from typing import Annotated, Literal

from fastapi import FastAPI, File, Form, Header, HTTPException, Request, UploadFile

from food_ai import MAX_UPLOAD_BYTES, MODEL, AIError, AnalyzeResult, analyze_food_photo
from limits import DailyLimiter, ResultCache
from recipes_ai import RecipeRequest, RecipesResult, generate_recipes

# 让各模块的日志（用时、token 用量）显示在终端里
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
# 开发模式会监视文件改动，它的「检测到 N 处变化」提示没什么用，关掉
logging.getLogger("watchfiles").setLevel(logging.WARNING)

# ---------- 费用控制：每台设备 24 小时内的次数上限，以及食谱缓存 ----------
ANALYZE_PER_DAY = 15
RECIPES_PER_DAY = 5
analyze_limiter = DailyLimiter(ANALYZE_PER_DAY)
recipe_limiter = DailyLimiter(RECIPES_PER_DAY)
recipe_cache = ResultCache(ttl_seconds=24 * 3600)

app = FastAPI(
    title="饮食记录 App 后端",
    description="上传餐食照片识别营养，或根据目标生成一日三餐食谱。",
    version="0.2.0",
)

# App 在请求头 X-Device-ID 里带上自己的设备 ID（第一次启动时随机生成），用来计次
DeviceID = Annotated[str | None, Header(alias="X-Device-ID", description="App 的设备 ID")]
DEVICE_ID_PATTERN = re.compile(r"^[A-Za-z0-9-]{8,64}$")


def client_key(request: Request, device_id: str | None) -> str:
    """计次用的钥匙：有合法的设备 ID 就用它，否则用来访者的 IP"""
    if device_id and DEVICE_ID_PATTERN.match(device_id):
        return f"device:{device_id}"
    return f"ip:{request.client.host if request.client else 'unknown'}"


def check_quota(limiter: DailyLimiter, key: str, what: str, per_day: int) -> None:
    """次数用完就直接拒绝，不调用 AI"""
    if limiter.remaining(key) > 0:
        return
    wait = limiter.retry_after_seconds(key)
    hours = max(1, -(-wait // 3600))  # 向上取整
    raise HTTPException(
        status_code=429,
        detail=f"{what}的次数用完了（每 24 小时最多 {per_day} 次），大约 {hours} 小时后可以再用",
        headers={"Retry-After": str(wait)},
    )


@app.get("/")
def home():
    """首页：提示去 /docs 测试接口。"""
    return {"message": "后端正在运行。打开 /docs 可以测试接口。"}


@app.get("/health")
def health():
    """检查后端是否在运行，并显示当前用的模型。"""
    return {"status": "ok", "model": MODEL}


@app.get("/quota")
def quota(request: Request, device_id: DeviceID = None):
    """这台设备今天还能识别几次、生成几次食谱。"""
    key = client_key(request, device_id)
    return {
        "analyze_remaining": analyze_limiter.remaining(key),
        "analyze_per_day": ANALYZE_PER_DAY,
        "recipes_remaining": recipe_limiter.remaining(key),
        "recipes_per_day": RECIPES_PER_DAY,
    }


@app.post("/analyze", response_model=AnalyzeResult)
def analyze(
    request: Request,
    photo: Annotated[UploadFile, File(description="餐食照片（JPG、PNG 或 HEIC）")],
    lang: Annotated[Literal["zh", "en"], Form(description="结果语言：zh 中文，en 英文")] = "zh",
    device_id: DeviceID = None,
):
    """识别照片里的食物，返回每种食物的营养数据和整餐合计。"""
    key = client_key(request, device_id)
    check_quota(analyze_limiter, key, "拍照识别", ANALYZE_PER_DAY)

    # 多读 1 个字节：如果读到的比上限还多，说明照片太大
    data = photo.file.read(MAX_UPLOAD_BYTES + 1)
    if not data:
        raise HTTPException(status_code=400, detail="没有收到照片")
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="照片太大了，请上传 15 MB 以内的照片")

    try:
        result = analyze_food_photo(data, lang)
    except AIError as e:
        # 出错时统一返回 {"detail": "给用户看的说明"}，App 直接显示这句话就行
        raise HTTPException(status_code=e.status_code, detail=e.message)
    analyze_limiter.record(key)  # 成功了才算一次
    return result


@app.post("/recipes", response_model=RecipesResult)
def recipes(body: RecipeRequest, request: Request, device_id: DeviceID = None):
    """根据目标、每日营养目标、偏好和忌口生成食谱。相同的请求 24 小时内直接返回缓存。"""
    key = client_key(request, device_id)

    # 「换一个」（带 exclude_names）要求结果不同，所以不用缓存
    cache_key = None if body.exclude_names else ResultCache.key_for(body.cache_payload())
    if cache_key and (cached := recipe_cache.get(cache_key)) is not None:
        return cached.model_copy(update={"from_cache": True, "remaining_today": recipe_limiter.remaining(key)})

    check_quota(recipe_limiter, key, "食谱推荐", RECIPES_PER_DAY)
    try:
        result = generate_recipes(body)
    except AIError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)
    recipe_limiter.record(key)
    result.remaining_today = recipe_limiter.remaining(key)
    if cache_key:
        recipe_cache.set(cache_key, result)
    return result
