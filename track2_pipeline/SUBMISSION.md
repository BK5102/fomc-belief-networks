# DAT 301 Project 1: Mapping How Kalshi Traders Link Upcoming Fed Meetings

Bhavana Kannan, Fall 2026, Dr. Neha Joshi.

## Contents of this folder
| File | What it is |
|---|---|
| `report/track2_report.html` | Final report (knitted) |
| `report/track2_report.Rmd` | Report source: all wrangling, analysis and figures in R |
| `report/track2_slides.html`, `report/track2_slides.Rmd` | Presentation slides and their source |
| `report/figures/*.png` | Figures saved by the report, reused by the slides |
| `R/pull_kalshi.R` | Downloads the raw data from Kalshi's public API (run once, 2026-10-29) |
| `data/raw/kalshi_candles.csv` | Raw daily prices, one row per contract per day |
| `data/raw/kalshi_markets.csv` | Raw contract list, one row per contract |
| `data/meetings.csv` | FOMC decision dates from federalreserve.gov |

## How to reproduce
1. Open `report/track2_report.Rmd` in RStudio and click Knit. It reads only the CSV files above and needs no internet.
2. Then knit `report/track2_slides.Rmd`.
3. Optional: to re-download the data, set the working directory to this folder and run `source("R/pull_kalshi.R")`.

R packages: tidyverse, lubridate, igraph, plotly, httr2, jsonlite, rmarkdown, knitr.

Raw Kalshi data is included for this course submission only and is not for redistribution.
