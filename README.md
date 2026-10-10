# FOMC Belief Networks

**Do prediction-market traders price upcoming Fed meetings as separate bets, or as one connected forecast of the rate path?**

This project treats each upcoming FOMC meeting as a node in a network. It builds the network from daily Kalshi prediction-market prices, keeps the strongest links with a minimum spanning tree (MST), and tests whether that network changed after the Federal Reserve's 25 bp hike on 2026-09-16.

Built in R for DAT 301 (Exploring Data in R and Python) at Arizona State University, Fall 2026.

![Minimum spanning trees of FOMC meetings before and after the September 2026 hike](track2_pipeline/report/figures/graph-trees-1.png)

## Findings

- **Before the hike, the network is a chain of weak links.** Each meeting moves mostly with its neighbor in time (correlations of daily changes 0.17 to 0.32) and no meeting acts as a hub. Traders appear to update the rate path one step at a time, and many far-dated quotes are stale.
- **After the hike, the links roughly double in strength and the tree reorganizes.** Near meetings move together (up to rho = 0.58 between December 2026 and January 2027), January 2027 becomes a mild hub, and July 2027 moves against the rest.
- **The old structure did not carry over.** The two trees share 2 of 6 edges, which is what random relabelling gives on average (1.7; permutation p = 0.55).
- **The change is not only a short-window artifact.** A tree built from the last 41 days *before* the hike shares 5 of 6 edges with the full before tree.
- **The hike was expected, so this is not a shock reaction.** Kalshi priced it at 87% the day before. The shift came in the weeks after, as traders pushed expected hikes into 2027 (March 2027 went from about 0 to 13 bp), consistent with pricing a hiking cycle rather than a one-off move.

## Method

```
Kalshi public API (KXFEDDECISION, 8 meetings x 5 legs, 13,211 daily candles)
  -> US Eastern trading dates
  -> one price per leg per day (bid/ask midpoint; quotes wider than 20 cents treated as missing)
  -> forward-fill gaps up to 5 days; drop decision-day settlement prices
  -> expected move per meeting per day = sum(p x move) / sum(p), in basis points
     (days where the 5 legs sum outside 0.80 to 1.20 are dropped)
  -> daily changes, split at the hike: before (344 days) and after (41 days)
  -> 7 x 7 correlation matrix per window
  -> distance d = sqrt(2 (1 - rho))  ->  minimum spanning tree (igraph, Kruskal)
  -> compare trees: shared edges, permutation test (5,000 relabellings), degree
```

Nodes are the seven meetings from October 2026 to July 2027. Each meeting has five legs (cut more than 25 bp, cut 25, hold, hike 25, hike more than 25), coded as -50, -25, 0, +25 and +50 bp.

## Repository layout

```
track2_pipeline/
  R/pull_kalshi.R             downloads raw Kalshi data (httr2 + jsonlite, public endpoints, no key)
  report/track2_report.Rmd    the full analysis: wrangling, EDA, graph analysis, conclusions
  report/track2_report.html   knitted report
  report/track2_slides.Rmd    ioslides deck for the 10-minute presentation (+ .html)
  report/figures/             figures saved by the report and reused by the slides
  data/meetings.csv           FOMC decision and effective dates, 2025-01 to 2028-01 (2027+ tentative)
  py/, tests/, R/analysis.R   earlier Python prototype (Kalshi, Polymarket and Fed funds futures pullers,
                              panel builder with a futures least-squares step) and a generic MST
                              comparison script; not used by the final report
CONCEPTS.md                   plain-language glossary: Fed basics, prediction markets, statistics, graph theory
```

## Reproduce

The raw Kalshi data is **not included** in this repository, because Kalshi's terms do not allow republishing it. Download it yourself first:

1. Install R (4.4 or later) and the packages: `install.packages(c("tidyverse", "lubridate", "igraph", "plotly", "httr2", "jsonlite", "rmarkdown", "knitr"))`.
2. Download the data (about 20 seconds). From R, with the working directory set to `track2_pipeline/`:
   ```r
   source("R/pull_kalshi.R")   # writes data/raw/kalshi_markets.csv and data/raw/kalshi_candles.csv
   ```
3. Open `track2_pipeline/report/track2_report.Rmd` in RStudio and click **Knit**. The report reads only the local CSV files and makes no network calls. Knit `track2_slides.Rmd` after the report, since it reuses its figures.

The analysis stops at 2026-10-27, so a later download should give the same results, as long as Kalshi does not revise its historical candles.

## Limitations

- The after window has only 41 trading days, so its correlations are noisy and the permutation test has little power.
- Meetings in 2027 trade on 20 to 43% of days; stale quotes pull correlations toward zero, especially before the hike.
- One market only. The results describe Kalshi traders, not the whole rates market.
- FOMC dates from 2027 on are tentative, and the "more than 25 bp" legs are coded as exactly 50 bp.
- With 7 nodes a tree has 6 edges, so degree and shared-edge counts move in large steps.

## References

- Board of Governors of the Federal Reserve System. *Meeting calendars, statements, and minutes.* https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm
- Kalshi. *Kalshi API documentation.* https://docs.kalshi.com
- Kruskal, J. B. (1956). On the shortest spanning subtree of a graph and the traveling salesman problem. *Proceedings of the American Mathematical Society*, 7(1), 48-50.
- Mantegna, R. N. (1999). Hierarchical structure in financial markets. *The European Physical Journal B*, 11(1), 193-197.

## License

Code is released under the MIT License (see `LICENSE`). Kalshi market data is subject to Kalshi's terms and is not distributed here.
