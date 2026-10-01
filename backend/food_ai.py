"""
食物识别的核心逻辑，分三步：
1. 整理照片：转正方向、缩小、统一转成 JPEG
2. 把照片发给 Claude，要求它严格按固定的 JSON 格式返回识别结果
3. 检查 AI 的结果：数值取整、去掉不合理的负数，再计算整餐合计

一餐可以有 1～4 张照片（比如整桌一张、单个菜的特写一张）：几张照片一起发给 Claude，
要求它把几张照片当成同一餐，同一份食物在不同照片里出现只算一次，最后只返回一份结果。
只有 1 张照片时，发给 AI 的内容和以前完全一样。

这个文件只管「识别」，网页接口相关的代码在 main.py 里。
"""

import base64
import io
import logging
import os
import time
from typing import Literal

import anthropic
import pydantic
from dotenv import load_dotenv
from PIL import Image, ImageOps, UnidentifiedImageError
from pillow_heif import register_heif_opener
from pydantic import BaseModel, Field

import messages
from messages import Lang

# 读取 backend/.env 文件里的配置（API Key 等），放进环境变量。
# override=True：如果电脑上已经有同名的环境变量，以 .env 里写的为准
load_dotenv(override=True)

# 让 Pillow 也能打开 iPhone 常用的 HEIC 格式照片
register_heif_opener()

logger = logging.getLogger("food_ai")

# ---------- 配置：都可以在 .env 里修改，改完要重启后端 ----------
# 变量名故意不用 CLAUDE_ 开头：Claude Code 等工具自己会设置 CLAUDE_ 开头的环境变量，避免撞名

# 用哪个 Claude 模型。默认 Opus 5.5（识别最准）；想省钱可以改成 claude-haiku-4-5
MODEL = os.getenv("FOOD_AI_MODEL") or "claude-opus-5-5"

# 思考深度：low / medium / high。越高越慢、越贵；识别食物一般 low 就够
EFFORT = os.getenv("FOOD_AI_EFFORT") or "low"

# 在 Render 上运行时，Render 会自动设置环境变量 RENDER=true
ON_RENDER = os.getenv("RENDER") == "true"

# App 上传前已经把照片压缩到 1024 像素（约 100～300 KB），5 MB 足够宽松；再大的多半是攻击。
# 一次上传几张照片时，这是所有照片加起来的上限（4 张压缩后的照片一般也不到 1.5 MB）
MAX_UPLOAD_BYTES = 5 * 1024 * 1024
# 一餐最多几张照片：再多 AI 也很难对得上哪些是同一份食物，费用也会成倍增加
MAX_PHOTOS = 4
# 照片像素数上限：一张几 MB 的照片解压后可能有上亿个像素，会把只有 512 MB 内存的服务器撑爆。
# 先读文件头里写的尺寸，超过这个数就不解压。16,000,000 像素还允许 1200 万像素的 iPhone 原图
MAX_IMAGE_PIXELS = 16_000_000
MAX_IMAGE_SIDE = 1024  # 发给 AI 之前，把照片的长边缩小到 1024 像素：更快，也更省钱

# 单次调用最多让 AI 输出多少 token（含思考）。这是「单次最高花费」的上限：
# 正常识别只输出 130～430 token，食谱 300～1100 token，这里留了约 3 倍的余量
# （识别最多约 3 美分、食谱最多约 6 美分；万一碰到上限会返回「回答被截断」，重试即可）
MAX_TOKENS_ANALYZE = 1500
MAX_TOKENS_RECIPES = 3000


# ---------- 数据格式：AI 必须按这个结构返回 ----------
# Field 里的 description 会一起发给 AI，告诉它每个字段是什么意思


class FoodItem(BaseModel):
    """照片里的一种食物"""

    name: str = Field(description="食物名称，例如：米饭、宫保鸡丁")
    weight_g: float = Field(description="估算的重量，单位：克")
    calories_kcal: float = Field(description="热量，单位：千卡（kcal）")
    protein_g: float = Field(description="蛋白质，单位：克")
    carbs_g: float = Field(description="碳水化合物，单位：克")
    fat_g: float = Field(description="脂肪，单位：克")
    confidence: Literal["high", "medium", "low"] = Field(
        description="识别可信度：high 很有把握，medium 基本确定，low 只能猜测"
    )


