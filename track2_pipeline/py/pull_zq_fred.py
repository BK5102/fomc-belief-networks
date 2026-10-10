"""Collect 30-Day Fed Funds futures (CME ZQ) prices and the effective Fed funds rate (EFFR).
 (a) Live ZQ contracts from yfinance (tickers like ZQV26.CBT).
 (b) Expired contracts from Barchart CSVs (free account, Daily Prices tab, up to 2 years) saved by hand in
     data/raw/barchart/ as ZQZ25.csv, ZQF26.csv, ... ZQU26.csv. The script reads every ZQ*.csv found there.
 (c) EFFR in percent from FRED's public fredgraph.csv, no API key.
Outputs: data/raw/zq_prices.csv (date, contract, price) and data/raw/effr.csv (date, effr)."""
import io, re, urllib.request
import pandas as pd
from common import RAW

CODES = "FGHJKMNQUVXZ"   # CME month codes, January to December

def live_contracts(first="2026-10", last="2027-12"):
    """Return ZQ contract codes (e.g. ZQV26) for each month from `first` to `last` (YYYY-MM)."""
    out = []
    for p in pd.period_range(first, last, freq="M"):
        out.append(f"ZQ{CODES[p.month-1]}{p.year % 100:02d}")
    return out

def pull_live():
    """Download daily closes for live_contracts() from yfinance. Output: DataFrame date, contract, price (100 minus rate in percent)."""
    import yfinance as yf
    rows = []
    for c in live_contracts():
        h = yf.Ticker(f"{c}.CBT").history(period="max", interval="1d", auto_adjust=False)
        if h.empty: print("no data", c); continue
        for d, r in h.iterrows(): rows.append(dict(date=d.date(), contract=c, price=float(r["Close"])))
        print(c, len(h))
    return pd.DataFrame(rows)

def read_barchart(path):
    """Read one Barchart daily-price CSV. Contract name comes from the file name. Output: DataFrame date, contract, price."""
    df = pd.read_csv(path)
    dcol = next(c for c in df.columns if c.strip().lower() in ("time", "date"))
    pcol = next(c for c in df.columns if c.strip().lower() in ("latest", "last", "close", "settle"))
    df = df[pd.to_datetime(df[dcol], errors="coerce").notna()]   # drop Barchart's trailing "Downloaded from..." line
    return pd.DataFrame(dict(date=pd.to_datetime(df[dcol]).dt.date, contract=path.stem.upper(),
                             price=pd.to_numeric(df[pcol], errors="coerce")))

def pull_effr():
    """Download the full daily EFFR series from FRED. Output: DataFrame date, effr (percent), missing days dropped."""
    url = "https://fred.stlouisfed.org/graph/fredgraph.csv?id=EFFR"
    raw = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "track2"}), timeout=40).read().decode()
    df = pd.read_csv(io.StringIO(raw)); df.columns = ["date", "effr"]
    df["effr"] = pd.to_numeric(df["effr"], errors="coerce")   # FRED marks holidays with "."
    return df.dropna()

def main():
    """Combine live and Barchart ZQ prices, write zq_prices.csv and effr.csv to data/raw/."""
    RAW.mkdir(parents=True, exist_ok=True)
    parts = []
    try: parts.append(pull_live())
    except Exception as e: print("live pull failed:", e)
    for p in sorted((RAW / "barchart").glob("ZQ*.csv")):
        parts.append(read_barchart(p)); print("ingested", p.name)
    # Barchart rows come after live rows, so keep="last" keeps the Barchart price when both exist
    z = pd.concat(parts).dropna().drop_duplicates(["date", "contract"], keep="last")
    z.to_csv(RAW / "zq_prices.csv", index=False)
    pull_effr().to_csv(RAW / "effr.csv", index=False)
    print("contracts:", sorted(z.contract.unique()))

if __name__ == "__main__":
    main()
