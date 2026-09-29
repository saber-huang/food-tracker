"""
食谱推荐：根据用户的目标、每日营养目标、偏好和忌口，让 Claude 生成一日三餐。

流程：
1. 把每日目标按 早餐 30% / 午餐 40% / 晚餐 30% 拆成每一餐的目标
2. 把目标、偏好、忌口、烹饪时间写进提示词，要求 Claude 严格按固定 JSON 格式返回
3. 检查结果：忌口和过敏食材绝对不能出现；出现了就让 AI 重做一次，还不行就报错
"""

import logging
import time
from typing import Literal

import anthropic
import pydantic
from pydantic import BaseModel, Field, field_validator

from food_ai import EFFORT, MODEL, AIError, get_client, model_options

logger = logging.getLogger("recipes_ai")

Meal = Literal["breakfast", "lunch", "dinner"]
ALL_MEALS: list[Meal] = ["breakfast", "lunch", "dinner"]

# 每一餐占全天热量和营养素的比例
MEAL_SHARES: dict[str, float] = {"breakfast": 0.30, "lunch": 0.40, "dinner": 0.30}
MEAL_NAMES = {
    "zh": {"breakfast": "早餐", "lunch": "午餐", "dinner": "晚餐"},
    "en": {"breakfast": "Breakfast", "lunch": "Lunch", "dinner": "Dinner"},
}
GOAL_NAMES = {
    "zh": {"loseFat": "减脂", "maintain": "维持体重", "gainMuscle": "增肌"},
    "en": {"loseFat": "fat loss", "maintain": "maintenance", "gainMuscle": "muscle gain"},
}


# ---------- App 发来的请求 ----------


class RecipeRequest(BaseModel):
    goal: Literal["loseFat", "maintain", "gainMuscle"]
    daily_calories: float = Field(ge=800, le=8000, description="每日热量目标（千卡）")
    daily_protein_g: float = Field(ge=0, le=600)
    daily_carbs_g: float = Field(ge=0, le=1500)
    daily_fat_g: float = Field(ge=0, le=500)
    preferences: str = Field(default="", max_length=300, description="饮食偏好，自由填写")
    allergies: list[str] = Field(default_factory=list, max_length=20, description="过敏食材")
    dislikes: list[str] = Field(default_factory=list, max_length=20, description="忌口")
    max_cooking_minutes: int = Field(default=30, ge=5, le=180, description="每餐可接受的烹饪时间（分钟）")
    meals: list[Meal] = Field(default_factory=lambda: list(ALL_MEALS), description="要生成哪几餐")
    exclude_names: list[str] = Field(default_factory=list, max_length=30, description="「换一个」时要避开的菜名")
    lang: Literal["zh", "en"] = "zh"

    @field_validator("allergies", "dislikes", "exclude_names")
    @classmethod
    def clean_terms(cls, terms: list[str]) -> list[str]:
        """去掉空白和重复，每一项最多 30 个字"""
        cleaned: list[str] = []
        for term in terms:
            term = term.strip()[:30]
            if term and term not in cleaned:
                cleaned.append(term)
        return cleaned

    @field_validator("meals")
    @classmethod
    def unique_meals(cls, meals: list[Meal]) -> list[Meal]:
        ordered = [m for m in ALL_MEALS if m in meals]
        if not ordered:
            raise ValueError("至少要选一餐")
        return ordered

    def cache_payload(self) -> dict:
        """用来算缓存指纹的内容：数值取整，避免 1463.28 和 1463.30 被当成两个不同的请求"""
        return {
            "goal": self.goal,
            "calories": round(self.daily_calories / 10) * 10,
            "protein": round(self.daily_protein_g / 5) * 5,
            "carbs": round(self.daily_carbs_g / 5) * 5,
            "fat": round(self.daily_fat_g / 5) * 5,
            "preferences": " ".join(self.preferences.split()).casefold(),
            "allergies": sorted(a.casefold() for a in self.allergies),
            "dislikes": sorted(d.casefold() for d in self.dislikes),
            "minutes": self.max_cooking_minutes,
            "meals": self.meals,
            "lang": self.lang,
        }


# ---------- 要求 Claude 返回的格式 ----------


class Ingredient(BaseModel):
    name: str = Field(description="食材名称")
    grams: float = Field(description="用量，单位克（按生重计算）")


