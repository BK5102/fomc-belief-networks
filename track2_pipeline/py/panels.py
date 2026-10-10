"""Build one daily panel per venue: expected FOMC move in basis points per meeting per day.
Prediction markets: E[move] = sum over outcomes of p * move, divided by the sum of p over the 5 legs.
Fed Funds futures: per day, solve for per-meeting moves that best fit the ZQ monthly curve by least squares.
Reference implementation for the R port (R/wrangle.R). Outputs data/panels/panel_{kalshi,polymarket,zq}.csv."""
import calendar, re
import numpy as np, pandas as pd
from common import RAW, PANELS, MOVE_BP, load_meetings

MON = {m.upper(): i for i, m in enumerate(calendar.month_abbr) if m}   # "OCT" -> 10

# ---------------------------------------------------------------- prediction markets
def _normalise(leg_long, meetings, max_stale=5, tol=(0.80, 1.20)):
    """Turn leg prices into an expected move per meeting per day.
    Inputs: leg_long with columns date, meeting, outcome, p (dollars 0 to 1); meetings from load_meetings();
    max_stale (days a price may be carried forward); tol (allowed range for the sum of leg prices).
    Output: DataFrame date, meeting, e_move_bp (bp), n_legs, sum_raw (sum of leg prices before normalising)."""
    dec = dict(zip(meetings.meeting, meetings.decision_date))
    out = []
    for (mt, oc), g in leg_long.groupby(["meeting", "outcome"]):
        s = g.groupby("date").p.last()
        # daily calendar from first price to the decision date (or last price if earlier)
        idx = pd.date_range(s.index.min(), min(pd.Timestamp(dec.get(mt, s.index.max())), s.index.max()), freq="D")
        s = s.reindex(idx).ffill(limit=max_stale)   # carry a price forward at most max_stale days
        out.append(pd.DataFrame(dict(date=idx, meeting=mt, outcome=oc, p=s.values)))
    if not out: return pd.DataFrame(columns=["date", "meeting", "e_move_bp", "n_legs", "sum_raw"])
    d = pd.concat(out).dropna()
    d["w"] = d.outcome.map(MOVE_BP)
    d = d.dropna(subset=["w"])
    agg = d.groupby(["date", "meeting"]).apply(
        lambda x: pd.Series(dict(sum_raw=x.p.sum(), n_legs=len(x), e_move_bp=(x.p * x.w).sum() / x.p.sum() if x.p.sum() > 0 else np.nan)),
        include_groups=False).reset_index()
    # drop dates where leg prices sum outside 0.80 to 1.20 (stale or one-sided book)
    agg.loc[(agg.sum_raw < tol[0]) | (agg.sum_raw > tol[1]), "e_move_bp"] = np.nan
    return agg.dropna(subset=["e_move_bp"])

def kalshi_panel():
    """Read data/raw/kalshi/{markets,candles}.csv and return the Kalshi panel (see _normalise)."""
    mk = pd.read_csv(RAW / "kalshi" / "markets.csv"); c = pd.read_csv(RAW / "kalshi" / "candles.csv")
    c = c.merge(mk[["market", "event", "outcome"]].drop_duplicates("market"), on="market", suffixes=("", "_m"))
    mid = (c.bid + c.ask) / 2
    # no resting bids and ask at 0.99 or higher means no usable quote; use last trade price instead
    empty_book = (c.bid.fillna(0) == 0) & (c.ask.fillna(1) >= 0.99)
    c["p"] = np.where(empty_book | mid.isna(), c["last"], mid)
    # candle end timestamp minus 1 s, in US Eastern time, gives the trading date the candle covers
    et = pd.to_datetime(c.ts, unit="s", utc=True).dt.tz_convert("America/New_York") - pd.Timedelta(seconds=1)
    c["date"] = et.dt.tz_localize(None).dt.normalize()
    def meeting_of(ev):
        """Event ticker such as KXFEDDECISION-26OCT -> meeting "2026-10"."""
        m = re.search(r"-(\d{2})([A-Z]{3})", ev); return f"20{m.group(1)}-{MON[m.group(2)]:02d}"
    c["meeting"] = c.event.map(meeting_of)
    return _normalise(c.dropna(subset=["p"])[["date", "meeting", "outcome", "p"]], load_meetings())

