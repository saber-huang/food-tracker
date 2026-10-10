"""离线检查：不联网、不调用 AI、不花钱，在自己电脑上确认后端的几项基本行为。
在 backend 文件夹里运行：uv run --no-sync python offline_checks.py

检查的内容：
1. 提示文字表（messages.py）：每一条都有中文和英文，两种语言里要填的名字一样
2. 提示跟着 X-App-Lang 请求头走：en 用英文，没带或其他值用中文（旧版 App 不带这个头）
3. 真实接口：上传「不是图片」的内容，后端在调用 AI 之前就会拒绝，说明文字的语言正确，次数也还回去
4. 一餐几张照片（把调用 Claude 的那一步换成假的，不花钱）：1 张照片和以前完全一样；
   3 张照片一次发给 AI，规则里有「同一份食物只算一次」的原话，只算 1 次；5 张直接拒绝；加起来太大不调用 AI、次数还回去
5. 次数用完（每分钟限制）的说明文字、门卫（密钥不对）的说明文字也跟着语言走
6. AI 估算一种食物（同样把调用 Claude 的那一步换成假的）：名字检查、数字整理、菜 / 包装食品的判断、同一个名字用缓存不再问 AI、
   不是食物时营养都是 0、/quota 里有估算次数
7. 饭后拍剩下的（同样换成假的）：清单检查（不对的在扣次数之前拒绝）、发给 AI 的清单和份量、
   比例整理（限制在 0～1、取到 0.05、没提到的按吃完算）、照片不对时不改任何比例、和拍照识别共用次数
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import messages  # noqa: E402

failures = 0


def check(cond: bool, msg: str) -> None:
    global failures
    if cond:
        print("ok  ", msg)
    else:
        failures += 1
        print("FAIL", msg)


# ---------- 1. 提示文字表 ----------
names = re.compile(r"\{(\w+)\}")
for key, versions in messages.MESSAGES.items():
    check(set(versions) == {"zh", "en"}, f"{key}：有中文和英文")
    zh_names = set(names.findall(versions["zh"]))
    en_names = set(names.findall(versions["en"]))
    # 英文可以不用 action（中文「AI 识别超时」才需要），也可以用 hours_en 代替 hours
    allowed_zh_only = {"action", "hours"}
    check(
        en_names - {"hours_en"} <= zh_names and zh_names - en_names <= allowed_zh_only,
        f"{key}：两种语言要填的名字一致（中文 {sorted(zh_names)}，英文 {sorted(en_names)}）",
    )
    check(not re.search(r"[一-鿿]", versions["en"]), f"{key}：英文里没有中文")
check(messages.text("limit_device", "en", feature="analyze", limit=15, hours=1).endswith("about 1 hour."), "英文 1 小时用单数")
check("about 3 hours" in messages.text("limit_ip", "en", feature="recipes", hours=3), "英文 3 小时用复数")
check(messages.text("limit_device", "zh", feature="analyze", limit=15, hours=3).startswith("今天的拍照识别次数用完了"), "中文照旧")

# ---------- 2. 请求头 → 语言 ----------
check(messages.lang_from_header("en") == "en", "X-App-Lang: en → 英文")
check(messages.lang_from_header(" EN-us ") == "en", "大小写和空格不影响")
check(messages.lang_from_header("zh") == "zh", "X-App-Lang: zh → 中文")
check(messages.lang_from_header(None) == "zh", "没带这个头 → 中文（旧版 App）")
check(messages.lang_from_header("es") == "zh", "不认识的语言 → 中文")

# ---------- 3、4. 真实接口（本地、不调用 AI）----------
os.environ["APP_SHARED_SECRET"] = "offline-check-secret"
os.environ.pop("RENDER", None)
import main  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

client = TestClient(main.app)
key = {"X-App-Key": "offline-check-secret"}


def post_not_image(lang: str | None, device: str):
    headers = {**key, "X-Device-ID": device}
    if lang:
        headers["X-App-Lang"] = lang
    return client.post(
        "/analyze", headers=headers, files={"photo": ("a.jpg", b"not an image", "image/jpeg")}, data={"lang": "zh"}
    )


r = post_not_image("en", "OFFLINE-CHECK-DEVICE-EN")
check(r.status_code == 400 and r.json()["detail"].startswith("Couldn't read this image"), f"英文：读不了的图片 → 400 英文说明（{r.json()}）")
r = post_not_image(None, "OFFLINE-CHECK-DEVICE-ZH")
check(r.status_code == 400 and r.json()["detail"].startswith("无法读取这张图片"), f"没带语言：读不了的图片 → 400 中文说明（{r.json()}）")
q = client.get("/quota", headers={**key, "X-Device-ID": "OFFLINE-CHECK-DEVICE-EN"}).json()
check(q["analyze_remaining"] == q["analyze_per_day"], "没花钱的失败把每天的次数还回去了")

# ---------- 4. 一餐几张照片（不调用 AI：把调用 Claude 的那一步换成假的）----------
# 注意：每分钟的次数限制是按地址算的（测试里所有请求都来自同一个地址），这一段最多再用 3 次，放在连发检查之前
import io  # noqa: E402

import food_ai  # noqa: E402
from PIL import Image  # noqa: E402


def tiny_jpeg(color: tuple[int, int, int]) -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", (64, 48), color).save(buffer, format="JPEG")
    return buffer.getvalue()


calls: list[dict] = []


def fake_call_claude(*, system, content, output_format, max_tokens, feature):
    calls.append({"system": system, "content": content, "feature": feature})
    rice = food_ai.FoodItem(
        name="米饭", weight_g=150, calories_kcal=174, protein_g=3.9, carbs_g=38.1, fat_g=0.5, confidence="high"
    )
    return food_ai.AIResult(is_food=True, message="假结果", items=[rice]), "fake-model"


def post_photos(count: int, device: str, lang: str = "zh"):
    files = [("photo", ("1.jpg", tiny_jpeg((200, 180, 150)), "image/jpeg"))]
    for number in range(2, count + 1):
        files.append(("more_photos", (f"{number}.jpg", tiny_jpeg((120 + number * 20, 120, 90)), "image/jpeg")))
    headers = {**key, "X-Device-ID": device, "X-App-Lang": lang}
    return client.post("/analyze", headers=headers, files=files, data={"lang": lang})


def used_today(device: str) -> int:
    q = client.get("/quota", headers={**key, "X-Device-ID": device}).json()
    return q["analyze_per_day"] - q["analyze_remaining"]


real_call_claude = food_ai.call_claude
food_ai.call_claude = fake_call_claude
try:
    r = post_photos(1, "OFFLINE-CHECK-ONE-PHOTO")
    check(r.status_code == 200 and r.json()["items"][0]["name"] == "米饭", f"1 张照片：照常识别（{r.status_code}）")
    one = calls[-1]
    check(sum(block["type"] == "image" for block in one["content"]) == 1, "1 张照片：发给 AI 的内容里只有 1 张图")
    check(food_ai.MULTI_PHOTO_RULE not in one["system"], "1 张照片：没有加「几张照片合并」的规则")
    check(one["content"][-1]["text"] == "请分析这张照片里的餐食。", "1 张照片：提问和以前完全一样")

    r = post_photos(3, "OFFLINE-CHECK-THREE-PHOTOS")
    check(r.status_code == 200, f"3 张照片：返回 200（{r.status_code}）")
    three = calls[-1]
    check(len(calls) == 2, "3 张照片：只调用了 1 次 AI")
    check(sum(block["type"] == "image" for block in three["content"]) == 3, "3 张照片：3 张图在同一次调用里一起发给 AI")
    check(food_ai.MULTI_PHOTO_RULE in three["system"], "3 张照片：规则里有「同一份食物只算一次」的原话")
    check("Do not double-count the same item" in three["system"], "3 张照片：规则里写明不要重复计算")
    check("3 张照片是同一餐" in three["content"][-1]["text"], "3 张照片：提问里说明是同一餐")
    check(used_today("OFFLINE-CHECK-THREE-PHOTOS") == 1, "3 张照片只算 1 次")

    r = post_photos(5, "OFFLINE-CHECK-FIVE-PHOTOS", lang="en")
    check(r.status_code == 400 and r.json()["detail"] == "You can scan up to 4 photos at a time.", f"5 张照片：400 英文说明（{r.json()}）")
    r = post_photos(5, "OFFLINE-CHECK-FIVE-PHOTOS")
    check(r.status_code == 400 and r.json()["detail"] == "一次最多识别 4 张照片", f"5 张照片：400 中文说明（{r.json()}）")
    check(len(calls) == 2, "5 张照片：没有调用 AI")
    check(used_today("OFFLINE-CHECK-FIVE-PHOTOS") == 0, "5 张照片：没有扣次数")

    # 每张都不算大，但加起来超过 5 MB（请求总长度还在门卫的上限以内）：不调用 AI，次数还回去
    part = b"\xff\xd8" + b"0" * 2_630_000
    files = [("photo", ("1.jpg", part, "image/jpeg")), ("more_photos", ("2.jpg", part, "image/jpeg"))]
    r = client.post("/analyze", headers={**key, "X-Device-ID": "OFFLINE-CHECK-BIG-PHOTOS"}, files=files, data={"lang": "zh"})
    check(r.status_code == 413 and r.json()["detail"].startswith("这几张照片加起来太大了"), f"几张照片加起来太大 → 413（{r.json()}）")
    check(len(calls) == 2, "加起来太大：没有调用 AI")
    check(used_today("OFFLINE-CHECK-BIG-PHOTOS") == 0, "加起来太大：次数还回去了")
finally:
    food_ai.call_claude = real_call_claude

# ---------- 6. AI 估算（不调用 AI：把 estimate_ai 里调用 Claude 的那一步换成假的）----------
import estimate_ai  # noqa: E402

estimate_calls: list[dict] = []


def fake_estimate(*, system, content, output_format, max_tokens, feature):
    estimate_calls.append({"system": system, "content": content, "feature": feature})
    text = content[0]["text"]
    if "手机" in text:
        return estimate_ai.AIEstimate(
            is_food=False, food_type="other", name="手机", base_unit="g", calories_kcal_per_100=0, protein_g_per_100=0, carbs_g_per_100=0,
            fat_g_per_100=0, serving_name="个", serving_amount=200, message="手机不是食物",
        ), "fake-model"
    if "可乐" in text:
        return estimate_ai.AIEstimate(
            is_food=True, food_type="packaged", name="可乐", base_unit="ml", calories_kcal_per_100=43, protein_g_per_100=0,
            carbs_g_per_100=10.6, fat_g_per_100=0, serving_name="罐", serving_amount=330, message="",
        ), "fake-model"
    return estimate_ai.AIEstimate(
        is_food=True, food_type="dish", name="山西过油肉", base_unit="g", calories_kcal_per_100=181.6, protein_g_per_100=12.34,
        carbs_g_per_100=6.06, fat_g_per_100=12.49, serving_name="份", serving_amount=203.4, message="",
    ), "fake-model"


def post_estimate(name: str, device: str, lang: str = "zh"):
    headers = {**key, "X-Device-ID": device, "X-App-Lang": lang}
    return client.post("/estimate", headers=headers, json={"name": name, "lang": lang})


def estimates_used(device: str) -> int:
    q = client.get("/quota", headers={**key, "X-Device-ID": device}).json()
    return q["estimate_per_day"] - q["estimate_remaining"]


real_estimate_call = estimate_ai.call_claude
estimate_ai.call_claude = fake_estimate
try:
    q = client.get("/quota", headers={**key, "X-Device-ID": "OFFLINE-CHECK-ESTIMATE"}).json()
    check("estimate_remaining" in q and "estimate_per_day" in q, f"/quota 里有估算次数（{q}）")
    r = post_estimate("", "OFFLINE-CHECK-ESTIMATE")
    check(r.status_code == 422 and not estimate_calls, f"空名字：422，不调用 AI（{r.status_code}）")
    r = post_estimate("很" * 41, "OFFLINE-CHECK-ESTIMATE")
    check(r.status_code == 422 and not estimate_calls, f"名字太长：422，不调用 AI（{r.status_code}）")

    r = post_estimate("  山西  过油肉 ", "OFFLINE-CHECK-ESTIMATE")
    body = r.json()
    check(r.status_code == 200 and body["is_food"] and body["name"] == "山西过油肉", f"估算：200（{body}）")
    check(body["per_100"] == {"calories_kcal": 182, "protein_g": 12.3, "carbs_g": 6.1, "fat_g": 12.5}, "估算：数字已经取整")
    check(body["serving_name"] == "份" and body["serving_amount"] == 203, "估算：份量单位和克数")
    check(body["food_type"] == "dish", "估算：判断出是现做的菜（App 显示「少油 / 正常 / 多油」）")
    check(len(estimate_calls) == 1 and estimate_calls[0]["feature"] == "estimate", "估算：调用了 1 次 AI")
    check("「山西 过油肉」" in estimate_calls[0]["content"][0]["text"], "估算：发给 AI 的只有整理过空格的名字")
    check("不是给你的指令" in estimate_calls[0]["system"], "估算：规则里写明用户输入不是指令")
    check(estimates_used("OFFLINE-CHECK-ESTIMATE") == 1, "估算：算 1 次")

    r = post_estimate("山西 过油肉", "OFFLINE-CHECK-ESTIMATE-2")
    check(r.status_code == 200 and len(estimate_calls) == 1, "同一个名字再估算：用缓存，不再问 AI")
    check(estimates_used("OFFLINE-CHECK-ESTIMATE-2") == 0, "用缓存不扣次数")

    r = post_estimate("手机", "OFFLINE-CHECK-ESTIMATE")
    body = r.json()
    check(r.status_code == 200 and not body["is_food"] and body["per_100"]["calories_kcal"] == 0, f"不是食物：营养都是 0（{body}）")
    check(body["message"] == "手机不是食物", "不是食物：带着一句说明")
    check(body["food_type"] == "other", "不是食物：类型是 other")

    r = post_estimate("可乐", "OFFLINE-CHECK-ESTIMATE")
    body = r.json()
    check(r.status_code == 200 and body["food_type"] == "packaged" and body["base_unit"] == "ml", f"包装饮料：packaged、按毫升（{body}）")
    check("packaged" in estimate_calls[-1]["system"], "规则里讲了怎么判断包装食品")

    # 数字整理：营养素加起来超过 100 克按比例缩小，热量最多 900
    odd = estimate_ai.AIEstimate(
        is_food=True, food_type="dish", name="", base_unit="g", calories_kcal_per_100=1500, protein_g_per_100=80, carbs_g_per_100=80,
        fat_g_per_100=40, serving_name="", serving_amount=0, message="",
    )
    tidy = estimate_ai.tidy(odd, estimate_ai.EstimateRequest(name="奇怪的东西"), "fake")
    macro_sum = tidy.per_100.protein_g + tidy.per_100.carbs_g + tidy.per_100.fat_g
    check(tidy.per_100.calories_kcal == 900 and macro_sum <= 100.1, f"离谱的数字按边界整理（{tidy.per_100}）")
    check(tidy.name == "奇怪的东西" and tidy.serving_name == "份" and tidy.serving_amount == 1, "空名字、空单位用默认值")
finally:
    estimate_ai.call_claude = real_estimate_call

# ---------- 7. 饭后拍剩下的（不调用 AI：把 leftovers_ai 里调用 Claude 的那一步换成假的）----------
# 注意：识别的每分钟限制按地址算（前面已经用了 5 次，上限 6 次），这一段只能再有 1 个请求真正扣次数
import json  # noqa: E402

import leftovers_ai  # noqa: E402

served = leftovers_ai.parse_served_items(json.dumps([{"name": " 米饭 ", "weight_g": 150}, {"name": "宫保鸡丁"}]))
check([i.name for i in served] == ["米饭", "宫保鸡丁"] and served[1].weight_g is None, "清单：名字去掉多余空格，份量可以不填")
for bad, why in [("[]", "空清单"), ("不是 JSON", "不是 JSON"), (json.dumps([{"name": "  "}]), "空名字"),
                 (json.dumps([{"name": "米饭", "weight_g": -5}]), "负的份量"), (json.dumps([{"name": "米饭"}] * 21), "超过 20 样")]:
    try:
        leftovers_ai.parse_served_items(bad)
        check(False, f"清单：{why}应该被拒绝")
    except ValueError:
        check(True, f"清单：{why}被拒绝")

prompt = leftovers_ai.build_system_prompt(served, "en")
check("1. 米饭，约 150 克" in prompt and "2. 宫保鸡丁\n" in prompt, "发给 AI 的清单里有序号、名字和份量（没填份量的不写克数）")
check("English" in prompt and "按吃完算" in prompt, "说明里有结果语言和「看不到的按吃完算」")

ai = leftovers_ai.LeftoverAIResult(is_leftover_photo=True, message=" 菜剩了一点 ", items=[
    leftovers_ai.LeftoverItem(index=2, eaten_fraction=0.62),
    leftovers_ai.LeftoverItem(index=1, eaten_fraction=1.3),
    leftovers_ai.LeftoverItem(index=9, eaten_fraction=0.1),
])
tidy = leftovers_ai.build_result(ai, 3, "fake")
check(tidy.eaten == [1.0, 0.6, 1.0] and tidy.message == "菜剩了一点", f"比例：限制在 0～1、取到 0.05、没提到的按吃完、多出来的序号不管（{tidy.eaten}）")
low = leftovers_ai.build_result(leftovers_ai.LeftoverAIResult(is_leftover_photo=True, message="", items=[
    leftovers_ai.LeftoverItem(index=1, eaten_fraction=-0.2)]), 1, "fake", "en")
check(low.eaten == [0.0] and low.message == "Done. Please check the amounts.", f"负数当作没吃；没写总结用默认文字（{low}）")
nope = leftovers_ai.build_result(leftovers_ai.LeftoverAIResult(is_leftover_photo=False, message="", items=[]), 2, "fake")
check(not nope.is_leftover_photo and nope.eaten == [] and "不是吃剩的" in nope.message, "照片不对：不给比例，说明原因")

leftover_calls: list[dict] = []


def fake_leftovers(*, system, content, output_format, max_tokens, feature):
    leftover_calls.append({"system": system, "content": content, "feature": feature})
    return leftovers_ai.LeftoverAIResult(is_leftover_photo=True, message="米饭吃完了，菜剩了一半", items=[
        leftovers_ai.LeftoverItem(index=1, eaten_fraction=1), leftovers_ai.LeftoverItem(index=2, eaten_fraction=0.5)]), "fake-model"


def post_leftovers(items_json: str, device: str, lang: str = "zh"):
    headers = {**key, "X-Device-ID": device, "X-App-Lang": lang}
    files = [("photo", ("left.jpg", tiny_jpeg((210, 200, 190)), "image/jpeg"))]
    return client.post("/leftovers", headers=headers, files=files, data={"items": items_json, "lang": lang})


real_leftovers_call = leftovers_ai.call_claude
leftovers_ai.call_claude = fake_leftovers
try:
    r = post_leftovers("[]", "OFFLINE-CHECK-LEFTOVERS-BAD")
    check(r.status_code == 400 and "清单不对" in r.json()["detail"], f"清单不对 → 400 中文说明（{r.json()}）")
    check(not leftover_calls and used_today("OFFLINE-CHECK-LEFTOVERS-BAD") == 0, "清单不对：没有调用 AI，也没有扣次数")
    items_json = json.dumps([{"name": "米饭", "weight_g": 150}, {"name": "宫保鸡丁", "weight_g": 200}], ensure_ascii=False)
    r = post_leftovers(items_json, "OFFLINE-CHECK-LEFTOVERS")
    body = r.json()
    check(r.status_code == 200 and body["eaten"] == [1.0, 0.5] and body["is_leftover_photo"], f"返回每样吃掉的比例（{body}）")
    check(isinstance(body["remaining_today"], int), "返回今天还能识别几次")
    call = leftover_calls[0]
    check(call["feature"] == "leftovers" and sum(b["type"] == "image" for b in call["content"]) == 1, "发给 AI 的是 1 张照片")
    check("2. 宫保鸡丁，约 200 克" in call["system"], "发给 AI 的说明里有原来的清单")
    check(used_today("OFFLINE-CHECK-LEFTOVERS") == 1, "和拍照识别共用次数：用了 1 次")
finally:
    leftovers_ai.call_claude = real_leftovers_call

# ---------- 5. 每分钟限制、门卫 ----------
# 每分钟限制：同一个地址连发，超过之后是 429，说明按语言
codes = [post_not_image("en", f"OFFLINE-CHECK-BURST-{i:02d}").status_code for i in range(12)]
check(429 in codes, f"连发之后出现 429（{codes}）")
r = post_not_image("en", "OFFLINE-CHECK-BURST-EN")
check(r.status_code == 429 and r.json()["detail"].startswith("Too many photo scans in a short time"), f"英文的 429 说明（{r.json()}）")
r = post_not_image(None, "OFFLINE-CHECK-BURST-ZH")
check(r.status_code == 429 and "太频繁" in r.json()["detail"], f"中文的 429 说明（{r.json()}）")

# 门卫：密钥不对，只看请求头就拒绝
r = client.get("/quota", headers={"X-App-Key": "wrong", "X-App-Lang": "en"})
check(r.status_code == 401 and r.json()["detail"] == "Please update the app to the latest version.", f"英文的 401 说明（{r.json()}）")
r = client.get("/quota", headers={"X-App-Key": "wrong"})
check(r.status_code == 401 and r.json()["detail"] == "请更新 App 到最新版本", f"中文的 401 说明（{r.json()}）")

print()
print("全部通过" if failures == 0 else f"{failures} 项没通过")
sys.exit(1 if failures else 0)
