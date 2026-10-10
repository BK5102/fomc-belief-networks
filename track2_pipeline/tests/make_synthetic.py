"""Write synthetic panels (date, meeting, e_move_bp) in the format panels.py produces, to test R/analysis.R.
Usage: python make_synthetic.py shared|independent
shared: both venues use the same chain of neighbouring meetings, so their MSTs should share most edges.
independent: venue B uses a shuffled meeting order, so the MSTs should share few edges.
Output: /tmp/synA_<scenario>.csv and /tmp/synB_<scenario>.csv, 220 business days x 8 meetings."""
import sys, numpy as np, pandas as pd
rng = np.random.default_rng(7)
ms = ["2026-10","2026-12","2027-01","2027-03","2027-04","2027-06","2027-07","2027-09"]
dates = pd.bdate_range("2026-01-05", periods=220)
# panel(): unused by the script; draws its own shocks for each meeting plus 0.8 x its neighbours in `order`
def panel(order, noise):
    f = rng.normal(size=(len(dates), len(ms)))
    pos = {m: i for i, m in enumerate(order)}
    X = np.zeros_like(f)
    for j, m in enumerate(ms):
        i = pos[m]; nb = [k for k, mm in enumerate(ms) if abs(pos[mm] - i) == 1]
        X[:, j] = f[:, j] + 0.8 * sum(f[:, k] for k in nb)
    X = X + noise * rng.normal(size=X.shape)
    lv = X.cumsum(axis=0) * 0.5 + 10
    return pd.DataFrame([dict(date=d.date(), meeting=m, e_move_bp=lv[t, j]) for t, d in enumerate(dates) for j, m in enumerate(ms)])
shared_order = ms
f = rng.normal(size=(len(dates), len(ms)))
base = f
# from_common(): unused by the script; returns `base` unchanged
def from_common(order, noise):
    pos = {m: i for i, m in enumerate(order)}
    X = np.zeros_like(base)
    for j, m in enumerate(ms):
        i = pos[m]; nb = [k for k, mm in enumerate(ms) if abs(pos[mm] - i) == 1]
        X[:, j] = base[:, [pos[ms[k]] for k in range(len(ms))][j]] if False else base[:, j]
    return X
scen = sys.argv[1]
common = rng.normal(size=(len(dates), len(ms)))   # daily shocks shared by both venues, one column per meeting
def build(order, noise):
    """Panel from the shared shocks: each meeting = own shock + 0.9 x shocks of its neighbours in `order`,
    plus noise (std dev), cumulated into levels scaled by 0.5 bp and shifted by 10 bp. Output: long DataFrame."""
    pos = {m: i for i, m in enumerate(order)}; X = np.zeros_like(common)
    for j, m in enumerate(ms):
        i = pos[m]; nb = [k for k, mm in enumerate(ms) if abs(pos[mm] - i) == 1]
        X[:, j] = common[:, j] + 0.9 * sum(common[:, k] for k in nb)
    X += noise * rng.normal(size=X.shape)
    lv = X.cumsum(axis=0) * 0.5 + 10
    return pd.DataFrame([dict(date=d.date(), meeting=m, e_move_bp=lv[t, j]) for t, d in enumerate(dates) for j, m in enumerate(ms)])
A = build(ms, 0.3)
if scen == "shared": B = build(ms, 0.6)
else:
    shuf = list(rng.permutation(ms)); B = build(shuf, 0.3)
A.to_csv(f"/tmp/synA_{scen}.csv", index=False); B.to_csv(f"/tmp/synB_{scen}.csv", index=False)
print("wrote", scen)
