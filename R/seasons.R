#' Convert a date to a ROC season code
#'
#' The MOI publishes data per calendar quarter, labelled by Republic-of-China
#' (民國) year and quarter, e.g. \code{"113S1"} = ROC 113 (2024), Q1.
#'
#' @param date A \code{Date} or a string coercible by \code{as.Date()}
#'   (e.g. \code{"2024-02-15"}).
#' @return A length-one character season code such as \code{"113S1"}.
#' @examples
#' date_to_season("2024-02-15")  # "113S1"
#' date_to_season("2012-08-01")  # "101S3"
#' @export
date_to_season <- function(date) {
  date <- as.Date(date)
  if (any(is.na(date))) stop("`date` could not be parsed as a Date.")
  y <- as.integer(format(date, "%Y")) - 1911L
  m <- as.integer(format(date, "%m"))
  q <- (m - 1L) %/% 3L + 1L
  sprintf("%dS%d", y, q)
}

#' List the ROC seasons overlapping a date range
#'
#' Returns every quarter (inclusive) touched by \code{[start, end]}. Because the
#' source data is quarterly, a daily range is widened to whole quarters; filter
#' rows by the transaction-date column afterwards if you need exact-day limits.
#'
#' @param start,end Dates (or strings) bounding the range, inclusive.
#' @return A character vector of season codes in chronological order.
#' @examples
#' seasons_in_range("2023-11-01", "2024-04-30")
#' # "112S4" "113S1" "113S2"
#' @export
seasons_in_range <- function(start, end) {
  start <- as.Date(start)
  end <- as.Date(end)
  if (is.na(start) || is.na(end)) stop("`start`/`end` could not be parsed as Dates.")
  if (end < start) stop("`end` must not be earlier than `start`.")

  y <- as.integer(format(start, "%Y"))
  q <- (as.integer(format(start, "%m")) - 1L) %/% 3L + 1L
  ye <- as.integer(format(end, "%Y"))
  qe <- (as.integer(format(end, "%m")) - 1L) %/% 3L + 1L

  out <- character(0)
  repeat {
    out <- c(out, sprintf("%dS%d", y - 1911L, q))
    if (y == ye && q == qe) break
    q <- q + 1L
    if (q > 4L) { q <- 1L; y <- y + 1L }
  }
  out
}

#' Build the download URL for a season's CSV zip
#'
#' @param season A season code such as \code{"113S1"}.
#' @return The download URL (character).
#' @export
plvr_season_url <- function(season) {
  sprintf(
    "https://plvr.land.moi.gov.tw/DownloadSeason?season=%s&type=zip&fileName=lvr_landcsv.zip",
    season
  )
}
