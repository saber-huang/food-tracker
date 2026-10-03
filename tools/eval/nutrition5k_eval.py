"""
Evaluate Kindbite's photo recognition (backend/food_ai.py) on the public Nutrition5k dataset.

Nutrition5k (Google Research, CC BY 4.0) has overhead photos of cafeteria dishes whose calories
and macros were computed from weighed ingredients. This script samples dishes from the official
RGB test split, sends each overhead photo through the same code path as POST /analyze (same
prompt, model and effort as production), and compares the predicted meal totals with the
ground truth.

Usage (from the repository root):
    backend/.venv/bin/python tools/eval/nutrition5k_eval.py --n 50 --seed 42

Primary metric, following the Nutrition5k paper: calorie MAE as a percentage of the mean
ground-truth calories. Also reported: MAE in kcal, median absolute percentage error, mean
signed error (bias), and the same for mass, fat, carbs and protein.

Downloads are cached in tools/eval/data/ (git-ignored). Each run spends real API money:
roughly 1–2 cents per dish with claude-opus-5-5 at low effort.
"""

import argparse
import csv
import json
import logging
import os
import random
import statistics
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "backend"))

import food_ai  # noqa: E402  (loads backend/.env)

DATASET_URL = "https://storage.googleapis.com/nutrition5k_dataset/nutrition5k_dataset"
METADATA_PATH = "metadata/dish_metadata_cafe1.csv"
TEST_SPLIT_PATH = "dish_ids/splits/rgb_test_ids.txt"
IMAGE_PATH = "imagery/realsense_overhead/{dish_id}/rgb.png"

HERE = Path(__file__).resolve().parent
DATA_DIR = HERE / "data"
RESULTS_DIR = HERE / "results"

# USD per million tokens (input, output), for the cost line in the report
PRICES = {"claude-opus-5-5": (4.00, 20.00), "claude-haiku-4-5": (1.00, 5.00)}

FIELDS = [  # (label, ground-truth column, predicted MealTotal attribute)
    ("calories (kcal)", "calories", "calories_kcal"),
    ("mass (g)", "mass", "weight_g"),
    ("fat (g)", "fat", "fat_g"),
    ("carbs (g)", "carbs", "carbs_g"),
    ("protein (g)", "protein", "protein_g"),
]

# ---------- data ----------


def fetch(rel_path: str) -> Path:
    """Download one dataset file into the cache (once) and return its local path."""
    local = DATA_DIR / rel_path
    if not local.exists():
        local.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(f"{DATASET_URL}/{rel_path}", timeout=60) as response:
            local.write_bytes(response.read())
    return local


def load_ground_truth() -> dict[str, dict[str, float]]:
    """dish_id -> totals. Each CSV row starts with dish_id, calories, mass, fat, carbs, protein,
    followed by a variable number of per-ingredient columns that we don't need."""
    truth = {}
    with fetch(METADATA_PATH).open(newline="") as f:
        for row in csv.reader(f):
            if len(row) < 6 or not row[0].startswith("dish_"):
                continue
            calories, mass, fat, carbs, protein = (float(v) for v in row[1:6])
            truth[row[0]] = {"calories": calories, "mass": mass, "fat": fat, "carbs": carbs, "protein": protein}
    return truth


def sample_dishes(truth: dict, n: int, seed: int) -> tuple[list[tuple[str, bytes]], list[str]]:
    """Shuffle the test-split dishes that have cafe-1 ground truth (fixed seed), then take the
    first n whose overhead photo downloads. Returns ([(dish_id, png_bytes)], skipped_ids)."""
    test_ids = [line.strip() for line in fetch(TEST_SPLIT_PATH).read_text().splitlines() if line.strip()]
    candidates = sorted(d for d in test_ids if d in truth)
    random.Random(seed).shuffle(candidates)
    chosen, skipped = [], []
    for dish_id in candidates:
        if len(chosen) == n:
            break
        try:
            chosen.append((dish_id, fetch(IMAGE_PATH.format(dish_id=dish_id)).read_bytes()))
        except urllib.error.HTTPError:
            skipped.append(dish_id)  # some dishes have no overhead capture
    return chosen, skipped


# ---------- recognition ----------

_current = threading.local()
_usage: dict[str, tuple[int, int]] = {}


class UsageCapture(logging.Handler):
    """food_ai.call_claude logs (action, model, seconds, input_tokens, output_tokens, stop_reason)
    after every call; keep the token counts for the dish being processed on this thread."""

    def emit(self, record: logging.LogRecord) -> None:
        dish_id = getattr(_current, "dish_id", None)
        if dish_id and isinstance(record.args, tuple) and len(record.args) == 6:
            _usage[dish_id] = (int(record.args[3]), int(record.args[4]))


def recognize(dish: tuple[str, bytes]) -> dict:
    dish_id, png = dish
    _current.dish_id = dish_id
    for attempt in range(2):
        started = time.monotonic()
        try:
            result = food_ai.analyze_food_photos([png], lang="en")
            return {"dish_id": dish_id, "ok": True, "seconds": time.monotonic() - started, "result": result}
        except food_ai.AIError as e:
            if attempt == 0 and (e.status_code >= 500 or e.status_code == 429):
                time.sleep(5)
                continue
            return {"dish_id": dish_id, "ok": False, "error": f"{e.status_code} {e.key}"}
    return {"dish_id": dish_id, "ok": False, "error": "unreachable"}


# ---------- metrics ----------


