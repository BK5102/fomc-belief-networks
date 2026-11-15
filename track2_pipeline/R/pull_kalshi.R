# pull_kalshi.R
# Downloads daily Kalshi prices for the FOMC meetings used in the report.
# Source: Kalshi public API (no key), series KXFEDDECISION, one event per meeting, 5 legs per event.
# Run once in RStudio with the working directory set to track2_pipeline/.
# Writes data/raw/kalshi_markets.csv (one row per leg) and data/raw/kalshi_candles.csv (one row per leg per day).
# The report (.Rmd) reads these files and makes no network calls.

library(httr2)
library(jsonlite)

BASE   <- "https://api.elections.kalshi.com/trade-api/v2"
SERIES <- "KXFEDDECISION"

# 7 meetings in the network plus 26SEP, used to check how expected the September 2026 hike was
EVENTS <- paste0(SERIES, "-", c("26SEP", "26OCT", "26DEC", "27JAN", "27MAR", "27APR", "27JUN", "27JUL"))

# ticker suffix -> outcome label and policy move in basis points
LEGS <- data.frame(
  leg     = c("C26", "C25", "H0", "H25", "H26"),
  outcome = c("CUT50P", "CUT25", "HOLD", "HIKE25", "HIKE50P"),
  move_bp = c(-50, -25, 0, 25, 50)
)

# get_json: GET one Kalshi endpoint.
# Inputs: path (string after BASE), query (named list of query parameters).
# Output: list(status = HTTP status code, body = parsed JSON as nested lists, NULL unless status is 200).
get_json <- function(path, query = list()) {
  resp <- request(BASE) |>
    req_url_path_append(path) |>
    req_url_query(!!!query) |>
    req_user_agent("dat301-track2/0.1") |>
    req_timeout(40) |>
    req_retry(max_tries = 4, backoff = function(i) 0.6 * 2^i) |>
    req_error(is_error = function(resp) FALSE) |>   # return 404s instead of stopping, so the caller can try /historical
    req_perform()
  status <- resp_status(resp)
  body <- if (status == 200) fromJSON(resp_body_string(resp), simplifyVector = FALSE) else NULL
  Sys.sleep(0.15)   # 0.15 s between requests to stay under the public rate limit
  list(status = status, body = body)
}

# num: convert one JSON value to a number.
# Input: a value that may be NULL, a string such as "0.0100", or a number. Output: numeric, NA when missing.
num <- function(x) if (is.null(x)) NA_real_ else suppressWarnings(as.numeric(x))

# event_markets: list the 5 leg markets of one event.
# Input: event ticker, e.g. "KXFEDDECISION-26DEC".
# Output: list(markets = list of market records, archived = TRUE when they came from /historical).
event_markets <- function(event) {
  r <- get_json(paste0("/events/", event), list(with_nested_markets = "true"))
  mk <- if (r$status == 200) c(r$body$markets, r$body$event$markets) else list()
  if (length(mk) > 0) return(list(markets = mk, archived = FALSE))
  # older events list no markets on /events; the archive serves them instead
  h <- get_json("/historical/markets", list(event_ticker = event, limit = 50))
  if (h$status != 200) stop("no markets for ", event, " (HTTP ", r$status, " and ", h$status, ")")
  list(markets = h$body$markets, archived = TRUE)
}