class AIResult(BaseModel):
    """要求 Claude 返回的完整 JSON"""

    is_food: bool = Field(description="照片里有没有可以吃的食物")
    message: str = Field(description="给用户看的一句话：有食物时概括这一餐，没有食物时说明原因")
    items: list[FoodItem] = Field(description="识别出的每一种食物；没有食物时为空列表")


class MealTotal(BaseModel):
    """整餐合计（由后端自己加总，不依赖 AI 算术）"""

    weight_g: float
    calories_kcal: float
    protein_g: float
    carbs_g: float
    fat_g: float


class AnalyzeResult(BaseModel):
    """/analyze 接口最终返回给 App 的 JSON"""

    is_food: bool
    message: str
    items: list[FoodItem]
    total: MealTotal
    model: str  # 这次用的是哪个模型，方便以后对比不同模型的效果


class AIError(Exception):
    """识别或生成食谱时出的错。status_code 是返回给 App 的 HTTP 状态码。

    key 是给用户看的说明（messages.py 里的一条），params 是要填进说明里的数字和名字；
    说明用中文还是英文，要到回复 App 的时候才按请求头决定（message_for）。

    billed 表示这次失败有没有可能已经花了钱：没花钱的（比如照片读不了、连不上 AI）
    会把用户当天的次数还回去；可能已经花了钱的（比如超时、返回格式不对）不还。

    dev 是只在本地开发时显示的详细排查提示（中文）；部署到网上后只给通用说明，不向陌生人透露内部配置。
    """

    def __init__(self, status_code: int, key: str, *, billed: bool = True, dev: str | None = None, **params):
        super().__init__(key)
        self.status_code = status_code
        self.key = key
        self.billed = billed
        self.dev = dev
        self.params = params

    def message_for(self, lang: Lang) -> str:
        """给用户看的说明，lang 是 zh 或 en"""
        if self.dev and not ON_RENDER:
            return self.dev
        return messages.text(self.key, lang, **self.params)


# ---------- 第 1 步：整理照片 ----------


def prepare_image(data: bytes) -> bytes:
    """把上传的照片整理成适合发给 AI 的 JPEG：转正方向、缩小、压缩。"""
    try:
        image = Image.open(io.BytesIO(data))  # 这一步只读文件头，还没有解压整张图
        if image.width * image.height > MAX_IMAGE_PIXELS:
            raise AIError(400, "too_many_pixels", billed=False)
        # 手机拍的照片常常只带一个「旋转」标记，这里把像素真正转正，AI 才不会看到歪的图
        image = ImageOps.exif_transpose(image)
        # 统一转成 RGB（去掉透明背景），因为 JPEG 不支持透明
        image = image.convert("RGB")
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError):
        raise AIError(400, "unreadable_image", billed=False)

    # 等比例缩小，长边不超过 MAX_IMAGE_SIDE（本来就小的图不会被放大）
    image.thumbnail((MAX_IMAGE_SIDE, MAX_IMAGE_SIDE))
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=85)
    return buffer.getvalue()


# ---------- 第 2 步：调用 Claude ----------

LANGUAGE_NAMES = {"zh": "简体中文", "en": "English"}


# 几张照片时加在规则最后的说明。英文那段是产品要求的原话，和中文的做法说明一起发给 AI
MULTI_PHOTO_RULE = (
    "Multiple photos may contain the same food from different angles or close-up views. "
    "Treat all uploaded images as one meal session. "
    "Merge duplicate food entities across images before estimating quantity, calories, and macros. "
    "Do not double-count the same item simply because it appears in multiple images."
)


