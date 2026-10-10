# Kindbite — AI Nutrition Tracker for iOS

Kindbite (一拍即食) is a bilingual (English / Simplified Chinese) iOS app that turns a photo of a meal into calories and macros, then helps you reach daily targets without judgment. It is currently in **TestFlight beta**.

<!-- TODO: add 3–4 screenshots here (Today, photo result, Choose Food, Recipes) -->

## Features

- **Photo logging** — analyze 1–4 photos of the same meal in one request. Foods that appear in several photos are merged, every item gets a confidence level, and you can edit the results before saving.
- **Leftovers** — didn't finish? Mark how much of each food you ate (all, ¾, half, ¼ or none), or snap the leftovers and the AI compares them with what you logged. Only the eaten share counts, and switching back restores the original numbers exactly.
- **Choose Food** — search a built-in, bilingual database of 121 foods with natural serving units, save your own foods, or ask the AI to estimate a food the database doesn't have.
- **Nutrition-label scanning** — packaged foods are read from their nutrition label **on the device** with Apple Vision. The photo is never uploaded.
- **Daily targets** — calorie and macro targets come from your profile and goal (lose fat, maintain, build muscle). Below a BMI of 16, targets are treated as a minimum and the app recommends having a doctor or registered dietitian set them.
- **Today view** — a bowl-shaped progress gauge, meal cards, a week strip, and a month calendar.
- **Gentle guidance** — optional calorie hints, a weekly summary, and next-meal suggestions.
- **AI recipes** — a one-day meal plan that fits your targets and never uses your listed allergies or disliked foods.
- **Habits** — eight badges in three tiers that reward logging, never eating less. Each new badge appears in a small celebration card (it only fades in when Reduce Motion is on).
- **Privacy** — no account, data stays on the phone (SwiftData), consent is asked before the first AI request, and Delete All Data erases everything on the phone.
- **Accessibility** — supports Dynamic Type and VoiceOver; heights and weights in metric or ft / in / lb.

## Architecture

```
iOS app  (SwiftUI · SwiftData · on-device Vision OCR · offline food database)
   |
   |  HTTPS + app key header
   v
FastAPI backend on Render
   auth & size checks -> rate limits -> concurrency gate -> cache -> per-call token caps
   |
   |  photos or text + Pydantic JSON schema
   v
Claude API  (vision, structured outputs)
```

| Endpoint | Purpose |
| --- | --- |
| `POST /analyze` | Recognize foods and nutrition from 1–4 photos of one meal |
| `POST /estimate` | Estimate nutrition for a food name the built-in database doesn't have |
| `POST /recipes` | Generate a one-day meal plan from targets, allergies, and dislikes |
| `GET /quota` | Remaining AI uses for this device today |
| `GET /health` | Health check |

### Backend highlights

- **Structured output** — Claude must answer with a JSON schema defined by Pydantic models. The server rounds the values, clamps impossible ones, and sums meal totals itself instead of trusting the model's arithmetic.
- **Constraint checks** — generated recipes are checked against the user's allergies and dislikes. If one slips through, the model gets one retry with the violation spelled out.
- **Image pipeline** — accepts HEIC, applies EXIF orientation, rejects images over 16 MP before decoding them, and downsizes each photo to 1024 px JPEG before sending it.
- **Abuse and cost controls** (built for a 512 MB free-tier instance):

  | Layer | Rule |
  | --- | --- |
  | App key and size check | Checked from headers alone, before the request body is read |
  | Rate limits | Sliding windows per IP per minute, per device per day, per IP per day, and site-wide per day |
  | Concurrency gate | At most 2 requests process photos or call the AI at once |
  | Cache | Identical recipe requests are reused for 24 hours and food estimates for 7 days |
  | Cost caps | Per-call output-token limits plus site-wide daily caps keep worst-case AI spend near $7/day |
  | Fair refunds | Failures that could not have cost money give the user's quota back |

- **Bilingual errors** — the app sends `X-App-Lang`, and user-facing errors come back in English or Chinese.

## Evaluation

Photo recognition was benchmarked on 50 dishes from the public [Nutrition5k](https://github.com/google-research-datasets/Nutrition5k) test split (overhead photos, weighed ground truth). The run used the production prompt and model (`claude-opus-5-5`, effort `low`):

| Metric | Result |
| --- | --- |
| Calorie MAE | 101 kcal (35% of the mean) |
| Median latency | 3.7 s per dish |
| Calorie density, predicted vs. true | 1.33 vs. 1.30 kcal/g |
| Correlation of portion error with calorie error | r = 0.72 |

Most of the error comes from estimating portion size, not from identifying the food. Per-dish results are in [`tools/eval/results/`](tools/eval/results/). To reproduce the run (about $0.75 in API usage):

```bash
backend/.venv/bin/python tools/eval/nutrition5k_eval.py --n 50 --seed 42
```

## Tech stack

| Area | Tools |
| --- | --- |
| iOS | Swift, SwiftUI, SwiftData, Vision, PhotosUI, Keychain, Swift Testing (267 tests) |
| Backend | Python 3.13, FastAPI, Pydantic, Pillow, Anthropic SDK, uv; deployed on Render |
| Tooling | Python scripts that validate and build the food database, generate localization catalogs, and build the support site; a Node script that renders the app icon |

## Repository layout

| Path | Contents |
| --- | --- |
| `FoodTracker/` | Xcode project, app source, and unit tests |
| `backend/` | FastAPI service; see `backend/README.md` (Chinese) for deployment details |
| `tools/fooddb/` | Source data and validator for the built-in food database |
| `tools/l10n/` | English translations and string-catalog generator |
| `tools/icon/` | App icon renderer |
| `tools/eval/` | Nutrition5k evaluation of photo recognition |
| `site/` | Support and privacy pages, published with GitHub Pages |
| `design-system/` | Design guidelines (Chinese) |

## Running locally

**Backend**

```bash
cd backend
cp .env.example .env          # then add your ANTHROPIC_API_KEY
uv run fastapi dev main.py    # API docs at http://127.0.0.1:8000/docs
uv run --no-sync python offline_checks.py   # offline checks, no AI calls
```

**iOS app**

1. Copy `FoodTracker/Config/Secrets.example.xcconfig` to `Secrets.xcconfig`. Leave both values empty to use the local backend.
2. Open `FoodTracker/FoodTracker.xcodeproj` in a recent Xcode with the iOS 27 SDK and run. Press ⌘U to run the tests.

## Links

- Support: <https://saber-huang.github.io/food-tracker-support/en.html>
- Privacy policy: <https://saber-huang.github.io/food-tracker-support/privacy-en.html>

## How it was built

Developed by Shengkai Huang with AI pair programming (Claude Code). Commits include co-author trailers.
