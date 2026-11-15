# track2_pipeline

Code, data calendar and reports for the project. See the top-level `README.md` for the question, findings and how to reproduce.

Run R from this folder (`setwd()` to `track2_pipeline/`), so that `data/raw/` and `data/meetings.csv` resolve. `Rscript run_all.R` downloads the data if missing, runs the tests and knits all reports.

| Path | Status | What it does |
|---|---|---|
| `R/pull_kalshi.R` | used | downloads Kalshi `KXFEDDECISION` events 26SEP to 27JUL into `data/raw/kalshi_{markets,candles}.csv`; `Rscript R/pull_kalshi.R [end_date] [out_dir]` |
| `R/wrangle.R` | used | wrangling functions (trading dates, leg prices, gap filling, expected move, daily changes) |
| `R/graph.R` | used | correlation matrices, MSTs, exact and Monte Carlo permutation tests, Mantel, Jennrich, block null, block bootstrap, rolling trees |
| `report/track2_report.Rmd` | submitted | the graded report (tag `v1.0-submitted`); code inline, reads only local CSVs |
| `report/extensions.Rmd` | used | follow-up checks built on `R/wrangle.R` and `R/graph.R` |
| `report/track2_slides.Rmd` | submitted | presentation slides; reuses `report/figures/` |
| `tests/testthat/` | used | unit tests on hand-built inputs; regression test that `R/` reproduces the submitted report (skipped without raw data) |
| `data/meetings.csv` | used | FOMC decision and effective dates from federalreserve.gov (2027+ tentative) |
| `DESCRIPTION`, `renv.lock` | used | dependencies; `renv::restore()` installs the pinned versions |
| `py/` | prototype | Python pullers for Kalshi, Polymarket, CME ZQ futures (Yahoo, Barchart) and FRED EFFR; `panels.py` builds expected-move panels, including a least-squares conversion of the futures curve to per-meeting moves |
| `tests/*.py` | prototype | checks for the futures conversion and leg normalization in `py/panels.py`; synthetic data generator |
| `R/analysis.R` | prototype | command-line MST comparison of two venues' panels (shared edges, Jaccard, permutation, Mantel) |
| `out/synthetic_demo_mst.png` | prototype | output of `R/analysis.R` on synthetic data |

Python prototype: run scripts from `py/` and tests from `tests/` (Python 3.12, pandas, numpy, yfinance).
