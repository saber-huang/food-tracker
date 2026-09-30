"""
重新生成 App 的两个语言文件（Localizable.xcstrings 和 HintCopy.xcstrings），并检查英文翻译。

什么时候用：代码里加了、改了要显示的中文之后。步骤：
  1. 在 Xcode 里编译一次（⌘B）。编译时 Xcode 会把代码里所有要翻译的中文收集起来
  2. 在 food-tracker 文件夹里运行：python3 tools/l10n/build_catalogs.py
     它会列出还没有英文的中文；把英文加进 tools/l10n/translations_en.py 以后再运行一次
  3. 检查通过后，两个语言文件会被重新写好；再编译、跑一遍测试（⌘U）

检查的内容：每一句都有英文；英文里的 %@、%lld 等占位符和中文一一对应（调换顺序时用 %1$@、%2$@）；
百分号写法正确；英文里没有剩下中文。热量提示的英文还要遵守 HintCopy.swift 开头写的原则
（不制造负罪感，不建议少吃、补偿或靠运动消耗），LocalizationTests.swift 会检查英文禁用词。

编译时收集到的中文在 DerivedData 里；这个脚本默认读 Claude Code 编译用的位置，
在 Xcode 里编译的话，把下面 DERIVED_DATA 改成 Xcode 的 DerivedData 文件夹。
"""
import glob
import os
import json
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from translations_en import HINTCOPY, LOCALIZABLE

DERIVED_DATA = os.environ.get("DERIVED_DATA", "/tmp/claude-501/dd-foodtracker")


def collect_keys():
    """读编译时收集到的中文：每个表（Localizable、HintCopy）一组 key"""
    pattern = f"{DERIVED_DATA}/Build/Intermediates.noindex/FoodTracker.build/*/FoodTracker.build/Objects-normal/*/*.stringsdata"
    files = glob.glob(pattern)
    if not files:
        sys.exit(f"没有找到编译时收集的文字（{pattern}）。先编译一次，或设置 DERIVED_DATA")
    tables = {}
    for f in files:
        d = json.load(open(f))
        for table, items in d.get("tables", {}).items():
            for it in items:
                tables.setdefault(table, set()).add(it["key"])
    return {t: sorted(k) for t, k in tables.items()}


KEYS = collect_keys()
APP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "FoodTracker", "FoodTracker")
SPEC = re.compile(r"%(?:(\d+)\$)?(@|lld|ld|d|lf|f)|%%")

def specs(text):
    """Returns (list of types in order for non-positional, dict pos->type for positional, has_positional)."""
    ordered, positional = [], {}
    for m in SPEC.finditer(text):
        if m.group(0) == "%%":
            continue
        pos, typ = m.group(1), m.group(2)
        if pos:
            positional[int(pos)] = typ
        else:
            ordered.append(typ)
    return ordered, positional

def stray_percent(text):
    """A % that is not part of a placeholder or %%"""
    return "%" in SPEC.sub("", text)

errors = []

def check(key, value, where):
    k_order, _ = specs(key)
    v_order, v_pos = specs(value)
    if v_pos and v_order:
        errors.append(f"{where}: mixes positional and plain placeholders: {value}")
        return
    if v_pos:
        expected = {i + 1: t for i, t in enumerate(k_order)}
        if v_pos != expected:
            errors.append(f"{where}: placeholders {v_pos} != {expected}\n    key: {key}\n    en:  {value}")
    elif v_order != k_order:
        errors.append(f"{where}: placeholders {v_order} != {k_order}\n    key: {key}\n    en:  {value}")
    has_args = bool(k_order)
    if has_args and stray_percent(value):
        errors.append(f"{where}: literal % must be written %% when the string has values: {value}")
    if not has_args and "%%" in value:
        errors.append(f"{where}: no values, so a literal % stays single: {value}")
    if re.search(r"[一-鿿]", value):
        errors.append(f"{where}: Chinese left in English: {value}")

def en_unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}

def build(table, translations):
    keys = KEYS[table]
    missing = [k for k in keys if k not in translations]
    extra = [k for k in translations if k not in keys]
    for k in missing:
        errors.append(f"{table}: missing translation: {k}")
    strings = {}
    for k in keys:
        loc = {"zh-Hans": {"stringUnit": {"state": "translated", "value": k}}}
        v = translations.get(k)
        if isinstance(v, dict):
            assert set(v) == {"one", "other"}, k
            for form, text in v.items():
                check(k, text, f"{table}[{form}]")
            loc["en"] = {"variations": {"plural": {form: en_unit(text) for form, text in v.items()}}}
        elif v is not None:
            check(k, v, table)
            loc["en"] = en_unit(v)
        strings[k] = {"localizations": loc}
    catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    return catalog, extra

catalogs = {}
for table, tr in (("Localizable", LOCALIZABLE), ("HintCopy", HINTCOPY)):
    catalog, extra = build(table, tr)
    catalogs[table] = catalog
    if extra:
        print(f"{table}: {len(extra)} translations without a key (ignored):")
        for k in extra:
            print("   ", k)

if errors:
    print(f"{len(errors)} problems:")
    print("\n".join(errors))
    sys.exit(1)

for table, catalog in catalogs.items():
    path = f"{APP}/{table}.xcstrings"
    text = json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : ")) + "\n"
    open(path, "w", encoding="utf-8").write(text)
    print(f"wrote {path}: {len(catalog['strings'])} strings")
