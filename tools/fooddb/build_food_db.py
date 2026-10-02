"""
检查 foods.py 里的数据，生成 App 用的内置食物库：FoodTracker/FoodTracker/FoodData/FoodDatabase.json。

用法（在仓库根目录）：/usr/bin/python3 tools/fooddb/build_food_db.py
数据有问题会列出来并退出，不会写出半成品。

检查的内容：
- id 不重复；名称、别名在规范化（去空格标点、全角转半角、英文小写、同义词换成标准写法）之后不和别的食物撞车
- 热量和三大营养素对得上：蛋白质、碳水每克 4 千卡，脂肪 9 千卡，相差不超过 20%（酒、黑咖啡这类例外）
- 每 100 克的营养素加起来不超过 100 克；单位的克数、步长合理
"""

from __future__ import annotations

import json
import sys
import unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from foods import FOODS, SYNONYMS, UNITS  # noqa: E402

OUT = HERE.parent.parent / "FoodTracker" / "FoodTracker" / "FoodData" / "FoodDatabase.json"
VERSION = 1

# 热量里有酒精、或者几乎为 0 的饮品：不按三大营养素核对
KCAL_CHECK_EXCEPTIONS = {"beer", "red_wine", "black_coffee", "diet_cola"}


def normalize(text: str) -> str:
    """和 App 里 FoodNameKey.normalize 一样：全角转半角、英文小写、去掉空格和标点符号"""
    text = unicodedata.normalize("NFKC", text).lower()
    return "".join(ch for ch in text if not (ch.isspace() or unicodedata.category(ch)[0] in "PS"))


def canonical(text: str, table: list[tuple[str, str]]) -> str:
    """把同义词换成标准写法：从左往右，每个位置先试最长的词"""
    key = normalize(text)
    out, i = [], 0
    while i < len(key):
        for word, standard in table:
            if key.startswith(word, i):
                out.append(standard)
                i += len(word)
                break
        else:
            out.append(key[i])
            i += 1
    return "".join(out)


def main() -> None:
    problems: list[str] = []
    table = sorted(
        ((normalize(w), normalize(group[0])) for group in SYNONYMS for w in group[1:]), key=lambda x: -len(x[0])
    )
    seen_ids: set[str] = set()
    seen_keys: dict[str, str] = {}
    foods_json = []

    for food in FOODS:
        if food.id in seen_ids:
            problems.append(f"{food.id}: id 重复")
        seen_ids.add(food.id)

        # 名称、别名撞车
        for name in [food.name, *food.aliases, food.name_en, *food.aliases_en]:
            key = canonical(name, table)
            if not key:
                problems.append(f"{food.id}: 名称「{name}」规范化后是空的")
                continue
            owner = seen_keys.get(key)
            if owner and owner != food.id:
                problems.append(f"{food.id}: 「{name}」和 {owner} 的名称或别名重复（规范化后都是 {key}）")
            seen_keys[key] = food.id

        s = food.source
        if s.kind not in {"usda", "cn", "estimate"}:
            problems.append(f"{food.id}: 来源 {s.kind} 不认识")
        if min(s.kcal, s.protein, s.carbs, s.fat) < 0:
            problems.append(f"{food.id}: 营养数据有负数")
        if s.protein + s.carbs + s.fat > 100.5:
            problems.append(f"{food.id}: 每 100 克的营养素加起来超过 100 克")
        macro_kcal = 4 * s.protein + 4 * s.carbs + 9 * s.fat
        if food.id not in KCAL_CHECK_EXCEPTIONS and abs(macro_kcal - s.kcal) > max(0.2 * s.kcal, 10):
            problems.append(f"{food.id}: 热量 {s.kcal} 和三大营养素算出来的 {macro_kcal:.0f} 相差太多")

        # 饮品按毫升记：每 100 克的数值乘以密度 = 每 100 毫升
        factor = food.density or 1.0
        per100 = {
            "kcal": round(s.kcal * factor),
            "protein": round(s.protein * factor, 1),
            "carbs": round(s.carbs * factor, 1),
            "fat": round(s.fat * factor, 1),
        }

        units_json = []
        unit_ids: set[str] = set()
        if not food.units:
            problems.append(f"{food.id}: 至少要有一个自然份量单位")
        for spec in food.units:
            key, amount, step, *en = spec
            if key not in UNITS:
                problems.append(f"{food.id}: 单位 {key} 没有定义")
                continue
            if key in unit_ids:
                problems.append(f"{food.id}: 单位 {key} 重复")
            unit_ids.add(key)
            if not (0 < amount <= 2000):
                problems.append(f"{food.id}: 单位 {key} 的克数 {amount} 不合理")
            if step not in (0.5, 1):
                problems.append(f"{food.id}: 单位 {key} 的步长只能是 0.5 或 1")
            zh, en_one, en_many = UNITS[key]
            if en:
                en_one, en_many = en
            units_json.append(
                {"id": key, "name": zh, "nameEn": en_one, "nameEnPlural": en_many, "amount": amount, "step": step}
            )
        if food.default_quantity <= 0:
            problems.append(f"{food.id}: 默认数量要大于 0")

        foods_json.append(
            {
                "id": food.id,
                "name": food.name,
                "nameEn": food.name_en,
                "aliases": food.aliases,
                "aliasesEn": food.aliases_en,
                "category": food.category,
                "baseUnit": "ml" if food.density else "g",
                "per100": per100,
                "source": s.kind,
                "sourceRef": s.ref,
                "units": units_json,
                "defaultQuantity": food.default_quantity,
            }
        )

    if problems:
        print("食物库有问题，没有生成：")
        for p in problems:
            print("  -", p)
        sys.exit(1)

    data = {"version": VERSION, "synonyms": SYNONYMS, "foods": foods_json}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    kinds = {k: sum(1 for f in FOODS if f.source.kind == k) for k in ("usda", "cn", "estimate")}
    print(f"wrote {OUT}: {len(foods_json)} foods（USDA {kinds['usda']}、成分表 {kinds['cn']}、估算 {kinds['estimate']}）")


if __name__ == "__main__":
    main()