def build_system_prompt(lang: str, photo_count: int = 1) -> str:
    """给 AI 的「工作说明」。想调整识别效果，主要就是改这里的规则。
    photo_count 是这一餐有几张照片：超过 1 张时，多加一条「几张照片算同一餐、同一份食物只算一次」的规则。"""
    language = LANGUAGE_NAMES.get(lang, "简体中文")
    prompt = f"""你是一名经验丰富的营养师，擅长根据照片估算一餐饭的营养成分。

请识别照片里的每一种食物，估算它的重量和营养，并遵守以下规则：
1. 按照片里实际能看到的份量估算。可以参考碗、盘子、筷子、手、包装等物体来判断大小。
2. 考虑烹饪方式：油炸、爆炒、红烧等做法会用不少油，要把油和酱汁的热量算进去。
3. 营养数值参考常见的食物成分数据。热量单位是千卡（kcal），重量和三大营养素的单位是克。
4. 一道菜算一项，不要拆成配料；米饭、面条、饮料等分开列出。
5. confidence 表示你的把握：看得清、很常见的食物用 high；份量或做法不太确定用 medium；看不清、只能猜测用 low。不要编造照片里没有的食物；看不出是什么的东西不要硬猜成某种食物，不要列进 items，可以在 message 里提醒用户手动补上。
6. 如果照片里没有可以吃的食物（比如人物、风景、文件、空盘子），is_food 设为 false，items 为空列表，message 用一句话说明原因。
7. 如果有食物，is_food 设为 true，message 用一句话概括这一餐。
8. name 和 message 使用{language}。"""
    if photo_count <= 1:
        return prompt
    return prompt + f"""
9. 这一餐一共有 {photo_count} 张照片（按上传顺序是照片 1 到照片 {photo_count}）。{MULTI_PHOTO_RULE}
   具体做法：先在所有照片里找出同一份食物（同一碗米饭的全景和特写算同一项），合并之后再估算份量；份量以看得最清楚的那张为准，其他角度用来帮助判断大小。只有明显是不同的食物，或者明显是两份，才分开列出。message 概括整餐，不要按照片分别描述。"""


_client: anthropic.Anthropic | None = None


def get_client() -> anthropic.Anthropic:
    """创建 Claude 客户端（只创建一次，之后重复使用）。API Key 从环境变量 ANTHROPIC_API_KEY 读取。"""
    global _client
    if _client is None:
        api_key = os.getenv("ANTHROPIC_API_KEY")
        if not api_key:
            logger.error("没有配置 ANTHROPIC_API_KEY")
            raise AIError(
                500, "unavailable", billed=False, dev="服务器没有配置 ANTHROPIC_API_KEY，请在 backend/.env 里填写后重启后端"
            )
        _client = anthropic.Anthropic(
            api_key=api_key,
            # 明确使用官方地址，不受电脑上其他程序设置的 ANTHROPIC_BASE_URL 影响
            base_url="https://api.anthropic.com",
            timeout=60.0,  # 最多等 60 秒
            # 本地开发时网络抖动自动重试 1 次；部署后不重试，让服务器比 App（120 秒超时）先放弃。
            # 否则 App 显示超时、用户再点一次，而服务器还在替上一次请求花钱
            max_retries=0 if ON_RENDER else 1,
        )
    return _client


def model_options(model: str) -> dict:
    """不同模型支持的参数不一样，这里按模型挑选。"""
    if model.startswith("claude-haiku"):
        # Haiku 不支持 effort 参数和服务器端的备用模型，只用最基本的参数
        return {}
    return {
        # effort 控制 AI 思考多久：low 更快、更省钱
        "output_config": {"effort": EFFORT},
        # 万一 AI 因为安全策略拒绝处理，由 Anthropic 自动换一个合适的模型重试（一般用不到）
        "betas": ["server-side-fallback-2026-07-01"],
        "fallbacks": "default",
    }


