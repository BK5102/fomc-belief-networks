# regression test: the functions in R/ reproduce the submitted report's results on the original data.
# Skipped when data/raw/ is absent (for example on GitHub Actions, where the Kalshi data is not published).

raw_dir <- file.path(root, "data", "raw")

test_that("refactored pipeline reproduces the submitted report", {
  skip_if_not(file.exists(file.path(raw_dir, "kalshi_candles.csv")), "raw Kalshi data not downloaded")
  raw <- read_raw(raw_dir, file.path(root, "data", "meetings.csv"))
  skip_if_not(nrow(raw$candles) == 13211, "raw data is not the 2026-10-29 pull")
  b <- build_panel(raw, date_rule = "eastern")   # the date rule the report used
  expect_equal(nrow(b$panel), 2939)
  expect_equal(nrow(b$dropped), 123)
  be <- dplyr::filter(b$changes, window == "before")
  af <- dplyr::filter(b$changes, window == "after")
  expect_equal(c(nrow(be), nrow(af)), c(344, 41))
  tb <- build_mst(cor_matrix(be, NODES))
  ta <- build_mst(cor_matrix(af, NODES))
  expect_setequal(intersect(edge_keys(tb), edge_keys(ta)), c("2026-12|2027-01", "2027-06|2027-07"))
  mc <- perm_shared_mc(tb, ta, NODES, n_perm = 5000, seed = 301)
  expect_equal(round(mc$p, 3), 0.554)
  late <- build_mst(cor_matrix(dplyr::slice_tail(be, n = 41), NODES))
  expect_equal(n_shared(late, tb), 5)
})
