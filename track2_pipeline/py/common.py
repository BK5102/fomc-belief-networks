"""Paths, outcome-to-move maps, and HTTP helper shared by the Track 2 Python scripts."""
import json, time, urllib.request, urllib.parse
from pathlib import Path
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent   # track2_pipeline/
RAW = ROOT / "data" / "raw"
PANELS = ROOT / "data" / "panels"
MEETINGS = ROOT / "data" / "meetings.csv"

# outcome label -> policy move in basis points
MOVE_BP = {"CUT50P": -50, "CUT25": -25, "HOLD": 0, "HIKE25": 25, "HIKE50P": 50}
# Kalshi KXFEDDECISION market-ticker suffix (text after the last '-') -> outcome label
KALSHI_LEG = {"C26": "CUT50P", "C25": "CUT25", "H0": "HOLD", "H25": "HIKE25", "H26": "HIKE50P"}


def http_json(url, params=None, retries=4, pause=0.6):
    """GET a public URL and return parsed JSON.
    Inputs: url (str), params (dict of query parameters or None), retries (int), pause (base wait in seconds).
    Output: parsed JSON (dict or list). Waits pause * 2**i seconds after failed try i; raises RuntimeError after `retries` failures."""
    if params:
        url = url + ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
    last = None
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "track2-research/0.1"})
            with urllib.request.urlopen(req, timeout=40) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception as e:  # noqa
            last = e
            time.sleep(pause * (2 ** i))
    raise RuntimeError(f"GET failed after {retries} tries: {url} :: {last}")


def load_meetings():
    """Read data/meetings.csv. Output: DataFrame with meeting (YYYY-MM), decision_date and effective_date (Timestamps), status."""
    return pd.read_csv(MEETINGS, parse_dates=["decision_date", "effective_date"])
