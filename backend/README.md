# 后端：拍照识别食物热量

上传一张餐食照片，后端调用 Claude 识别食物，返回每种食物的重量、热量、三大营养素和整餐合计。

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `main.py` | 网页接口：`POST /analyze`（识别照片）、`GET /health`（检查是否在运行） |
| `food_ai.py` | 识别逻辑：整理照片、调用 Claude、检查结果、计算合计 |
| `.env` | 本地配置，放 API Key（不会上传到 GitHub） |
| `.env.example` | 配置模板 |
| `pyproject.toml` / `uv.lock` | 依赖清单，由 uv 管理 |

## 第一次使用

1. 在 [Claude Console](https://platform.claude.com) 创建 API Key。
2. 打开 `.env`，把 Key 填在 `ANTHROPIC_API_KEY=` 后面：

   ```bash
   open -e .env
   ```

## 启动

在 `backend` 文件夹里运行：

```bash
uv run fastapi dev main.py
```

然后用浏览器打开 <http://127.0.0.1:8000/docs>，在 `POST /analyze` 里上传照片测试。按 `Ctrl + C` 停止。

## 配置（.env）

| 名称 | 默认值 | 说明 |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | 无 | 必填，Claude API Key |
| `FOOD_AI_MODEL` | `claude-opus-5-5` | 识别用的模型，换成 `claude-haiku-4-5` 更便宜 |
| `FOOD_AI_EFFORT` | `low` | 思考深度：`low` / `medium` / `high`，越高越慢、越贵 |

改了 `.env` 之后要重启后端才会生效。