# market_candles: daily candles for one leg market.
# Inputs: market ticker, start_ts and end_ts (Unix seconds), archived (TRUE to use the /historical path).
# Output: data frame with market, ts (candle end, Unix seconds), bid, ask, last (yes side, dollars 0 to 1),
#   volume and oi (open interest), both in contracts. One request covers the whole span (under 900 days here).
market_candles <- function(market, start_ts, end_ts, archived) {
  path <- if (archived) paste0("/historical/markets/", market, "/candlesticks")
          else paste0("/series/", SERIES, "/markets/", market, "/candlesticks")
  q <- list(start_ts = start_ts, end_ts = end_ts + 86400, period_interval = 1440)   # 1440 min = daily candles
  r <- get_json(path, q)
  if (r$status == 404 && !archived) {   # a market archived after settling moves to /historical
    r <- get_json(paste0("/historical/markets/", market, "/candlesticks"), q)
  }
  if (r$status != 200) stop("candles failed for ", market, " (HTTP ", r$status, ")")
  cs <- r$body$candlesticks
  if (length(cs) == 0) return(NULL)
  # live candles name prices close_dollars and counts *_fp; archived candles use close, volume, open_interest
  pick <- function(a, b) if (!is.null(a)) a else b
  data.frame(
    market = market,
    ts     = sapply(cs, function(c) num(c$end_period_ts)),
    bid    = sapply(cs, function(c) num(pick(c$yes_bid$close_dollars, c$yes_bid$close))),
    ask    = sapply(cs, function(c) num(pick(c$yes_ask$close_dollars, c$yes_ask$close))),
    last   = sapply(cs, function(c) num(pick(c$price$close_dollars, c$price$close))),
    volume = sapply(cs, function(c) num(pick(c$volume_fp, c$volume))),
    oi     = sapply(cs, function(c) num(pick(c$open_interest_fp, c$open_interest)))
  )
}

# pull_kalshi: download all legs and daily candles for a set of events and write two CSVs.
# Inputs: events (event tickers), end_date (last US Eastern trading date to keep, Date),
#   out_dir (folder for the CSVs).
# Output: invisible list(markets, candles); writes out_dir/kalshi_markets.csv and out_dir/kalshi_candles.csv.
# The default end_date 2026-10-29 matches the original pull (run during 2026-10-29), so a re-run gives the same rows.
pull_kalshi <- function(events = EVENTS, end_date = as.Date("2026-10-29"), out_dir = "data/raw") {
  # last candle kept ends at midnight US Eastern after end_date
  end_ts <- as.numeric(as.POSIXct(paste(end_date + 1, "00:00:00"), tz = "America/New_York"))
  market_rows <- list()
  candle_rows <- list()
  for (event in events) {
    em <- event_markets(event)
    for (mk in em$markets) {
      leg <- sub(".*-", "", mk$ticker)   # text after the last "-", e.g. "H25"
      info <- LEGS[LEGS$leg == leg, ]
      if (nrow(info) == 0) { message("skip unknown leg ", mk$ticker); next }
      open_ts <- as.numeric(as.POSIXct(mk$open_time, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
      market_rows[[mk$ticker]] <- data.frame(
        event = event, market = mk$ticker, leg = leg, outcome = info$outcome, move_bp = info$move_bp,
        status = if (is.null(mk$status)) NA_character_ else mk$status,
        result = if (is.null(mk$result)) NA_character_ else mk$result,
        open_time = mk$open_time, close_time = mk$close_time
      )
      cd <- market_candles(mk$ticker, floor(open_ts), floor(end_ts), em$archived)
      if (!is.null(cd)) cd <- cd[cd$ts <= end_ts, ]   # the API pads end_ts by one day; trim back
      if (!is.null(cd) && nrow(cd) > 0) {
        cd$event <- event
        cd$outcome <- info$outcome
        candle_rows[[mk$ticker]] <- cd
      }
      message(sprintf("%-28s archived=%-5s days=%d", mk$ticker, em$archived, if (is.null(cd)) 0L else nrow(cd)))
    }
  }
  markets <- do.call(rbind, market_rows)
  candles <- do.call(rbind, candle_rows)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  write.csv(markets, file.path(out_dir, "kalshi_markets.csv"), row.names = FALSE)
  write.csv(candles, file.path(out_dir, "kalshi_candles.csv"), row.names = FALSE)
  message("wrote ", nrow(markets), " markets and ", nrow(candles), " candles to ", out_dir)
  invisible(list(markets = markets, candles = candles))
}

# run on source() or Rscript unless options(pull_kalshi.run = FALSE) is set first
# Rscript R/pull_kalshi.R [end_date YYYY-MM-DD] [out_dir]
if (isTRUE(getOption("pull_kalshi.run", TRUE))) {
  args <- commandArgs(trailingOnly = TRUE)
  pull_kalshi(end_date = if (length(args) >= 1) as.Date(args[1]) else as.Date("2026-10-29"),
              out_dir  = if (length(args) >= 2) args[2] else "data/raw")
}
