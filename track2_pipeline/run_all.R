# run_all.R
# Rebuild everything from track2_pipeline/: download raw data if missing, run tests, knit the reports.
# Usage: Rscript run_all.R            (keeps existing data/raw/)
#        Rscript run_all.R --refresh  (downloads the 2026-10-29 snapshot again)
# Knitting outside RStudio needs pandoc; set RSTUDIO_PANDOC to RStudio's pandoc folder if it is not on PATH.

args <- commandArgs(trailingOnly = TRUE)
raw_file <- "data/raw/kalshi_candles.csv"

# step 1: raw data from Kalshi's public API (about 20 s)
if (!file.exists(raw_file) || "--refresh" %in% args) {
  message("downloading Kalshi data to data/raw/")
  source("R/pull_kalshi.R")
}

# step 2: unit tests and the regression test against the submitted report's numbers
testthat::test_dir("tests/testthat", reporter = "summary", stop_on_failure = TRUE)

# step 3: knit the submitted report, its slides (reuse the report's figures), and the extensions
for (f in c("report/track2_report.Rmd", "report/track2_slides.Rmd", "report/extensions.Rmd")) {
  message("knitting ", f)
  rmarkdown::render(f, quiet = TRUE, envir = new.env())
}
message("done: report/track2_report.html, report/track2_slides.html, report/extensions.html")