def call_claude(*, system: str, content: list, output_format: type, max_tokens: int, feature: str):
    """调用 Claude，并把回答解析成 output_format 指定的格式。识别和食谱共用这一个函数：
    统一处理各种出错情况、打印用量日志，并限制单次最多输出多少 token（控制单次最高花费）。
    feature 是 "analyze"（识别）或 "recipes"（生成食谱），用在日志和出错说明里。返回（解析好的结果，实际回答的模型名）。"""
    client = get_client()
    started = time.monotonic()
    try:
        response = client.beta.messages.parse(
            model=MODEL,
            max_tokens=max_tokens,
            system=system,
            messages=[{"role": "user", "content": content}],
            # 结构化输出：Claude 只会返回符合 output_format 结构的 JSON，SDK 会自动转成对应的对象
            output_format=output_format,
            **model_options(MODEL),
        )
    # 下面按「从具体到笼统」的顺序处理各种出错情况。
    # 详细原因只写进服务器日志；对外只给通用说明，不向陌生人透露内部信息
    except pydantic.ValidationError:
        # AI 返回的内容不是合格的 JSON（很少见，比如回答被截断）
        raise AIError(502, "ai_bad_format")
    except anthropic.AuthenticationError:
        logger.error("ANTHROPIC_API_KEY 无效")
        raise AIError(500, "unavailable", billed=False, dev="ANTHROPIC_API_KEY 无效，请检查 backend/.env 里的 Key")
    except anthropic.PermissionDeniedError:
        logger.error("这个 API Key 没有权限使用模型 %s", MODEL)
        raise AIError(500, "unavailable", billed=False, dev="这个 API Key 没有权限使用该模型")
    except anthropic.NotFoundError:
        logger.error("找不到模型 %s", MODEL)
        raise AIError(500, "unavailable", billed=False, dev=f"找不到模型 {MODEL}，请检查 .env 里的 FOOD_AI_MODEL")
    except anthropic.RateLimitError:
        # Anthropic 那边限速，或者账号的每月花费上限到了（这种情况没有 retry-after）
        logger.error("Claude 限速或达到花费上限")
        raise AIError(429, "ai_busy", billed=False)
    except anthropic.BadRequestError as e:
        # 你自己在控制台设的每月花费上限用完、账户余额不足等，都会走到这里
        message = (e.message or "").lower()
        logger.error("Claude 拒绝了请求：%s", e.message)
        if "specified" in message and "limit" in message:
            raise AIError(503, "ai_quota_used_up", billed=False)
        if "credit balance" in message:
            raise AIError(503, "unavailable", billed=False)
        raise AIError(502, "ai_cannot_process", billed=False)
    except anthropic.APITimeoutError:
        raise AIError(504, "ai_timeout", feature=feature)
    except anthropic.APIConnectionError:
        raise AIError(503, "ai_connect_failed", billed=False)
    except anthropic.APIStatusError as e:
        logger.error("Claude 服务出错：%s %s", e.status_code, e.message)
        raise AIError(502, "ai_error")
    except anthropic.APIError as e:
        # SDK 里其他没单独处理的错误（比如返回的内容不符合预期），也当作服务出错
        logger.error("Claude 调用出错：%s", e)
        raise AIError(502, "ai_error")

    # 在日志里打印这次的用时和 token 用量，方便你估算费用
    logger.info(
        "%s完成：模型 %s，用时 %.1f 秒，输入 %d token，输出 %d token，结束原因 %s",
        messages.ACTIONS[feature]["zh"],
        response.model,
        time.monotonic() - started,
        response.usage.input_tokens,
        response.usage.output_tokens,
        response.stop_reason,
    )

    # 先看 AI 为什么停下，再读结果
    if response.stop_reason == "refusal":
        raise AIError(422, "ai_refusal")
    if response.stop_reason == "max_tokens":
        raise AIError(502, "ai_truncated")
    if response.parsed_output is None:
        raise AIError(502, "ai_empty")
    # response.model 是实际回答的模型（触发备用模型时会和 MODEL 不同）
    return response.parsed_output, response.model


