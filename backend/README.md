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
2. 从模板复制出一份 `.env`（这个文件不会上传 GitHub，新电脑上要重新做一次）：

   ```bash
   cp .env.example .env
   ```

3. 打开 `.env`，把 Key 填在 `ANTHROPIC_API_KEY=` 后面：

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
- 除了首页 `/` 和 `/health`，所有请求都要带 `X-App-Key` 请求头，值等于环境变量 `APP_SHARED_SECRET`。
- 错误提示只给通用说明，具体原因看 Render 的日志（服务页面的 Logs）。

### 第一次部署的步骤

1. 代码推送到 GitHub（Render 从 GitHub 拉代码）。
2. 在 Claude Console 里给线上后端单独创建一个 API Key（建议放在有每月花费上限的工作区里）。
3. 在电脑上生成 App 密钥，并填进 App 的配置文件 `FoodTracker/Config/Secrets.xcconfig`（从 `Secrets.example.xcconfig` 复制一份改名）：

   ```bash
   openssl rand -hex 32
   ```

4. Render 网页：**New → Blueprint**，选这个仓库，Render 会读到 `render.yaml`，并让你填两个值：`ANTHROPIC_API_KEY`（第 2 步的 Key）和 `APP_SHARED_SECRET`（第 3 步生成的串）。点 **Deploy Blueprint**。
5. 部署完成后，服务页面顶部会显示网址（`https://xxx.onrender.com`）。把它填进 `Secrets.xcconfig` 的 `BACKEND_URL`（写法见文件里的注释），在 Xcode 里重新运行 App。
6. 检查：浏览器打开 `https://xxx.onrender.com/health` 应显示 `{"status":"ok"}`；打开 `/docs` 应显示 `{"detail":"请更新 App 到最新版本"}`（说明密钥检查生效了；接口文档在线上已关闭，带密钥访问也只会得到 404）。

以后改了 `backend/` 里的代码，推送到 GitHub 的 `main` 分支就会自动重新部署。改环境变量在服务页面的 **Environment** 里改，保存后也会自动重新部署。

## 防护和费用控制

后端一旦放到公网，任何人都可以调用，费用记在你的 Key 上，所以有这几层：

| 层 | 规则 | 说明 |
| --- | --- | --- |
| App 密钥 | 请求头 `X-App-Key` 必须等于 `APP_SHARED_SECRET`，在读取请求体之前检查 | 挡住随手乱试的人；密钥藏在 App 里，有心人能抠出来，所以只是第一道门 |
| 请求大小 | 识别最多 5 MB 出头，其他接口 32 KB，超过的在读取请求体之前就拒绝 | 防止有人用超大请求把 512 MB 内存的服务器撑崩 |
| 每分钟 | 同一 IP 每分钟最多识别 6 次、食谱 4 次 | 防止瞬间猛刷 |
| 每台设备 | 每 24 小时识别 15 次、食谱 5 次 | 设备 ID 由 App 自己报，能伪造，算「公平限制」 |
| 每个 IP | 每 24 小时识别 60 次、食谱 20 次 | 伪造设备 ID 也绕不过；放得比设备上限宽，是因为同一个 Wi-Fi 下的几个人共用一个 IP |
| 全站 | 每 24 小时识别 100 次、食谱 40 次 | 最后一道减速带：按典型花费一天约 3 美元；极端情况（每次都顶到输出上限）约 7 美元 |
| 并发闸门 | 同时最多 2 个请求在处理照片和调用 AI | 保护只有 512 MB 内存的免费服务器 |
| 照片限制 | 最大 5 MB、1600 万像素 | App 上传的照片只有一两百 KB，再大的多半是攻击 |
| 缓存 | 相同的食谱请求 24 小时内直接返回上次结果 | 不花钱，也不占次数 |

这些计数都在内存里，后端重启或免费实例休眠后会清零，所以它们不是硬上限。**真正的硬上限是 Claude 控制台里设的每月花费上限**（已设：账号 $10，工作区 food-tracker-prod $8）。

每调用一次 AI 算一次次数：食谱没避开忌口时会重做一次，重做也算一次（次数不够就不重做）。没花钱的失败（照片读不了、连不上 AI、密钥错误等）会把次数还给用户；可能已经花了钱的失败（超时、回答被截断）不还。

### 可以在 Render 后台调整的环境变量

| 名称 | 默认值 | 说明 |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | 无 | 必填，Claude API Key |
| `APP_SHARED_SECRET` | 无 | App 密钥；不设就不检查（本地开发时不设） |
| `FOOD_AI_MODEL` | `claude-opus-5-5` | 用的模型，换成 `claude-haiku-4-5` 更便宜 |
| `FOOD_AI_EFFORT` | `low` | 思考深度：`low` / `medium` / `high` |
| `ANALYZE_PER_DEVICE` / `ANALYZE_PER_IP` / `ANALYZE_PER_SITE` | 15 / 60 / 100 | 识别的每日次数上限 |
| `RECIPES_PER_DEVICE` / `RECIPES_PER_IP` / `RECIPES_PER_SITE` | 5 / 20 / 40 | 食谱的每日次数上限 |
| `TRUSTED_PROXIES` | 见 `render.yaml` | 可信的代理地址段。在 Render 上计次看的是 Cloudflare 写入的 `CF-Connecting-IP`（见 `main.py` 的 `client_ip`），这个只在请求没带它时备用 |

改了环境变量之后，Render 会自动重新部署。
