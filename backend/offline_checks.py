"""离线检查：不联网、不调用 AI、不花钱，在自己电脑上确认后端的几项基本行为。
在 backend 文件夹里运行：uv run --no-sync python offline_checks.py

检查的内容：
1. 提示文字表（messages.py）：每一条都有中文和英文，两种语言里要填的名字一样
2. 提示跟着 X-App-Lang 请求头走：en 用英文，没带或其他值用中文（旧版 App 不带这个头）
3. 真实接口：上传「不是图片」的内容，后端在调用 AI 之前就会拒绝，说明文字的语言正确，次数也还回去
4. 一餐几张照片（把调用 Claude 的那一步换成假的，不花钱）：1 张照片和以前完全一样；
   3 张照片一次发给 AI，规则里有「同一份食物只算一次」的原话，只算 1 次；5 张直接拒绝；加起来太大不调用 AI、次数还回去
5. 次数用完（每分钟限制）的说明文字、门卫（密钥不对）的说明文字也跟着语言走
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