def image_block(jpeg: bytes) -> dict:
    """一张照片在发给 Claude 的内容里的写法"""
    return {
        "type": "image",
        "source": {
            "type": "base64",
            "media_type": "image/jpeg",
            "data": base64.standard_b64encode(jpeg).decode("ascii"),
        },
    }


def build_content(jpegs: list[bytes]) -> list:
    """发给 Claude 的内容：照片放在文字前面（Claude 的效果更好）。
    只有 1 张照片时和以前完全一样；几张照片时每张前面标上「照片 N」，最后说明这些是同一餐"""
    if len(jpegs) == 1:
        return [image_block(jpegs[0]), {"type": "text", "text": "请分析这张照片里的餐食。"}]
    content: list = []
    for number, jpeg in enumerate(jpegs, start=1):
        content.append({"type": "text", "text": f"照片 {number}："})
        content.append(image_block(jpeg))
    content.append(
        {
            "type": "text",
            "text": f"这 {len(jpegs)} 张照片是同一餐。请把它们当作一餐来分析：同一份食物在几张照片里出现，只算一次。",
        }
    )
    return content


def ask_claude(jpegs: list[bytes], lang: str) -> tuple[AIResult, str]:
    """把一餐的照片（1～4 张）一起发给 Claude，拿回按 AIResult 格式整理好的识别结果，以及实际回答的模型名。"""
    return call_claude(
        system=build_system_prompt(lang, photo_count=len(jpegs)),
        content=build_content(jpegs),
        output_format=AIResult,
        max_tokens=MAX_TOKENS_ANALYZE,
        feature="analyze",
    )


# ---------- 第 3 步：检查结果、计算合计 ----------


def build_result(ai: AIResult, model: str, lang: Lang = "zh") -> AnalyzeResult:
    """整理 AI 的结果：数值取整、负数改成 0、去掉空名字，并由后端自己加总整餐合计。
    AI 没写名字、没写总结时补上的默认文字，用结果的语言 lang。"""
    items = [
        FoodItem(
            name=item.name.strip() or messages.text("unknown_food", lang),
            weight_g=round(max(item.weight_g, 0)),
            calories_kcal=round(max(item.calories_kcal, 0)),
            protein_g=round(max(item.protein_g, 0), 1),
            carbs_g=round(max(item.carbs_g, 0), 1),
            fat_g=round(max(item.fat_g, 0), 1),
            confidence=item.confidence,
        )
        for item in ai.items
    ]

    message = ai.message.strip()
    if not ai.is_food:
        items = []  # 不是食物时，不返回任何食物项
        message = message or messages.text("result_not_food", lang)
    elif not items:
        message = messages.text("result_no_items", lang)

    total = MealTotal(
        weight_g=round(sum(i.weight_g for i in items)),
        calories_kcal=round(sum(i.calories_kcal for i in items)),
        protein_g=round(sum(i.protein_g for i in items), 1),
        carbs_g=round(sum(i.carbs_g for i in items), 1),
        fat_g=round(sum(i.fat_g for i in items), 1),
    )
    return AnalyzeResult(
        is_food=bool(items),
        message=message or messages.text("result_done", lang),
        items=items,
        total=total,
        model=model,
    )


def analyze_food_photos(photos: list[bytes], lang: Lang = "zh") -> AnalyzeResult:
    """完整流程：整理每一张照片 → 一起问 Claude → 整理成一份结果。
    photos 是同一餐的 1～4 张照片；lang 是结果（食物名称和总结）用的语言"""
    if not photos:
        raise AIError(400, "no_photo", billed=False)
    if len(photos) > MAX_PHOTOS:
        raise AIError(400, "too_many_photos", billed=False, max=MAX_PHOTOS)
    # 一张一张地整理：同一时间只有一张大图在内存里
    jpegs = [prepare_image(data) for data in photos]
    ai, model = ask_claude(jpegs, lang)
    return build_result(ai, model, lang)


def analyze_food_photo(data: bytes, lang: Lang = "zh") -> AnalyzeResult:
    """只有一张照片时的写法（和以前一样）"""
    return analyze_food_photos([data], lang)
