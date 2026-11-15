# wrangle.R
# Functions that turn raw Kalshi candles into a daily expected-move panel per FOMC meeting.
# Same steps as Section 2 of report/track2_report.Rmd, with each threshold as an argument.
# Source from track2_pipeline/ or report/; needs dplyr, tidyr, lubridate, stringr, readr.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(lubridate)
  library(stringr)
  library(readr)
})

# policy move per Kalshi leg outcome, in basis points
MOVE_BP <- c(CUT50P = -50, CUT25 = -25, HOLD = 0, HIKE25 = 25, HIKE50P = 50)

# 7 meetings in the network and the analysis dates
NODES     <- c("2026-10", "2026-12", "2027-01", "2027-03", "2027-04", "2027-06", "2027-07")
HIKE_DATE <- as.Date("2026-09-16")
START     <- as.Date("2025-10-06")
END       <- as.Date("2026-10-27")

# read_raw: read the three input files.
# Input: raw_dir (folder with kalshi_candles.csv, kalshi_markets.csv), meetings_file (FOMC calendar CSV).
# Output: list(candles, markets, meetings) of tibbles.
read_raw <- function(raw_dir = "data/raw", meetings_file = "data/meetings.csv") {
  list(candles  = read_csv(file.path(raw_dir, "kalshi_candles.csv"), show_col_types = FALSE),
       markets  = read_csv(file.path(raw_dir, "kalshi_markets.csv"), show_col_types = FALSE),
       meetings = read_csv(meetings_file, show_col_types = FALSE))
}

# add_trading_date: add the trading date each daily candle covers.
# Input: candles with ts (candle end, Unix seconds). rule = "est" or "eastern".
# Output: candles with a Date column `date`.
# Kalshi candles end at 04:00 or 05:00 UTC. "est" reads ts - 1 s on a fixed UTC-5 clock, which gives the
# previous calendar day for both. "eastern" uses America/New_York, as the submitted report did; it misdates
# a candle ending at 05:00 UTC once daylight time has started (2026-03-09 in the original pull).
add_trading_date <- function(candles, rule = c("est", "eastern")) {
  rule <- match.arg(rule)
  tz <- if (rule == "est") "Etc/GMT+5" else "America/New_York"   # Etc/GMT+5 is UTC-5 all year
  mutate(candles, date = as_date(with_tz(as_datetime(ts - 1, tz = "UTC"), tz)))
}

# pick_leg_price: one probability per leg per day.
# Input: candles with bid, ask, last (dollars 0 to 1). max_spread in dollars.
# Output: candles with empty_book, p (probability), spread; rows with a wider spread or no price removed.
# p is the bid/ask midpoint, or the last trade when the book is empty (bid 0 and ask 0.99 or more).
pick_leg_price <- function(candles, max_spread = 0.20) {
  candles |>
    mutate(empty_book = bid == 0 & ask >= 0.99,
           p = if_else(empty_book, last, (bid + ask) / 2),
           spread = ask - bid) |>
    filter(spread <= max_spread | empty_book, !is.na(p))
}

# code_to_meeting: event ticker to meeting month.
# Input: character vector such as "KXFEDDECISION-26DEC". Output: "YYYY-MM", e.g. "2026-12".
code_to_meeting <- function(event) {
  code <- str_remove(event, "^KXFEDDECISION-")
  month_num <- match(str_sub(code, 3, 5), toupper(month.abb))
  sprintf("20%s-%02d", str_sub(code, 1, 2), month_num)
}

# attach_meetings: add meeting, move_bp and decision_date; drop decision-day and later prices.
# Input: priced candles, meetings calendar (meeting, decision_date), move_bp named vector in bp.
# Output: one row per leg per day before the decision date.
attach_meetings <- function(candles, meetings, move_bp = MOVE_BP) {
  candles |>
    mutate(meeting = code_to_meeting(event),
           move_bp = unname(move_bp[outcome])) |>
    left_join(select(meetings, meeting, decision_date), by = "meeting") |>
    filter(date < decision_date)   # decision-day mids all read 0.50 (settlement)
}

# fill_leg_gaps: daily rows per leg, carrying the last price forward for at most max_stale days.
# Input: legs from attach_meetings, max_stale in days. Output: market, meeting, outcome, move_bp, date, p, obs_date.
fill_leg_gaps <- function(legs, max_stale = 5) {
  legs |>
    select(market, meeting, outcome, move_bp, date, p) |>
    group_by(market, meeting, outcome, move_bp) |>
    complete(date = seq(min(date), max(date), by = "day")) |>
    mutate(obs_date = if_else(is.na(p), NA_Date_, date)) |>
    fill(p, obs_date, .direction = "down") |>
    filter(date - obs_date <= max_stale) |>
    ungroup()
}

# expected_move_panel: expected policy move per meeting per day.
# Input: legs_daily, sum_range (allowed range of the raw leg-price sum).
# Output: list(panel = kept days, dropped = days outside sum_range); columns meeting, date, n_legs, sum_raw, e_move_bp (bp).
expected_move_panel <- function(legs_daily, sum_range = c(0.80, 1.20)) {
  all_days <- legs_daily |>
    group_by(meeting, date) |>
    summarise(n_legs = n(), sum_raw = sum(p), e_move_bp = sum(p * move_bp) / sum(p), .groups = "drop")
  keep <- between(all_days$sum_raw, sum_range[1], sum_range[2])
  list(panel = all_days[keep, ], dropped = all_days[!keep, ])
}

# daily_changes: wide table of daily changes in expected move, split at the hike.
# Input: panel, nodes (meetings), start and end dates, hike_date.
# Output: tibble with date, one column per node (change in bp), window ("before"/"after"); hike day excluded.
daily_changes <- function(panel, nodes = NODES, start = START, end = END, hike_date = HIKE_DATE) {
  wide <- panel |>
    filter(meeting %in% nodes, date >= start, date <= end) |>
    select(date, meeting, e_move_bp) |>
    pivot_wider(names_from = meeting, values_from = e_move_bp) |>
    complete(date = seq(min(date), max(date), by = "day")) |>
    arrange(date)
  wide |>
    mutate(across(all_of(nodes), ~ .x - lag(.x))) |>
    slice(-1) |>
    mutate(window = case_when(date < hike_date ~ "before",
                              date > hike_date ~ "after",
                              TRUE ~ NA_character_)) |>
    filter(!is.na(window))
}

# build_panel: run all wrangling steps on raw inputs.
# Input: raw (from read_raw), date_rule, max_spread (dollars), max_stale (days), sum_range, move_bp (bp per outcome).
# Output: list(legs, legs_daily, panel, dropped, changes).
build_panel <- function(raw, date_rule = "est", max_spread = 0.20, max_stale = 5,
                        sum_range = c(0.80, 1.20), move_bp = MOVE_BP, nodes = NODES) {
  legs <- raw$candles |>
    add_trading_date(date_rule) |>
    pick_leg_price(max_spread) |>
    attach_meetings(raw$meetings, move_bp)
  legs_daily <- fill_leg_gaps(legs, max_stale)
  em <- expected_move_panel(legs_daily, sum_range)
  list(legs = legs, legs_daily = legs_daily, panel = em$panel, dropped = em$dropped,
       changes = daily_changes(em$panel, nodes))
}
