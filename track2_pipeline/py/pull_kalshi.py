"""Download daily candles for every Kalshi KXFEDDECISION market (one event per FOMC meeting, 5 legs).
Public endpoints, no API key. Endpoint paths and field names follow docs.kalshi.com.
Writes data/raw/kalshi/markets.csv (one row per market) and data/raw/kalshi/candles.csv (one row per market per day).
Events up to 2026-07 list no nested markets; their markets and candles come from the /historical endpoints."""
import time
import pandas as pd
from common import http_json, RAW, KALSHI_LEG, MOVE_BP

BASE = "https://api.elections.kalshi.com/trade-api/v2"
SERIES = "KXFEDDECISION"
OUT = RAW / "kalshi"


def list_events():
    """Return a list of event dicts (with nested markets) for SERIES, deduplicated by event_ticker.
    Queries with no status filter and with open, settled, closed, following the cursor until it is empty."""
    events, seen = [], set()
    for status in (None, "open", "settled", "closed"):
        cursor = None
        while True:
            p = {"series_ticker": SERIES, "with_nested_markets": "true", "limit": 200}
            if status: p["status"] = status
            if cursor: p["cursor"] = cursor
            body = http_json(f"{BASE}/events", p)
            for ev in body.get("events", []):
                if ev["event_ticker"] not in seen:
                    seen.add(ev["event_ticker"]); events.append(ev)
            cursor = body.get("cursor") or None
            if not cursor: break
    return events


def f(x):
    """Convert x to float; return None for missing or non-numeric values."""
    try: return float(x)
    except (TypeError, ValueError): return None


def historical_markets(event_ticker):
    """Return the market dicts for one archived event from /historical/markets (used when the event lists no nested markets)."""
    return http_json(f"{BASE}/historical/markets", {"event_ticker": event_ticker, "limit": 50}).get("markets", [])


def candles(market_ticker, start_ts, end_ts, step=1440, chunk_days=900, archived=False):
    """Fetch candles for one market.
    Inputs: market_ticker (str), start_ts and end_ts (Unix seconds), step (candle length in minutes, 1440 = daily),
    chunk_days (days per request), archived (True for markets listed by /historical/markets).
    Output: list of dicts with market, ts (candle end, Unix seconds), bid, ask, last (yes side, dollars 0 to 1),
    volume and oi (contracts)."""
    rows, s = [], start_ts
    # live markets use the series path; archived markets return 404 there and are served by /historical
    path = (f"/historical/markets/{market_ticker}/candlesticks" if archived
            else f"/series/{SERIES}/markets/{market_ticker}/candlesticks")
    while s < end_ts:
        e = min(end_ts, s + chunk_days * 86400)
        body = http_json(BASE + path, {"start_ts": s, "end_ts": e + 86400, "period_interval": step})
        for c in body.get("candlesticks", []):
            yb, ya, pr = c.get("yes_bid") or {}, c.get("yes_ask") or {}, c.get("price") or {}
            # live candles name prices close_dollars; archived candles name them close
            rows.append(dict(market=market_ticker, ts=int(c["end_period_ts"]),
                             bid=f(yb.get("close_dollars", yb.get("close"))), ask=f(ya.get("close_dollars", ya.get("close"))),
                             last=f(pr.get("close_dollars", pr.get("close"))), volume=f(c.get("volume_fp", c.get("volume"))),
                             oi=f(c.get("open_interest_fp", c.get("open_interest")))))
        s = e
        time.sleep(0.15)   # 0.15 s between requests to stay under the public rate limit
    return rows


def main():
    """Pull all events and candles, then write markets.csv and candles.csv to data/raw/kalshi/."""
    OUT.mkdir(parents=True, exist_ok=True)
    now = int(time.time())
    mk_rows, c_rows = [], []
    for ev in list_events():
        if not ev["event_ticker"].startswith(SERIES): continue   # skip the 2023-2024 FEDDECISION series
        markets = ev.get("markets") or []
        archived = not markets
        if archived: markets = historical_markets(ev["event_ticker"])
        for mk in markets:
            leg = mk["ticker"].rsplit("-", 1)[-1]
            outcome = KALSHI_LEG.get(leg)
            if outcome is None:
                print("skip unknown leg", mk["ticker"]); continue
            # candle history starts at the market open time; 2022-01-01 when the API omits it
            ot = pd.Timestamp(mk.get("open_time") or "2022-01-01", tz="UTC").timestamp()
            mk_rows.append(dict(event=ev["event_ticker"], market=mk["ticker"], leg=leg, outcome=outcome,
                                move_bp=MOVE_BP[outcome], status=mk.get("status"), result=mk.get("result"),
                                open_time=mk.get("open_time"), close_time=mk.get("close_time")))
            try:
                rows = candles(mk["ticker"], int(ot), now, archived=archived)
            except RuntimeError as err:
                print("candles failed", mk["ticker"], err); rows = []
            for r in rows: r.update(event=ev["event_ticker"], outcome=outcome)
            c_rows += rows
            print(f"{mk['ticker']:32s} bars={len(rows)}")
    pd.DataFrame(mk_rows).to_csv(OUT / "markets.csv", index=False)
    pd.DataFrame(c_rows).to_csv(OUT / "candles.csv", index=False)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