def summarize(rows: list[dict]) -> dict:
    out = {}
    for label, key, _ in FIELDS:
        truth = [r[f"true_{key}"] for r in rows]
        pred = [r[f"pred_{key}"] for r in rows]
        abs_err = [abs(p - t) for p, t in zip(pred, truth)]
        mae = statistics.fmean(abs_err)
        mean_truth = statistics.fmean(truth)
        ape = [abs(p - t) / t * 100 for p, t in zip(pred, truth) if t > 0]
        out[label] = {
            "mae": round(mae, 1),
            "mean_truth": round(mean_truth, 1),
            "mae_pct_of_mean": round(mae / mean_truth * 100, 1) if mean_truth else None,
            "median_ape_pct": round(statistics.median(ape), 1) if ape else None,
            "mean_signed_error": round(statistics.fmean(p - t for p, t in zip(pred, truth)), 1),
        }
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--n", type=int, default=50, help="number of dishes (default 50)")
    parser.add_argument("--seed", type=int, default=42, help="sampling seed (default 42)")
    parser.add_argument("--model", default="claude-opus-5-5", help="model to evaluate (default: production)")
    parser.add_argument("--effort", default="low", help="effort level (default: production)")
    parser.add_argument("--workers", type=int, default=4, help="parallel requests (default 4)")
    args = parser.parse_args()
    if args.n > 100:
        sys.exit("Refusing to run more than 100 dishes in one go; each dish is a paid API call.")
    if not os.getenv("ANTHROPIC_API_KEY"):
        sys.exit("ANTHROPIC_API_KEY is not set (backend/.env).")

    # Same settings as production (render.yaml), whatever the local .env says
    food_ai.MODEL = args.model
    food_ai.EFFORT = args.effort
    logging.basicConfig(level=logging.WARNING)
    logging.getLogger("food_ai").setLevel(logging.INFO)
    logging.getLogger("food_ai").addHandler(UsageCapture())

    truth = load_ground_truth()
    dishes, skipped = sample_dishes(truth, args.n, args.seed)
    print(f"Evaluating {len(dishes)} dishes with {args.model} (effort {args.effort})"
          + (f"; skipped {len(skipped)} without a photo" if skipped else ""))

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        outcomes = list(pool.map(recognize, dishes))

    rows, failures = [], []
    for o in outcomes:
        if not o["ok"]:
            failures.append(o)
            continue
        r, t = o["result"], truth[o["dish_id"]]
        tokens_in, tokens_out = _usage.get(o["dish_id"], (0, 0))
        row = {"dish_id": o["dish_id"], "model": r.model, "is_food": r.is_food, "items": len(r.items),
               "low_confidence_items": sum(1 for i in r.items if i.confidence == "low"),
               "seconds": round(o["seconds"], 2), "input_tokens": tokens_in, "output_tokens": tokens_out,
               "predicted_foods": "; ".join(i.name for i in r.items)}
        for _, key, attr in FIELDS:
            row[f"true_{key}"] = round(t[key], 1)
            row[f"pred_{key}"] = getattr(r.total, attr)
        rows.append(row)
    if not rows:
        sys.exit(f"All {len(failures)} requests failed: {[f['error'] for f in failures]}")

    metrics = summarize(rows)
    tokens_in = sum(r["input_tokens"] for r in rows)
    tokens_out = sum(r["output_tokens"] for r in rows)
    price = PRICES.get(args.model)
    cost = round((tokens_in * price[0] + tokens_out * price[1]) / 1_000_000, 2) if price else None
    seconds = sorted(r["seconds"] for r in rows)
    summary = {
        "dataset": "Nutrition5k (cafe 1, official RGB test split, overhead photos)",
        "date": datetime.now().strftime("%Y-%m-%d"),
        "model": args.model, "effort": args.effort, "seed": args.seed,
        "dishes_evaluated": len(rows), "failed_requests": len(failures), "skipped_no_photo": len(skipped),
        "metrics": metrics,
        "median_latency_s": round(statistics.median(seconds), 1),
        "input_tokens": tokens_in, "output_tokens": tokens_out, "estimated_cost_usd": cost,
        "failures": [f"{f['dish_id']}: {f['error']}" for f in failures],
    }

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    stem = f"nutrition5k_{summary['date']}_{args.model}_n{len(rows)}"
    with (RESULTS_DIR / f"{stem}.csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    (RESULTS_DIR / f"{stem}.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False))

    lines = [
        f"# Kindbite photo recognition on Nutrition5k ({summary['date']})",
        "",
        f"- Dishes: {len(rows)} sampled with seed {args.seed} from the official RGB test split (cafe 1); "
        f"{len(failures)} failed requests, {len(skipped)} skipped for a missing photo",
        f"- Model: `{args.model}`, effort `{args.effort}`, same prompt and code path as `POST /analyze`",
        "- Ground truth: weighed ingredients from the dataset; one overhead photo per dish",
        "",
        "| Quantity | MAE | MAE % of mean | Median abs. % error | Mean signed error |",
        "| --- | --- | --- | --- | --- |",
    ]
    for label, m in metrics.items():
        lines.append(f"| {label} | {m['mae']} | {m['mae_pct_of_mean']}% | {m['median_ape_pct']}% | {m['mean_signed_error']:+} |")
    lines += [
        "",
        f"Median latency {summary['median_latency_s']} s per dish; {tokens_in:,} input / {tokens_out:,} output tokens"
        + (f" (about ${cost})." if cost is not None else "."),
        "",
        "MAE % of mean = mean absolute error ÷ mean ground truth (the convention used in the Nutrition5k paper).",
        "Nutrition5k is a public dataset, so some images may have appeared in the model's training data.",
    ]
    (RESULTS_DIR / f"{stem}.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"\nSaved {stem}.csv / .json / .md in {RESULTS_DIR.relative_to(REPO)}")


if __name__ == "__main__":
    main()
