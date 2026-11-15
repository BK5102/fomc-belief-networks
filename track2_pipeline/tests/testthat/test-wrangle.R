# unit tests for R/wrangle.R on small hand-built inputs (no raw data needed)

test_that("event ticker maps to meeting month", {
  expect_equal(code_to_meeting(c("KXFEDDECISION-26DEC", "KXFEDDECISION-27JAN")), c("2026-12", "2027-01"))
})

test_that("candles ending at 04:00 or 05:00 UTC both map to the previous day", {
  # 2026-03-09 05:00 UTC (Sunday 03-08 candle stamped on EST) and 2026-03-10 04:00 UTC (Monday 03-09, EDT)
  c0 <- tibble::tibble(ts = c(1773032400, 1773115200))
  expect_equal(add_trading_date(c0, "est")$date, as.Date(c("2026-03-08", "2026-03-09")))
  # the America/New_York rule used in the submitted report puts both on 2026-03-09
  expect_equal(add_trading_date(c0, "eastern")$date, as.Date(c("2026-03-09", "2026-03-09")))
})

test_that("midpoint is used, empty book falls back to last trade, wide quotes are removed", {
  c0 <- tibble::tibble(bid = c(0.40, 0.00, 0.00), ask = c(0.42, 0.99, 0.48), last = c(0.50, 0.03, 0.10))
  out <- pick_leg_price(c0, max_spread = 0.20)
  expect_equal(nrow(out), 2)            # the 0.00 / 0.48 quote is dropped
  expect_equal(out$p, c(0.41, 0.03))
})

test_that("gaps are filled for at most max_stale days", {
  legs <- tibble::tibble(market = "M", meeting = "2026-12", outcome = "HOLD", move_bp = 0,
                         date = as.Date(c("2026-01-01", "2026-01-08")), p = c(0.6, 0.7))
  out <- fill_leg_gaps(legs, max_stale = 5)
  expect_equal(out$date, as.Date(c("2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04",
                                   "2026-01-05", "2026-01-06", "2026-01-08")))
  expect_equal(out$p[1:6], rep(0.6, 6))
})

test_that("expected move is the normalised probability-weighted move", {
  # ladder CUT25 0.40 / HOLD 0.55 / HIKE25 0.05 sums to 1.00: E = 0.40 * -25 + 0.05 * 25 = -8.75 bp
  ld <- tibble::tibble(meeting = "2026-12", date = as.Date("2026-01-01"),
                       move_bp = c(-25, 0, 25), p = c(0.40, 0.55, 0.05))
  em <- expected_move_panel(ld)
  expect_equal(em$panel$e_move_bp, -8.75)
  # same ladder doubled sums to 2.00 and is dropped
  em2 <- expected_move_panel(dplyr::mutate(ld, p = 2 * p))
  expect_equal(nrow(em2$panel), 0)
  expect_equal(nrow(em2$dropped), 1)
})

test_that("daily changes exclude the hike day and label the windows", {
  panel <- tibble::tibble(meeting = "2026-12",
                          date = as.Date("2026-09-13") + 0:6,
                          e_move_bp = c(0, 1, 3, 6, 10, 15, 21))
  ch <- daily_changes(panel, nodes = "2026-12", start = as.Date("2026-09-13"), end = as.Date("2026-09-19"))
  expect_false(any(ch$date == HIKE_DATE))
  expect_equal(ch$`2026-12`[ch$window == "before"], c(1, 2))
  expect_equal(ch$`2026-12`[ch$window == "after"], c(4, 5, 6))
})
