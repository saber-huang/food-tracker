"""离线检查：不联网、不调用 AI、不花钱，在自己电脑上确认后端的几项基本行为。
在 backend 文件夹里运行：uv run --no-sync python offline_checks.py

检查的内容：
1. 提示文字表（messages.py）：每一条都有中文和英文，两种语言里要填的名字一样
2. 提示跟着 X-App-Lang 请求头走：en 用英文，没带或其他值用中文（旧版 App 不带这个头）
3. 真实接口：上传「不是图片」的内容，后端在调用 AI 之前就会拒绝，说明文字的语言正确，次数也还回去
4. 次数用完（每分钟限制）的说明文字、门卫（密钥不对）的说明文字也跟着语言走
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
