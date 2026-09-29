# 后端：拍照识别食物热量、生成食谱

两个功能：上传餐食照片，Claude 识别食物并返回营养数据；根据每日目标和忌口，Claude 生成一日三餐。

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `main.py` | 网页接口：`POST /analyze`、`POST /recipes`、`GET /quota`、`GET /health`，以及各种防护 |
| `food_ai.py` | 识别逻辑：整理照片、调用 Claude（识别和食谱共用 `call_claude`）、检查结果、计算合计 |
| `recipes_ai.py` | 食谱逻辑：拆分每餐目标、组织提示词、检查忌口 |
| `limits.py` | 防护工具：次数限制、并发闸门、食谱缓存 |
| `.env` | 本地配置，放 API Key（不会上传到 GitHub） |
| `.env.example` | 配置模板 |
| `pyproject.toml` / `uv.lock` | 依赖清单，由 uv 管理 |
| `../render.yaml` | Render 部署配置（在仓库根目录） |

## 第一次使用

1. 在 [Claude Console](https://platform.claude.com) 创建 API Key。
2. 打开 `.env`，把 Key 填在 `ANTHROPIC_API_KEY=` 后面：

   ```bash
   open -e .env
   ```

## 本地启动

在 `backend` 文件夹里运行：

```bash
uv run fastapi dev main.py
```

然后用浏览器打开 <http://127.0.0.1:8000/docs>，在 `POST /analyze` 里上传照片测试。按 `Ctrl + C` 停止。

真机测试时要让手机能访问电脑，改用（只在自己家的 Wi-Fi 下这样用）：

```bash
uv run fastapi dev main.py --host 0.0.0.0
```

## 部署到网上（Render）

部署配置在仓库根目录的 `render.yaml` 里，Render 会读它自动创建服务。部署后：

- `/docs` 会自动关闭（Render 会设置环境变量 `RENDER=true`）。
- 所有请求都要带 `X-App-Key` 请求头，值等于环境变量 `APP_SHARED_SECRET`（Render 自动生成，要填进 App）。
- 错误提示只给通用说明，具体原因看 Render 的日志。

## 防护和费用控制

后端一旦放到公网，任何人都可以调用，费用记在你的 Key 上，所以有这几层：

| 层 | 规则 | 说明 |
| --- | --- | --- |
| App 密钥 | 请求头 `X-App-Key` 必须等于 `APP_SHARED_SECRET` | 挡住随手乱试的人；密钥藏在 App 里，有心人能抠出来，所以只是第一道门 |
| 每分钟 | 同一 IP 每分钟最多识别 6 次、食谱 4 次 | 防止瞬间猛刷 |
| 每台设备 | 每 24 小时识别 15 次、食谱 5 次 | 设备 ID 由 App 自己报，能伪造，算「公平限制」 |
| 每个 IP | 每 24 小时识别 40 次、食谱 15 次 | 伪造设备 ID 也绕不过 |
| 全站 | 每 24 小时识别 100 次、食谱 40 次 | 最后一道减速带：一天最多花约 3 美元 |
| 并发闸门 | 同时最多 2 个请求在处理照片和调用 AI | 保护只有 512 MB 内存的免费服务器 |
| 照片限制 | 最大 5 MB、1600 万像素 | App 上传的照片只有一两百 KB，再大的多半是攻击 |
| 缓存 | 相同的食谱请求 24 小时内直接返回上次结果 | 不花钱，也不占次数 |

这些计数都在内存里，后端重启或免费实例休眠后会清零，所以它们不是硬上限。**真正的硬上限是 Claude 控制台里设的每月花费上限**（已设：账号 $10，工作区 food-tracker-prod $8）。

没花钱的失败（照片读不了、连不上 AI、密钥错误等）会把次数还给用户；可能已经花了钱的失败（超时、回答被截断）不还。

### 可以在 Render 后台调整的环境变量

| 名称 | 默认值 | 说明 |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | 无 | 必填，Claude API Key |
| `APP_SHARED_SECRET` | 无 | App 密钥；不设就不检查（本地开发时不设） |
| `FOOD_AI_MODEL` | `claude-opus-5-5` | 用的模型，换成 `claude-haiku-4-5` 更便宜 |
| `FOOD_AI_EFFORT` | `low` | 思考深度：`low` / `medium` / `high` |
| `ANALYZE_PER_DEVICE` / `ANALYZE_PER_IP` / `ANALYZE_PER_SITE` | 15 / 40 / 100 | 识别的每日次数上限 |
| `RECIPES_PER_DEVICE` / `RECIPES_PER_IP` / `RECIPES_PER_SITE` | 5 / 15 / 40 | 食谱的每日次数上限 |
| `TRUSTED_PROXIES` | 见 `render.yaml` | 可信的代理地址段，用来拿到来访者的真实 IP |

改了环境变量之后，Render 会自动重新部署。
