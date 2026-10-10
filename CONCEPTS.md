# CONCEPTS.md: everything to learn for this project, in one file

Updated 2026-10-29 for the narrowed project (Kalshi only, tree before vs after the September 2026 hike). The plan and schedule live in `PLAN_NOV1.md`.

## How to use this file
Learn the blocks in order. Each block lists what to learn, then defines every term. **Must** items are needed to explain your own report and video. **Nice** items help but can be skipped if time runs out.

| Block | Topic | Time | When |
|---|---|---|---|
| A | The Fed and interest rates | 20 min | Thu |
| B | Kalshi and prediction markets | 40 min | Thu |
| C | Statistics | 40 min | Fri morning |
| D | Graph theory | 50 min | Fri morning |
| E | R functions used in the code | while reading code | Thu to Sat |
| F | Report vocabulary and limitations | 15 min | Sat |

Total: about 2 h 45 min plus reading the code.

---

## Block A. The Fed and interest rates (20 min)

Learn: what the FOMC is, what the federal funds rate is, basis points, hike / cut / hold, decision vs effective date, why traders bet on meetings months ahead.

- **FOMC (Federal Open Market Committee).** (Must) The Fed group that sets US short-term interest rates. It meets about 8 times a year on a calendar published on the Fed's website.
- **Federal funds rate.** (Must) The overnight rate banks charge each other. The FOMC sets a target range for it, 25 bp wide (for example 3.75% to 4.00%).
- **Basis point (bp).** (Must) 0.01 percentage point. A 25 bp hike moves the rate from 3.75% to 4.00%.
- **Hike, cut, hold.** (Must) A hike raises the rate, a cut lowers it, a hold leaves it unchanged. Usual step size is 25 bp.
- **Decision date and effective date.** (Nice) The decision is announced on the last meeting day; the new rate starts the next business day.
- **Why markets look ahead.** (Must) A rate change affects loans, mortgages and stock prices, so traders bet on every upcoming meeting, not just the next one. Beliefs about one meeting depend on beliefs about the others, which is why a network of meetings makes sense.
- **The September 2026 hike.** (Must) On 2026-09-16 the FOMC raised the rate by 25 bp. This is the dividing line between the "before" and "after" trees.
- **Tentative dates.** (Nice) FOMC dates from 2027 on are provisional on the Fed calendar.

## Block B. Kalshi and prediction markets (40 min)

Learn: price as probability, events and legs, bid / ask / mid / spread, volume, stale prices, leg normalization, expected move.

- **Prediction market.** (Must) An exchange where people trade contracts that pay $1 if an event happens and $0 if not. Kalshi is a US-regulated one.
- **Price as probability.** (Must) A contract trading at $0.70 means traders give the event about a 70% chance.
- **Event.** (Must) One question, for example "What will the Fed do at the December 2026 meeting?" Kalshi ticker `KXFEDDECISION-26DEC`. One event per meeting.
- **Leg.** (Must) One possible answer to the event, traded as its own yes/no contract. Each meeting has five legs:

  | Leg code | Outcome | Move used (bp) |
  |---|---|---|
  | C26 | cut more than 25 bp | -50 |
  | C25 | cut 25 bp | -25 |
  | H0 | hold | 0 |
  | H25 | hike 25 bp | +25 |
  | H26 | hike more than 25 bp | +50 |

- **Bid, ask, mid, spread.** (Must) Bid is the best price a buyer offers; ask is the best price a seller offers; mid is their average; spread is ask minus bid. A wide spread means a thin, uncertain market. We use the mid as the probability.
- **Candle.** (Nice) One day of trading summed up as a few numbers: closing bid, ask, last trade price, volume. The name comes from candlestick charts. Each leg has one candle per day.
- **Volume.** (Must) Contracts traded that day. Zero means no trades happened.
- **Stale price.** (Must) A quote that stays the same because nobody trades. Meetings in 2027 trade on only 8 to 20 percent of days, so their prices are often stale. A frozen series has no daily changes and cannot be correlated.
- **Leg normalization.** (Must) The five leg prices rarely add up to exactly 1. Divide each by their sum so they do. Drop days where the raw sum is outside 0.80 to 1.20, because that signals a broken or one-sided quote.
- **Expected move.** (Must) The probability-weighted average of the possible rate changes, in bp. Example: hold 80%, hike 25 bp 20% gives 0.8 x 0 + 0.2 x 25 = 5 bp. This is the one number per meeting per day that the whole project is built on.
- **Settlement day.** (Nice) On the decision day the order book empties and all mids read 0.50, so each meeting's series ends the day before its decision.

## Block C. Statistics (40 min)

Learn: levels vs daily changes, correlation, correlation matrix, null hypothesis, p-value, permutation test.