class Recipe(BaseModel):
    meal: Meal = Field(description="这道菜属于哪一餐：breakfast、lunch 或 dinner")
    name: str = Field(description="菜名")
    ingredients: list[Ingredient] = Field(description="食材及克数，3～8 种")
    steps: list[str] = Field(description="简要做法，3～6 步，每步一句话")
    cooking_minutes: int = Field(description="从准备到做好大约需要的分钟数")
    calories_kcal: float = Field(description="这一餐的热量（千卡）")
    protein_g: float = Field(description="蛋白质（克）")
    carbs_g: float = Field(description="碳水化合物（克）")
    fat_g: float = Field(description="脂肪（克）")


class AIRecipes(BaseModel):
    recipes: list[Recipe] = Field(description="每一餐一道菜（或一套搭配）")


class RecipesResult(BaseModel):
    """/recipes 接口最终返回给 App 的 JSON"""

    recipes: list[Recipe]
    model: str
    from_cache: bool = False  # 是不是直接用的缓存
    remaining_today: int = 0  # 今天还能生成几次


# ---------- 提示词 ----------


def meal_targets_text(req: RecipeRequest) -> str:
    """把每日目标拆到每一餐，写成一段文字"""
    names = MEAL_NAMES[req.lang]
    lines = []
    for meal in req.meals:
        share = MEAL_SHARES[meal]
        lines.append(
            f"- {names[meal]}（{meal}）：约 {req.daily_calories * share:.0f} 千卡，"
            f"蛋白质 {req.daily_protein_g * share:.0f} 克、碳水 {req.daily_carbs_g * share:.0f} 克、脂肪 {req.daily_fat_g * share:.0f} 克"
            if req.lang == "zh"
            else f"- {names[meal]} ({meal}): about {req.daily_calories * share:.0f} kcal, "
            f"protein {req.daily_protein_g * share:.0f} g, carbs {req.daily_carbs_g * share:.0f} g, fat {req.daily_fat_g * share:.0f} g"
        )
    return "\n".join(lines)


def build_system_prompt(lang: str) -> str:
    """给 AI 的「工作说明」。想调整食谱风格，主要就是改这里。"""
    language = "简体中文" if lang == "zh" else "English"
    return f"""你是一名擅长家常菜的注册营养师，为健身人群设计一日三餐。

规则：
1. 用户列出的「过敏食材」和「忌口」绝对不能出现，包括由它们制成的食品（例如忌口花生，就不能用花生酱、花生油）。这是最重要的规则。
2. 每一餐设计一道菜或一套简单搭配，热量和三大营养素都要贴近给出的目标，误差控制在 ±10% 以内。蛋白质不要明显超过目标：目标是多少就给多少，不要额外加量。
3. 食材要在普通超市和菜市场能买到；用量按生重、以克为单位；一餐 3～8 种食材。
4. 做法写 3～6 步，每步一句话，新手能照着做；总耗时不超过用户给的烹饪时间。
5. 营养数值参考常见的食物成分数据，按食材用量估算。
6. 三餐之间不要重复主要食材，菜名也不要和「要避开的菜名」重复。
7. 早餐要像早餐，午餐和晚餐可以是正餐。除非用户另有偏好，默认以中式家常做法为主。
8. 菜名、食材名和做法使用{language}。"""


def build_user_prompt(req: RecipeRequest, violation_note: str = "") -> str:
    lang = req.lang
    parts = [
        f"用户目标：{GOAL_NAMES[lang][req.goal]}",
        f"每餐目标：\n{meal_targets_text(req)}",
        f"每餐可接受的烹饪时间：不超过 {req.max_cooking_minutes} 分钟",
    ]
    if req.allergies:
        parts.append("过敏食材（绝对不能用）：" + "、".join(req.allergies))
    if req.dislikes:
        parts.append("忌口（绝对不能用）：" + "、".join(req.dislikes))
    if req.preferences:
        parts.append(f"饮食偏好：{req.preferences}")
    if req.exclude_names:
        parts.append("要避开的菜名（用户想换别的）：" + "、".join(req.exclude_names))
    if violation_note:
        parts.append(violation_note)
    parts.append(f"请为以上 {len(req.meals)} 餐各设计一份食谱。")
    return "\n\n".join(parts)


# ---------- 检查结果 ----------


def find_forbidden(recipe: Recipe, forbidden: list[str]) -> list[str]:
    """检查菜名和食材里有没有出现禁止的食材，返回出现了的那些"""
    haystack = (recipe.name + " " + " ".join(i.name for i in recipe.ingredients)).casefold()
    return [term for term in forbidden if term.casefold() in haystack]


