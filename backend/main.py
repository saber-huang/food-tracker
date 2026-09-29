"""
后端入口：定义 App 要调用的网页接口（API）。

启动方法（在 backend 文件夹里运行）：
    uv run fastapi dev main.py
然后用浏览器打开 http://127.0.0.1:8000/docs 测试接口。
"""

import logging
from typing import Annotated, Literal

from fastapi import FastAPI, File, Form, HTTPException, UploadFile

from food_ai import MAX_UPLOAD_BYTES, MODEL, AnalyzeError, AnalyzeResult, analyze_food_photo

# 让 food_ai.py 里的日志（用时、token 用量）显示在终端里
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
# 开发模式会监视文件改动，它的「检测到 N 处变化」提示没什么用，关掉
logging.getLogger("watchfiles").setLevel(logging.WARNING)

app = FastAPI(
    title="饮食记录 App 后端",
    description="上传一张餐食照片，返回 AI 识别出的食物和营养数据。",
    version="0.1.0",
)


@app.get("/")
def home():
    """首页：提示去 /docs 测试接口。"""
    return {"message": "后端正在运行。打开 /docs 可以测试接口。"}


@app.get("/health")
def health():
    """检查后端是否在运行，并显示当前用的模型。"""
    return {"status": "ok", "model": MODEL}


@app.post("/analyze", response_model=AnalyzeResult)
def analyze(
    photo: Annotated[UploadFile, File(description="餐食照片（JPG、PNG 或 HEIC）")],
    lang: Annotated[Literal["zh", "en"], Form(description="结果语言：zh 中文，en 英文")] = "zh",
):
    """识别照片里的食物，返回每种食物的营养数据和整餐合计。"""
    # 多读 1 个字节：如果读到的比上限还多，说明照片太大
    data = photo.file.read(MAX_UPLOAD_BYTES + 1)
    if not data:
        raise HTTPException(status_code=400, detail="没有收到照片")
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="照片太大了，请上传 15 MB 以内的照片")

    try:
        return analyze_food_photo(data, lang)
    except AnalyzeError as e:
        # 出错时统一返回 {"detail": "给用户看的说明"}，App 直接显示这句话就行
        raise HTTPException(status_code=e.status_code, detail=e.message)
