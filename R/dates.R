#' Convert a Republic-of-China (民國) date string to a Date
#'
#' MOI registration data stores dates as ROC year + month + day with no
#' separators, e.g. \code{"1130215"} = ROC 113 (2024) / 02 / 15. The ROC year may
#' be two or three digits, so strings are 6 or 7 characters; the last four
#' characters are always \code{MMDD}. Strings that encode an impossible calendar
#' date (e.g. month 13, day 00, day 32) return \code{NA}, which is what the
#' "remove unreasonable values" cleaning step relies on.
#'
#' @param x Character vector of ROC date strings (non-digits are ignored).
#' @param day_zero_to_one If \code{TRUE}, a day component of \code{"00"} is read
#'   as the 1st of the month instead of \code{NA}. Useful for
#'   \code{建築完成年月} records that only carry a year-month. Default
#'   \code{FALSE}.
#' @return A vector of class \code{Date}; unparseable entries are \code{NA}.
#' @examples
#' roc_to_date("1130215")            # 2024-02-15
#' roc_to_date("0990101")            # 2010-01-01
#' roc_to_date(c("1131301", "0"))    # NA, NA (month 13 / too short)
#' @export
roc_to_date <- function(x, day_zero_to_one = FALSE) {
  x <- as.character(x)
  digits <- gsub("[^0-9]", "", x)
  n <- nchar(digits)
  ok <- !is.na(digits) & n >= 5L          # need >=1 year digit + MMDD

  roc_y <- rep(NA_integer_, length(x))
  mo    <- rep(NA_integer_, length(x))
  dy    <- rep(NA_integer_, length(x))

  roc_y[ok] <- as.integer(substr(digits[ok], 1L, n[ok] - 4L))
  mo[ok]    <- as.integer(substr(digits[ok], n[ok] - 3L, n[ok] - 2L))
  dy[ok]    <- as.integer(substr(digits[ok], n[ok] - 1L, n[ok]))

  if (day_zero_to_one) dy[!is.na(dy) & dy == 0L] <- 1L

  greg_y <- roc_y + 1911L
  iso <- ifelse(
    is.na(roc_y) | is.na(mo) | is.na(dy) |
      mo < 1L | mo > 12L | dy < 1L | dy > 31L,
    NA_character_,
    sprintf("%04d-%02d-%02d", greg_y, mo, dy)
  )
  # as.Date validates day-of-month against the actual month (e.g. 2-30 -> NA).
  as.Date(iso, format = "%Y-%m-%d")
}

#' Convert a date to a ROC year-month-day string
#'
#' Inverse of \code{\link{roc_to_date}}; mainly useful for round-tripping or
#' for building filters against the raw \code{交易年月日} column.
#'
#' @param date A \code{Date} or value coercible by \code{as.Date()}.
#' @return Character vector like \code{"1130215"} (\code{NA} preserved).
#' @examples
#' date_to_roc("2024-02-15")  # "1130215"
#' @export
date_to_roc <- function(date) {
  date <- as.Date(date)
  y <- as.integer(format(date, "%Y")) - 1911L
  ifelse(is.na(date), NA_character_,
         sprintf("%d%s%s", y, format(date, "%m"), format(date, "%d")))
}
