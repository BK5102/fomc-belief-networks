"""Checks for py/panels.py: futures conversion, month weights, prediction-market normalisation. Run from tests/."""
import sys; sys.path.insert(0, "../py")
import numpy as np, pandas as pd
from panels import implied_moves, month_weight, _normalise
import common
meet = pd.read_csv("../data/meetings.csv", parse_dates=["decision_date", "effective_date"])

# 1) build ZQ prices from known per-meeting moves (bp), then check implied_moves recovers each within 1 bp
day, effr = pd.Timestamp("2026-10-05"), 3.90
true = {"2026-10": 25.0, "2026-12": -25.0, "2027-01": 0.0, "2027-03": -25.0, "2027-04": 0.0, "2027-06": 25.0}
up = meet[meet.meeting.isin(true)].copy()
prices = {}
for p in pd.period_range("2026-11", "2027-08", freq="M"):
    # monthly average rate (percent) = EFFR + weighted sum of moves already in effect
    r = effr + sum(month_weight(p, row.effective_date) * true[row.meeting] / 100 for row in up.itertuples())
    prices[f"ZQ{'FGHJKMNQUVXZ'[p.month-1]}{p.year%100:02d}"] = 100 - r
est = implied_moves(day, prices, effr, meet)
for k, v in true.items():
    assert abs(est[k] - v) < 1.0, (k, est[k], v)
print("bootstrap OK:", {k: round(v, 1) for k, v in est.items() if k in true})

# 2) month weight: meeting effective 2026-10-29 covers 3 of 31 October days and all of November
assert abs(month_weight(pd.Period("2026-10", "M"), pd.Timestamp("2026-10-29")) - 3/31) < 1e-9
assert month_weight(pd.Period("2026-11", "M"), pd.Timestamp("2026-10-29")) == 1.0

# 3) normalisation: ladder CUT25 0.40 / HOLD 0.55 / HIKE25 0.05 sums to 1.0, so E[move] = -25*0.40 + 25*0.05 = -8.75 bp
d = pd.date_range("2026-09-01", periods=5)
rows = []
for dt in d:
    for oc, p in {"CUT25": .40, "HOLD": .55, "HIKE25": .05}.items(): rows.append(dict(date=dt, meeting="2026-10", outcome=oc, p=p))
out = _normalise(pd.DataFrame(rows), meet)
assert abs(out.e_move_bp.iloc[0] - (-25*.40 + 25*.05)/1.0) < 1e-9, out
print("PM normalisation OK:", round(out.e_move_bp.iloc[0], 2))
