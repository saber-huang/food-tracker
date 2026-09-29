# 后端：拍照识别食物热量、生成食谱

两个功能：上传餐食照片，Claude 识别食物并返回营养数据；根据每日目标和忌口，Claude 生成一日三餐。

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `main.py` | 网页接口：`POST /analyze`、`POST /recipes`、`GET /quota`、`GET /health` |
| `food_ai.py` | 识别逻辑：整理照片、调用 Claude、检查结果、计算合计 |
| `recipes_ai.py` | 食谱逻辑：拆分每餐目标、调用 Claude、检查忌口 |
| `limits.py` | 费用控制：每台设备的每日次数限制，以及食谱缓存 |
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

真机测试时要让手机能访问电脑，改用（只在自己家的 Wi-Fi 下这样用）：

```bash
uv run fastapi dev main.py --host 0.0.0.0
```

## 费用控制

| 措施 | 规则 | 原理 |
| --- | --- | --- |
| 限流 | 每台设备每 24 小时最多识别 15 次、生成食谱 5 次 | App 在请求头 `X-Device-ID` 里带上设备 ID；后端记住每台设备最近的调用时间，超过次数就直接拒绝，不调用 AI |
| 缓存 | 相同的食谱请求 24 小时内直接返回上次结果 | 把请求内容算成一个「指纹」，指纹相同就复用结果；不花钱，也不占次数。「换一个」要求结果不同，所以不走缓存 |

两者都存在内存里，后端重启会清零。用户多了以后可以换成 Redis。

## 配置（.env）

| 名称 | 默认值 | 说明 |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | 无 | 必填，Claude API Key |
| `FOOD_AI_MODEL` | `claude-opus-5-5` | 用的模型，换成 `claude-haiku-4-5` 更便宜 |
| `FOOD_AI_EFFORT` | `low` | 思考深度：`low` / `medium` / `high`，越高越慢、越贵 |

改了 `.env` 之后要重启后端才会生效。