- **Level vs daily change.** (Must) The level is the expected move on a day; the daily change is today's level minus yesterday's. Two series that both trend up look correlated even when unrelated, so the analysis correlates daily changes, not levels.
- **Pearson correlation (rho).** (Must) A number from -1 to 1 for how closely two series move together. 1: always move together. 0: no linear link. -1: always opposite.
- **Correlation matrix.** (Must) A table of rho for every pair of meetings. With 7 meetings it is 7 x 7, symmetric, with 1s on the diagonal.
- **Heatmap.** (Must) A picture of the correlation matrix where color shows the size of rho.
- **Null hypothesis.** (Must) The "nothing is going on" assumption. Here: the before and after trees share edges only by chance.
- **p-value.** (Must) How often chance alone would give a result at least as extreme as ours. A small value (below 0.05 by convention) means chance is a poor explanation. It is not the probability that the hypothesis is true.
- **Permutation test.** (Must) Build the "chance" baseline by shuffling. Randomly relabel the meetings on one tree 5000 times, count shared edges each time, and see how often the shuffled count matches or beats the real one. Report p = (k + 1) / (5000 + 1), where k is the number of shuffles that matched or beat it.
- **Sample size and noise.** (Must) The after window has only about 40 daily changes, so its correlations are noisier than the before window's (about 340). Say this in the limitations.

## Block D. Graph theory (50 min)

Learn: graph, weighted graph, correlation-to-distance, tree, spanning tree, MST, Kruskal's algorithm, degree and hub, chain vs star, shared edges.

- **Graph.** (Must) Nodes joined by edges. Here the nodes are the 7 FOMC meetings and an edge is a link between two meetings.
- **Weighted graph.** (Must) Each edge carries a number. Here the number is a distance.
- **Distance from correlation.** (Must) d = sqrt(2(1 - rho)). It turns "moves together" into "close". rho = 1 gives d = 0, rho = 0 gives 1.41, rho = -1 gives 2.
- **Complete graph.** (Nice) Every pair of nodes has an edge. Our 7 meetings give 21 edges before the tree is built.
- **Tree.** (Must) A connected graph with no loops. A tree on n nodes always has n - 1 edges.
- **Spanning tree.** (Must) A tree that reaches every node.
- **Minimum spanning tree (MST).** (Must) The spanning tree with the smallest total distance. It keeps the strongest links that still connect every meeting. With 7 meetings it keeps 6 of the 21 edges. It was first used on stock correlations by Mantegna (1999).
- **Kruskal's algorithm.** (Must, be able to explain) Sort all edges from shortest to longest. Go down the list and add each edge unless it would close a loop. Stop at n - 1 edges. `igraph::mst()` does this for us.
- **Degree.** (Must) Number of edges touching a node.
- **Hub.** (Must) A node with high degree: a meeting many others are tied to.
- **Chain vs star.** (Must) A chain links meetings in a line, each tied to its neighbor (degrees 1, 2, 2, ..., 1). A star has one hub tied to all others. If both trees are chains, degree says little and the shared-edge count is the main result.
- **Shared edges.** (Must) Edges present in both the before and after trees. 6 of 6 means identical trees; 0 means none in common.

## Block E. R functions used in the code (learn while reading)

| Function | Package | What it does in this project |
|---|---|---|
| `request()`, `req_perform()` | httr2 | download Kalshi data |
| `fromJSON()` | jsonlite | turn the API reply into a table |
| `read_csv()`, `write_csv()` | readr | read and save raw data |
| `filter()`, `mutate()`, `select()` | dplyr | pick rows, add columns, pick columns |
| `group_by()` + `summarise()` | dplyr | one result per meeting per day |
| `left_join()` | dplyr | attach the meeting calendar |
| `pivot_wider()` | tidyr | one column per meeting, one row per date |
| `as_datetime()`, `with_tz()` | lubridate | convert Kalshi timestamps to US Eastern dates |
| `cor()` | base R | correlation matrix of daily changes |
| `graph_from_adjacency_matrix()`, `mst()`, `degree()` | igraph | build the graph, the tree, the degrees |
| `ggplot()` + `geom_line/col/point/tile/boxplot` | ggplot2 | all figures |
| `sample()`, `set.seed()` | base R | shuffles for the permutation test, made repeatable |
| knit button | rmarkdown | turn the .Rmd into the HTML report |

## Block F. Report vocabulary and limitations (15 min)

- **Why Kalshi.** (Must) Kalshi quotes 11 to 19 Fed meetings every day from October 2025, so a network of many meetings exists on the same dates. Polymarket opens each meeting only 4 to 5 months ahead, so it has just 3 or 4 at a time.
- **Why not futures.** (Must, for future work) CME 30-Day Fed Funds futures (ticker ZQ) also price meetings: price = 100 minus the expected average rate for the month. Turning them into per-meeting moves needs an extra conversion step, cut for time. A futures-vs-Kalshi comparison is natural future work.
- **Futures are not options.** (Nice) A future tracks one number; an option is a right to buy or sell at a fixed price and reveals a full probability range. No accessible options market exists on the fed funds rate (Diercks, Katz and Wright, FEDS 2026-010).
- **Limitations to name.** (Must) Short after window; stale 2027 quotes; one market only; tentative 2027 dates; chain-shaped trees make degree uninformative; expected move uses -50 and +50 for the "more than 25 bp" legs.
- **Future work.** (Must) Compare with futures or Polymarket; rolling windows to watch the tree change over time; other events (CPI, jobs reports).
