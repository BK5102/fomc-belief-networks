"""Download hourly prices for Polymarket Fed-decision markets. Public Gamma and CLOB endpoints, no API key.
Step 1: list one event slug per FOMC meeting in data/raw/polymarket/slugs.csv (columns: meeting,slug),
        for example 2026-10,fed-decision-in-october-xxx (the slug is the last part of the polymarket.com event URL).
        Run with --discover to write candidate slugs to slug_candidates.csv; check each one by hand.
Step 2: run with no flag. Writes data/raw/polymarket/markets.csv and data/raw/polymarket/prices.csv."""
import re, sys, time
import pandas as pd
from common import http_json, RAW

GAMMA = "https://gamma-api.polymarket.com"
CLOB = "https://clob.polymarket.com/prices-history"
OUT = RAW / "polymarket"

def classify(q):
    """Map a market question (str) to an outcome label in MOVE_BP, or "OTHER" when no pattern matches.
    A "25+ bps" hike question maps to HIKE25; check the outcome column in markets.csv."""
    q = q.lower()
    if re.search(r"no change|unchanged|hold", q): return "HOLD"
    dec = re.search(r"decrease|cut|lower", q); inc = re.search(r"increase|hike|raise", q)
    big = re.search(r"50\+|50 bps|75|100", q)   # move of 50 bp or more
    if dec: return "CUT50P" if big else "CUT25"
    if inc: return "HIKE50P" if big else "HIKE25"
    return "OTHER"

def discover():
    """Search Gamma for "Fed decision" events and write title, slug, end date to slug_candidates.csv."""
    res = http_json(f"{GAMMA}/public-search", {"q": "Fed decision", "limit_per_type": 50})
    rows = []
    for ev in res.get("events", []):
        t = ev.get("title", "")
        if re.search(r"fed (rate )?decision", t, re.I):
            rows.append(dict(title=t, slug=ev.get("slug"), end=ev.get("endDate")))
    OUT.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(OUT / "slug_candidates.csv", index=False)
    print(pd.DataFrame(rows).to_string(index=False))
    print("-> copy the right slugs into data/raw/polymarket/slugs.csv (meeting,slug)")

def main():
    """For each slug in slugs.csv, fetch its markets and the full hourly price history of each Yes token.
    Output files: markets.csv (meeting, slug, question, outcome, token, volume) and
    prices.csv (meeting, outcome, token, ts in Unix seconds, p = Yes price in dollars 0 to 1)."""
    if "--discover" in sys.argv:
        return discover()
    slugs = pd.read_csv(OUT / "slugs.csv")
    mk_rows, px_rows = [], []
    for _, s in slugs.iterrows():
        evs = http_json(f"{GAMMA}/events", {"slug": s["slug"]})
        if not evs: print("no event for", s["slug"]); continue
        ev = evs[0]
        for m in ev.get("markets", []):
            outcome = classify(m.get("question", ""))
            # Gamma returns clobTokenIds and outcomes as JSON-encoded strings
            toks = m.get("clobTokenIds"); toks = eval(toks) if isinstance(toks, str) else toks
            outs = m.get("outcomes"); outs = eval(outs) if isinstance(outs, str) else outs
            if not toks or "Yes" not in (outs or []): continue
            yes_tok = toks[outs.index("Yes")]
            mk_rows.append(dict(meeting=s["meeting"], slug=s["slug"], question=m.get("question"),
                                outcome=outcome, token=yes_tok, volume=m.get("volume")))
            # interval=max requests the full history; fidelity=60 requests one point per 60 minutes
            h = http_json(CLOB, {"market": yes_tok, "interval": "max", "fidelity": 60}).get("history", [])
            for p in h: px_rows.append(dict(meeting=s["meeting"], outcome=outcome, token=yes_tok, ts=p["t"], p=p["p"]))
            print(f"{s['meeting']} {outcome:8s} {m.get('question','')[:60]:60s} pts={len(h)}")
            time.sleep(0.2)   # 0.2 s between price requests
    pd.DataFrame(mk_rows).to_csv(OUT / "markets.csv", index=False)
    pd.DataFrame(px_rows).to_csv(OUT / "prices.csv", index=False)

if __name__ == "__main__":
    main()
