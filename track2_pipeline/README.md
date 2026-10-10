# track2_pipeline

Code, data calendar and report for the project. See the top-level `README.md` for the question, findings and how to reproduce.

Run R from this folder (`setwd()` to `track2_pipeline/`), so that `data/raw/` and `data/meetings.csv` resolve.

| Path | Status | What it does |
|---|---|---|
| `R/pull_kalshi.R` | used | downloads Kalshi `KXFEDDECISION` events 26SEP to 27JUL into `data/raw/kalshi_{markets,candles}.csv` |
| `report/track2_report.Rmd` | used | all wrangling, EDA, graph analysis and figures; reads only local CSVs |
| `report/track2_slides.Rmd` | used | presentation slides; reuses `report/figures/` |
| `data/meetings.csv` | used | FOMC decision and effective dates from federalreserve.gov (2027+ tentative) |
| `py/` | prototype | Python pullers for Kalshi, Polymarket, CME ZQ futures (Yahoo, Barchart) and FRED EFFR; `panels.py` builds expected-move panels, including a least-squares conversion of the futures curve to per-meeting moves |
| `tests/` | prototype | checks for the futures conversion and leg normalization in `py/panels.py`; synthetic data generator |
| `R/analysis.R` | prototype | command-line MST comparison of two venues' panels (shared edges, Jaccard, permutation, Mantel) |
| `out/synthetic_demo_mst.png` | prototype | output of `R/analysis.R` on synthetic data |

Python prototype: run scripts from `py/` and tests from `tests/` (Python 3.12, pandas, numpy, yfinance).
