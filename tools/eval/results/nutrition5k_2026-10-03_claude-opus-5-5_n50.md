# Kindbite photo recognition on Nutrition5k (2026-10-03)

- Dishes: 50 sampled with seed 42 from the official RGB test split (cafe 1); 0 failed requests, 16 skipped for a missing photo
- Model: `claude-opus-5-5`, effort `low`, same prompt and code path as `POST /analyze`
- Ground truth: weighed ingredients from the dataset; one overhead photo per dish

| Quantity | MAE | MAE % of mean | Median abs. % error | Mean signed error |
| --- | --- | --- | --- | --- |
| calories (kcal) | 100.9 | 35.2% | 42.7% | +43.6 |
| mass (g) | 66.8 | 29.9% | 23.8% | +26.4 |
| fat (g) | 7.6 | 57.0% | 51.9% | +2.0 |
| carbs (g) | 9.4 | 47.8% | 41.0% | +8.0 |
| protein (g) | 9.2 | 40.1% | 37.6% | -1.8 |

Median latency 3.7 s per dish; 120,650 input / 11,775 output tokens (about $0.72).

MAE % of mean = mean absolute error ÷ mean ground truth (the convention used in the Nutrition5k paper).
Nutrition5k is a public dataset, so some images may have appeared in the model's training data.
