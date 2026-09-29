"""
食物识别的核心逻辑，分三步：
1. 整理照片：转正方向、缩小、统一转成 JPEG
2. 把照片发给 Claude，要求它严格按固定的 JSON 格式返回识别结果
3. 检查 AI 的结果：数值取整、去掉不合理的负数，再计算整餐合计

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

MAX_UPLOAD_BYTES = 15 * 1024 * 1024  # 允许上传的照片最大 15 MB
MAX_IMAGE_SIDE = 1024  # 发给 AI 之前，把照片的长边缩小到 1024 像素：更快，也更省钱


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
    """识别过程中出的错。status_code 是返回给 App 的 HTTP 状态码，message 是给用户看的说明。"""

    def __init__(self, status_code: int, message: str):
        super().__init__(message)
        self.status_code = status_code
        self.message = message


# ---------- 第 1 步：整理照片 ----------


def prepare_image(data: bytes) -> bytes:
    """把上传的照片整理成适合发给 AI 的 JPEG：转正方向、缩小、压缩。"""
    try:
        image = Image.open(io.BytesIO(data))
        # 手机拍的照片常常只带一个「旋转」标记，这里把像素真正转正，AI 才不会看到歪的图
        image = ImageOps.exif_transpose(image)
        # 统一转成 RGB（去掉透明背景），因为 JPEG 不支持透明
        image = image.convert("RGB")
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError):
        raise AIError(400, "无法读取这张图片，请上传 JPG、PNG 或 HEIC 格式的照片")

    # 等比例缩小，长边不超过 MAX_IMAGE_SIDE（本来就小的图不会被放大）
    image.thumbnail((MAX_IMAGE_SIDE, MAX_IMAGE_SIDE))
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=85)
    return buffer.getvalue()


# ---------- 第 2 步：调用 Claude ----------

LANGUAGE_NAMES = {"zh": "简体中文", "en": "English"}


def build_system_prompt(lang: str) -> str:
    """给 AI 的「工作说明」。想调整识别效果，主要就是改这里的规则。"""
    language = LANGUAGE_NAMES.get(lang, "简体中文")
    return f"""你是一名经验丰富的营养师，擅长根据照片估算一餐饭的营养成分。

