"""
饭后拍剩下的：用户先记了一餐（拍照识别或手动添加），结果没吃完。吃完以后拍一张剩下的，
AI 对照「这餐原来有什么、各约多少克」，估算每一样吃掉了几成。

只返回比例，不重新估算营养：App 拿原来记的营养乘上吃掉的比例。
剩菜照片里看不清的细节不会把原来的估算带偏，要 AI 输出的内容也少很多（更快、更省钱）。

这个文件只管「估算剩下多少」，网页接口在 main.py 里（/leftovers）。
"""

import json
import logging

import pydantic
from pydantic import BaseModel, Field, field_validator

import messages
from food_ai import AIError, call_claude, image_block, prepare_image
from messages import Lang

logger = logging.getLogger("leftovers_ai")

# 一餐最多几样：再多的话一般是手动记了很多零碎的东西，AI 也很难一一对上
MAX_ITEMS = 20
# 单次最多输出多少 token：正常 100～300，留了几倍余量（最多约 3 美分）
MAX_TOKENS_LEFTOVERS = 1000

LANGUAGE_NAMES = {"zh": "简体中文", "en": "English"}


class ServedItem(BaseModel):
    """这一餐原来记的一样食物（App 发来的）"""

    name: str = Field(min_length=1, max_length=60)
    weight_g: float | None = Field(default=None, ge=0, le=5000)

    @field_validator("name")
    @classmethod
    def tidy_name(cls, value: str) -> str:
        value = " ".join(value.split())  # 去掉多余的空格和换行
        if not value:
            raise ValueError("名称不能为空")
        return value


_served_list = pydantic.TypeAdapter(list[ServedItem])


def parse_served_items(raw: str) -> list[ServedItem]:
    """把 App 发来的 JSON 文字转成清单。格式不对、空清单、超过 MAX_ITEMS 样都抛出 ValueError，由调用的地方拒绝"""
    try:
        items = _served_list.validate_python(json.loads(raw))
    except (ValueError, pydantic.ValidationError):
        raise ValueError("bad items")
    if not 1 <= len(items) <= MAX_ITEMS:
        raise ValueError("bad items")
    return items


class LeftoverItem(BaseModel):
    """AI 对清单里一样食物的判断"""

    index: int = Field(description="这一样在清单里的序号（从 1 开始）")
    eaten_fraction: float = Field(description="吃掉了几成：0 = 基本没动，0.5 = 吃了一半，1 = 吃完了")


class LeftoverAIResult(BaseModel):
    """要求 Claude 返回的 JSON"""

    is_leftover_photo: bool = Field(description="照片里是不是这一餐吃剩的食物，或者吃完以后的空碗空盘")
    message: str = Field(description="给用户看的一句话：概括每样吃了多少；照片不对时说明原因")
    items: list[LeftoverItem] = Field(description="清单里每一样的判断；照片不对时为空列表")


class LeftoversResult(BaseModel):
    """/leftovers 接口返回给 App 的 JSON"""

    is_leftover_photo: bool
    message: str
    eaten: list[float]  # 和请求里的清单一一对应：每样吃掉了几成（0～1，取到 0.05）；照片不对时是空列表
    model: str
    remaining_today: int | None = None  # 今天还能拍照识别几次（和拍照识别共用次数）


def build_system_prompt(items: list[ServedItem], lang: str) -> str:
    """给 AI 的说明：原来的清单 + 判断规则"""
    language = LANGUAGE_NAMES.get(lang, "简体中文")
    lines = "\n".join(
        f"{number}. {item.name}" + (f"，约 {round(item.weight_g)} 克" if item.weight_g else "")
        for number, item in enumerate(items, start=1)
    )
    return f"""你是一名经验丰富的营养师。用户吃饭前记下了这一餐，原来的食物和份量是：
{lines}

用户吃完以后拍了一张照片，照片里是剩下的部分（也可能已经吃光、只剩空碗空盘）。请判断清单里每一样吃掉了几成，并遵守以下规则：
1. eaten_fraction 在 0 到 1 之间：1 = 吃完了，0.75 = 吃了大约四分之三，0.5 = 吃了一半，0.25 = 只吃了一点，0 = 基本没动。
2. 参考原来的份量来估算：比如原来约 200 克的菜，照片里还剩大约 50 克，就是吃掉了 0.75。可以参考碗、盘子、筷子判断剩下多少。
3. 骨头、虾壳、果皮、汤底、葱姜这类本来就不吃的东西，不算剩下。
4. 照片里看不到的那一样，按吃完算（1）。如果照片明显只拍到了其中一部分，在 message 里提醒用户核对没拍到的。
5. 清单里每一样都要返回，index 对应上面的序号。
6. 如果照片里不是吃剩的食物或餐具（比如人物、风景、文件），is_leftover_photo 设为 false，items 为空列表，message 用一句话说明原因。
7. message 用一句话概括，比如「米饭吃完了，宫保鸡丁剩了大约四分之一」，使用{language}。"""


def build_content(jpeg: bytes) -> list:
    """照片放在文字前面（Claude 的效果更好）"""
    return [image_block(jpeg), {"type": "text", "text": "这是这一餐吃完以后剩下的。"}]


def build_result(ai: LeftoverAIResult, count: int, model: str, lang: Lang = "zh") -> LeftoversResult:
    """整理 AI 的结果：比例限制在 0～1、取到 0.05；清单里没提到的那一样按吃完算（和规则 4 一致）"""
    message = ai.message.strip()
    if not ai.is_leftover_photo:
        return LeftoversResult(
            is_leftover_photo=False,
            message=message or messages.text("leftovers_not_photo", lang),
            eaten=[],
            model=model,
        )
    eaten = [1.0] * count
    for item in ai.items:
        if 1 <= item.index <= count:
            fraction = min(max(item.eaten_fraction, 0.0), 1.0)
            eaten[item.index - 1] = round(fraction * 20) / 20
    return LeftoversResult(
        is_leftover_photo=True,
        message=message or messages.text("leftovers_done", lang),
        eaten=eaten,
        model=model,
    )


def estimate_leftovers(photo: bytes, items: list[ServedItem], lang: Lang = "zh") -> LeftoversResult:
    """完整流程：整理照片 → 连同原来的清单一起问 Claude → 整理成每样吃掉几成"""
    if not photo:
        raise AIError(400, "no_photo", billed=False)
    jpeg = prepare_image(photo)
    ai, model = call_claude(
        system=build_system_prompt(items, lang),
        content=build_content(jpeg),
        output_format=LeftoverAIResult,
        max_tokens=MAX_TOKENS_LEFTOVERS,
        feature="leftovers",
    )
    return build_result(ai, len(items), model, lang)