def polymarket_panel():
    """Read data/raw/polymarket/{markets,prices}.csv and return the Polymarket panel (see _normalise)."""
    mk = pd.read_csv(RAW / "polymarket" / "markets.csv"); px = pd.read_csv(RAW / "polymarket" / "prices.csv")
    px = px[px.outcome.isin(MOVE_BP)].copy()   # drop markets classified as OTHER
    et = pd.to_datetime(px.ts, unit="s", utc=True).dt.tz_convert("America/New_York")
    px["date"] = et.dt.tz_localize(None).dt.normalize()
    px = px.sort_values("ts")
    leg = px.groupby(["meeting", "outcome", "date"]).p.last().reset_index()   # last hourly price of each US Eastern day
    leg = leg.groupby(["date", "meeting", "outcome"], as_index=False).p.sum()   # add up markets that map to the same outcome
    return _normalise(leg, load_meetings())

# ---------------------------------------------------------------- Fed Funds futures conversion
CODES = "FGHJKMNQUVXZ"   # CME month codes, January to December
def contract_month(name):
    """ZQ contract code (e.g. ZQV26) -> pandas monthly Period (2026-10)."""
    m = re.match(r"ZQ([FGHJKMNQUVXZ])(\d{2})$", name.upper())
    return pd.Period(f"20{m.group(2)}-{CODES.index(m.group(1)) + 1:02d}", freq="M")

def month_weight(period, eff):
    """Fraction of the calendar month `period` on or after effective date `eff` (1 = whole month, 0 = none)."""
    start, end = period.start_time.normalize(), period.end_time.normalize()
    if eff <= start: return 1.0
    if eff > end: return 0.0
    return ((end - eff).days + 1) / ((end - start).days + 1)

def implied_moves(day, prices, effr, meetings, ridge=1e-6, min_contracts=3):
    """Per-meeting implied moves from one day's ZQ curve.
    Inputs: day (date), prices ({contract: price}), effr (percent, last value before `day`), meetings (load_meetings()),
    ridge (small penalty that keeps the solve stable), min_contracts (fewest usable contracts).
    Model: 100 - price = effr + sum over meetings of month_weight * move. Output: {meeting: move in bp}, empty if too few contracts."""
    day = pd.Timestamp(day)
    cm = {c: contract_month(c) for c in prices if not np.isnan(prices[c])}
    cm = {c: m for c, m in cm.items() if m > day.to_period("M")}          # drop the current month, already partly realised
    if len(cm) < min_contracts: return {}
    last = max(cm.values())
    # unknowns: meetings taking effect after `day` and before the end of the last contract month
    up = meetings[(meetings.effective_date > day) & (meetings.effective_date <= last.end_time)].reset_index(drop=True)
    if up.empty: return {}
    ks = sorted(cm, key=lambda c: cm[c])
    W = np.array([[month_weight(cm[c], eff) for eff in up.effective_date] for c in ks])   # contracts x meetings
    y = np.array([(100 - prices[c]) - effr for c in ks])                                   # implied rate minus EFFR, percent
    A = np.vstack([W, np.sqrt(ridge) * np.eye(W.shape[1])]); b = np.concatenate([y, np.zeros(W.shape[1])])
    e = np.linalg.lstsq(A, b, rcond=None)[0] * 100.0                       # percent -> bp
    return dict(zip(up.meeting, e))

def zq_panel():
    """Read data/raw/zq_prices.csv and effr.csv; return DataFrame date, meeting, e_move_bp (bp)."""
    z = pd.read_csv(RAW / "zq_prices.csv", parse_dates=["date"]); ef = pd.read_csv(RAW / "effr.csv", parse_dates=["date"]).set_index("date").effr
    meetings = load_meetings(); rows = []
    for day, g in z.groupby("date"):
        prev = ef[ef.index < day]   # EFFR for day d is published on d+1, so use the latest value before `day`
        if prev.empty: continue
        for mt, v in implied_moves(day, dict(zip(g.contract, g.price)), float(prev.iloc[-1]), meetings).items():
            rows.append(dict(date=day, meeting=mt, e_move_bp=v))
    return pd.DataFrame(rows)

def main():
    """Write one panel CSV per venue to data/panels/; skip a venue whose raw files are missing."""
    PANELS.mkdir(parents=True, exist_ok=True)
    for name, fn in (("kalshi", kalshi_panel), ("polymarket", polymarket_panel), ("zq", zq_panel)):
        try:
            p = fn(); p.to_csv(PANELS / f"panel_{name}.csv", index=False)
            print(name, p.shape, p.meeting.nunique() if len(p) else 0, "meetings")
        except FileNotFoundError as e:
            print("skip", name, "-", e)

if __name__ == "__main__":
    main()