def tidy(recipe: Recipe) -> Recipe:
    """数值取整、去掉多余空格"""
    return Recipe(
        meal=recipe.meal,
        name=recipe.name.strip(),
        ingredients=[Ingredient(name=i.name.strip(), grams=round(max(i.grams, 0))) for i in recipe.ingredients if i.name.strip()],
        steps=[s.strip() for s in recipe.steps if s.strip()],
        cooking_minutes=max(1, recipe.cooking_minutes),
        calories_kcal=round(max(recipe.calories_kcal, 0)),
        protein_g=round(max(recipe.protein_g, 0), 1),
        carbs_g=round(max(recipe.carbs_g, 0), 1),
        fat_g=round(max(recipe.fat_g, 0), 1),
    )


# ---------- 调用 Claude ----------


def ask_claude(req: RecipeRequest, violation_note: str = "") -> tuple[AIRecipes, str]:
    client = get_client()
    started = time.monotonic()
    try:
        response = client.beta.messages.parse(
            model=MODEL,
            max_tokens=16000,
            system=build_system_prompt(req.lang),
            messages=[{"role": "user", "content": build_user_prompt(req, violation_note)}],
            output_format=AIRecipes,
            **model_options(MODEL),
        )
    except pydantic.ValidationError:
        raise AIError(502, "AI 返回的食谱格式不对，请重试")
    except anthropic.AuthenticationError:
        raise AIError(500, "ANTHROPIC_API_KEY 无效，请检查 backend/.env 里的 Key")
    except anthropic.RateLimitError:
        raise AIError(429, "AI 服务太忙了，请稍后再试")
    except anthropic.BadRequestError as e:
        logger.error("Claude 拒绝了请求：%s", e.message)
        raise AIError(502, f"AI 服务拒绝了请求：{e.message}")
    except anthropic.APITimeoutError:
        raise AIError(504, "生成食谱超时，请重试")
    except anthropic.APIConnectionError:
        raise AIError(503, "连接不上 AI 服务，请检查网络")
    except anthropic.APIStatusError as e:
        logger.error("Claude 服务出错：%s %s", e.status_code, e.message)
        raise AIError(502, f"AI 服务出错（{e.status_code}），请稍后再试")

    logger.info(
        "食谱生成完成：模型 %s，用时 %.1f 秒，输入 %d token，输出 %d token，结束原因 %s",
        response.model, time.monotonic() - started,
        response.usage.input_tokens, response.usage.output_tokens, response.stop_reason,
    )
    if response.stop_reason == "refusal":
        raise AIError(422, "AI 无法处理这个请求，请调整偏好后重试")
    if response.stop_reason == "max_tokens":
        raise AIError(502, "AI 的回答被截断了，请重试")
    if response.parsed_output is None:
        raise AIError(502, "AI 没有返回食谱，请重试")
    return response.parsed_output, response.model


def generate_recipes(req: RecipeRequest) -> RecipesResult:
    """完整流程：问 Claude → 检查忌口 → 有问题让它重做一次 → 整理结果"""
    forbidden = req.allergies + req.dislikes
    violation_note = ""
    for attempt in range(2):  # 最多试两次
        ai, model = ask_claude(req, violation_note)
        recipes = [tidy(r) for r in ai.recipes if r.meal in req.meals]

        # 每一餐只留第一份，并且每餐都得有
        by_meal: dict[str, Recipe] = {}
        for r in recipes:
            by_meal.setdefault(r.meal, r)
        missing = [m for m in req.meals if m not in by_meal]

        problems = []
        for r in by_meal.values():
            found = find_forbidden(r, forbidden)
            if found:
                problems.append(f"「{r.name}」用了 {'、'.join(found)}")
        if not missing and not problems:
            return RecipesResult(recipes=[by_meal[m] for m in req.meals], model=model)

        # 有问题：把问题写进提示词再试一次
        notes = []
        if problems:
            notes.append("上一次的方案违反了规则：" + "；".join(problems) + "。请重新设计，绝对不要使用这些食材及其制品。")
        if missing:
            notes.append("上一次缺少了这些餐：" + "、".join(MEAL_NAMES[req.lang][m] for m in missing) + "。")
        violation_note = " ".join(notes)
        logger.warning("食谱第 %d 次结果有问题，重试：%s", attempt + 1, violation_note)

    raise AIError(502, "AI 没能完全避开你的忌口，请稍后重试或调整忌口写法")