请识别照片里的每一种食物，估算它的重量和营养，并遵守以下规则：
1. 按照片里实际能看到的份量估算。可以参考碗、盘子、筷子、手、包装等物体来判断大小。
2. 考虑烹饪方式：油炸、爆炒、红烧等做法会用不少油，要把油和酱汁的热量算进去。
3. 营养数值参考常见的食物成分数据。热量单位是千卡（kcal），重量和三大营养素的单位是克。
4. 一道菜算一项，不要拆成配料；米饭、面条、饮料等分开列出。
5. confidence 表示你的把握：看得清、很常见的食物用 high；份量或做法不太确定用 medium；看不清、只能猜测用 low。不要编造照片里没有的食物。
6. 如果照片里没有可以吃的食物（比如人物、风景、文件、空盘子），is_food 设为 false，items 为空列表，message 用一句话说明原因。
7. 如果有食物，is_food 设为 true，message 用一句话概括这一餐。
8. name 和 message 使用{language}。"""


_client: anthropic.Anthropic | None = None


def get_client() -> anthropic.Anthropic:
    """创建 Claude 客户端（只创建一次，之后重复使用）。API Key 从环境变量 ANTHROPIC_API_KEY 读取。"""
    global _client
    if _client is None:
        api_key = os.getenv("ANTHROPIC_API_KEY")
        if not api_key:
            raise AIError(500, "服务器没有配置 ANTHROPIC_API_KEY，请在 backend/.env 里填写后重启后端")
        _client = anthropic.Anthropic(
            api_key=api_key,
            # 明确使用官方地址，不受电脑上其他程序设置的 ANTHROPIC_BASE_URL 影响
            base_url="https://api.anthropic.com",
            timeout=60.0,  # 最多等 60 秒
            max_retries=1,  # 网络抖动时自动重试 1 次
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


def ask_claude(jpeg: bytes, lang: str) -> tuple[AIResult, str]:
    """把照片发给 Claude，拿回按 AIResult 格式整理好的识别结果，以及实际回答的模型名。"""
    client = get_client()
    started = time.monotonic()
    try:
        response = client.beta.messages.parse(
            model=MODEL,
            max_tokens=16000,
            system=build_system_prompt(lang),
            messages=[
                {
                    "role": "user",
                    "content": [
                        # 照片放在文字前面，Claude 的效果更好
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64.standard_b64encode(jpeg).decode("ascii"),
                            },
                        },
                        {"type": "text", "text": "请分析这张照片里的餐食。"},
                    ],
                }
            ],
            # 结构化输出：Claude 只会返回符合 AIResult 结构的 JSON，SDK 会自动把它转成 AIResult 对象
            output_format=AIResult,
            **model_options(MODEL),
        )
    # 下面按「从具体到笼统」的顺序处理各种出错情况
    except pydantic.ValidationError:
        # AI 返回的内容不是合格的 JSON（很少见，比如回答被截断）
        raise AIError(502, "AI 返回的结果格式不对，请重试")
    except anthropic.AuthenticationError:
        raise AIError(500, "ANTHROPIC_API_KEY 无效，请检查 backend/.env 里的 Key")
    except anthropic.PermissionDeniedError:
        raise AIError(500, "这个 API Key 没有权限使用该模型")
    except anthropic.NotFoundError:
        raise AIError(500, f"找不到模型 {MODEL}，请检查 .env 里的 FOOD_AI_MODEL")
    except anthropic.RateLimitError:
        raise AIError(429, "AI 服务太忙了，请稍后再试")
    except anthropic.BadRequestError as e:
        # 比如账户余额不足，Anthropic 会返回这类错误，把原因原样告诉你方便排查
        logger.error("Claude 拒绝了请求：%s", e.message)
        raise AIError(502, f"AI 服务拒绝了请求：{e.message}")
    except anthropic.APITimeoutError:
        raise AIError(504, "AI 识别超时，请重试")
    except anthropic.APIConnectionError:
        raise AIError(503, "连接不上 AI 服务，请检查网络")
    except anthropic.APIStatusError as e:
        logger.error("Claude 服务出错：%s %s", e.status_code, e.message)
        raise AIError(502, f"AI 服务出错（{e.status_code}），请稍后再试")

    # 在终端里打印这次的用时和 token 用量，方便你估算费用
    logger.info(
        "识别完成：模型 %s，用时 %.1f 秒，输入 %d token，输出 %d token，结束原因 %s",
        response.model,
        time.monotonic() - started,
        response.usage.input_tokens,
        response.usage.output_tokens,
        response.stop_reason,
    )

    # 先看 AI 为什么停下，再读结果
    if response.stop_reason == "refusal":
        raise AIError(422, "AI 无法处理这张图片，请换一张照片试试")
    if response.stop_reason == "max_tokens":
        raise AIError(502, "AI 的回答被截断了，请重试")
    if response.parsed_output is None:
        raise AIError(502, "AI 没有返回识别结果，请重试")
    # response.model 是实际回答的模型（触发备用模型时会和 MODEL 不同）
    return response.parsed_output, response.model


# ---------- 第 3 步：检查结果、计算合计 ----------


def build_result(ai: AIResult, model: str) -> AnalyzeResult:
    """整理 AI 的结果：数值取整、负数改成 0、去掉空名字，并由后端自己加总整餐合计。"""
    items = [
        FoodItem(
            name=item.name.strip() or "未知食物",
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
        message = message or "这张照片里好像没有食物"
    elif not items:
        message = "没有识别出具体的食物，请换个角度再拍一张"

    total = MealTotal(
        weight_g=round(sum(i.weight_g for i in items)),
        calories_kcal=round(sum(i.calories_kcal for i in items)),
        protein_g=round(sum(i.protein_g for i in items), 1),
        carbs_g=round(sum(i.carbs_g for i in items), 1),
        fat_g=round(sum(i.fat_g for i in items), 1),
    )
    return AnalyzeResult(
        is_food=bool(items),
        message=message or "识别完成",
        items=items,
        total=total,
        model=model,
    )


def analyze_food_photo(data: bytes, lang: str = "zh") -> AnalyzeResult:
    """完整流程：整理照片 → 问 Claude → 整理结果。"""
    jpeg = prepare_image(data)
    ai, model = ask_claude(jpeg, lang)
    return build_result(ai, model)
