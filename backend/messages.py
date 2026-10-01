"""给用户看的提示文字（出错说明、次数用完等），中文和英文各一份。

App 在每个请求的 X-App-Lang 请求头里告诉后端它现在显示的语言（zh 或 en）；
没带这个头的请求（比如只有中文界面的旧版 App）一律用中文。
识别结果和食谱本身用什么语言，由请求里的 lang 参数决定（见 food_ai.py、recipes_ai.py），和这里无关。

加一条提示：在 MESSAGES 里加一个 key，中文和英文都写上，花括号里的名字两种语言要一样；
然后在 backend 文件夹里运行 uv run --no-sync python offline_checks.py 检查。
"""

from typing import Literal

Lang = Literal["zh", "en"]

# 功能名：拼进「次数用完了」这类提示里。英文用复数名词（photo scans）
FEATURES: dict[str, dict[str, str]] = {
    "analyze": {"zh": "拍照识别", "en": "photo scans"},
    "recipes": {"zh": "食谱推荐", "en": "recipe generations"},
}

# 动作名：拼进「AI 识别超时」里（英文句子里不需要）
ACTIONS: dict[str, dict[str, str]] = {
    "analyze": {"zh": "识别", "en": ""},
    "recipes": {"zh": "生成食谱", "en": ""},
}

MESSAGES: dict[str, dict[str, str]] = {
    # ---------- 次数限制（main.acquire）----------
    "limit_burst": {
        "zh": "{feature}太频繁了，请稍等一分钟再试",
        "en": "Too many {feature} in a short time. Please wait a minute and try again.",
    },
    "limit_device": {
        "zh": "今天的{feature}次数用完了（每 24 小时最多 {limit} 次），大约 {hours} 小时后可以再用",
        "en": "You've used all of today's {feature} ({limit} every 24 hours). You can try again in about {hours_en}.",
    },
    "limit_ip": {
        "zh": "当前网络下今天的{feature}次数用完了，大约 {hours} 小时后可以再用",
        "en": "Today's {feature} on this network have all been used. You can try again in about {hours_en}.",
    },
    "limit_site": {
        "zh": "今天全站的{feature}次数已经用完，请明天再试",
        "en": "The app has reached today's limit for {feature}. Please try again tomorrow.",
    },
    # ---------- 服务器本身（main.run_ai）----------
    "busy": {"zh": "服务器正忙，请稍后再试", "en": "The server is busy. Please try again shortly."},
    "server_error": {"zh": "服务器出错，请稍后再试", "en": "Something went wrong on the server. Please try again later."},
    "unavailable": {
        "zh": "服务暂时不可用，请稍后再试",
        "en": "The service is temporarily unavailable. Please try again later.",
    },
    # ---------- 照片 ----------
    "no_photo": {"zh": "没有收到照片", "en": "No photo was received."},
    "too_many_photos": {"zh": "一次最多识别 {max} 张照片", "en": "You can scan up to {max} photos at a time."},
    "photo_too_big": {
        "zh": "照片太大了，请上传 {mb} MB 以内的照片",
        "en": "This photo is too large. Please upload one under {mb} MB.",
    },
    "photos_too_big": {
        "zh": "这几张照片加起来太大了（最多 {mb} MB），请少选几张再试",
        "en": "These photos are too large together (up to {mb} MB). Please choose fewer and try again.",
    },
    "too_many_pixels": {
        "zh": "这张照片的像素太多了，请换一张，或先压缩后再上传",
        "en": "This photo has too many pixels. Please choose another one, or compress it first.",
    },
    "unreadable_image": {
        "zh": "无法读取这张图片，请上传 JPG、PNG 或 HEIC 格式的照片",
        "en": "Couldn't read this image. Please upload a JPG, PNG or HEIC photo.",
    },
    # ---------- 调用 AI（food_ai.call_claude）----------
    "ai_bad_format": {"zh": "AI 返回的结果格式不对，请重试", "en": "The AI sent back an unexpected result. Please try again."},
    "ai_busy": {"zh": "AI 服务太忙了，请稍后再试", "en": "The AI service is busy. Please try again shortly."},
    "ai_quota_used_up": {
        "zh": "今天的 AI 额度已经用完了，请明天再试",
        "en": "Today's AI allowance has been used up. Please try again tomorrow.",
    },
    "ai_cannot_process": {
        "zh": "AI 服务暂时无法处理这个请求，请稍后再试",
        "en": "The AI service can't handle this request right now. Please try again later.",
    },
    "ai_timeout": {"zh": "AI {action}超时，请重试", "en": "The AI took too long to respond. Please try again."},
    "ai_connect_failed": {
        "zh": "连接不上 AI 服务，请稍后再试",
        "en": "Couldn't connect to the AI service. Please try again later.",
    },
    "ai_error": {"zh": "AI 服务出错，请稍后再试", "en": "The AI service ran into a problem. Please try again later."},
    "ai_refusal": {
        "zh": "AI 无法处理这个请求，请换一个试试",
        "en": "The AI can't help with this request. Please try a different one.",
    },
    "ai_truncated": {"zh": "AI 的回答被截断了，请重试", "en": "The AI's answer was cut off. Please try again."},
    "ai_empty": {"zh": "AI 没有返回结果，请重试", "en": "The AI didn't return a result. Please try again."},
    "recipe_restrictions_failed": {
        "zh": "AI 没能完全避开你的忌口，请稍后重试或调整忌口写法",
        "en": "The AI couldn't fully avoid your allergies and foods to avoid. Please try again later, or reword them.",
    },
    # ---------- 门卫（limits.Gatekeeper，只看请求头就拒绝的请求）----------
    "update_app": {"zh": "请更新 App 到最新版本", "en": "Please update the app to the latest version."},
    "missing_length": {"zh": "请求缺少 Content-Length", "en": "The request is missing a Content-Length header."},
    "request_too_large": {"zh": "请求太大了", "en": "The request is too large."},
    # ---------- 识别结果的默认文字（food_ai.build_result，跟着结果的语言）----------
    "unknown_food": {"zh": "未知食物", "en": "Unknown food"},
    "result_not_food": {"zh": "这张照片里好像没有食物", "en": "There doesn't seem to be any food in this photo."},
    "result_no_items": {
        "zh": "没有识别出具体的食物，请换个角度再拍一张",
        "en": "Couldn't make out specific foods. Try another photo from a different angle.",
    },
    "result_done": {"zh": "识别完成", "en": "Analysis complete."},
}


def lang_from_header(value: str | None) -> Lang:
    """X-App-Lang 请求头 → 提示用的语言。只认 en，其他情况（包括没带这个头）都用中文"""
    return "en" if (value or "").strip().lower().startswith("en") else "zh"


def text(key: str, lang: Lang, **params) -> str:
    """取一条提示并填好里面的数字和名字。

    params 里可以直接传 feature="analyze"（功能名的 key）和 hours=3，这里会换成对应语言的写法：
    中文「拍照识别」「3 小时」，英文「photo scans」「3 hours」。
    """
    feature = params.pop("feature", None)
    if feature is not None:
        params["feature"] = FEATURES[feature][lang]
        params["action"] = ACTIONS[feature][lang]
    if "hours" in params:
        hours = params["hours"]
        params["hours_en"] = "1 hour" if hours == 1 else f"{hours} hours"
    return MESSAGES[key][lang].format(**params)
