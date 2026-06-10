#' Default keyword groups for flagging non-arm's-length transactions
#'
#' Each element is a regular expression matched against the remark column
#' (\code{備註}). The defaults cover the four families called out for cleaning:
#' related-party / corporate, foreclosure, and "death house" (凶宅) deals.
#' Override or extend via the \code{abnormal_keywords} argument of
#' \code{\link{plvr_clean}}.
#'
#' @return A named list of regex strings.
#' @examples
#' plvr_abnormal_keywords()
#' @export
plvr_abnormal_keywords <- function() {
  list(
    related = "親友|親屬|親等|家屬|員工|共有人|特殊關係|關係人|關係企業",
    corporate = "法人|公司間|關係企業",
    foreclosure = "法拍|拍賣|查封|金融機構債權|債權",
    death_house = "凶宅|兇宅|兇殺|凶殺|自殺|身故|死亡|非自然"
  )
}

#' Flag non-arm's-length transactions from the remark column
#'
#' @param df A data frame containing a \code{備註} remark column.
#' @param keywords Named list of regex groups (default
#'   \code{\link{plvr_abnormal_keywords}}).
#' @return A character vector the length of \code{nrow(df)}: the matched group
#'   name(s) joined by \code{"|"}, or \code{NA} when nothing matched.
#' @export
plvr_flag_abnormal <- function(df, keywords = plvr_abnormal_keywords()) {
  note <- if ("備註" %in% names(df)) as.character(df[["備註"]]) else
    rep(NA_character_, nrow(df))
  note[is.na(note)] <- ""
  reasons <- lapply(names(keywords), function(k) {
    ifelse(grepl(keywords[[k]], note), k, NA_character_)
  })
  apply(do.call(cbind, reasons), 1L, function(r) {
    r <- r[!is.na(r)]
    if (length(r)) paste(r, collapse = "|") else NA_character_
  })
}

# Per-group two-sided quantile trim. Groups with too few non-NA values are left
# untouched; NA values are never trimmed.
.trim_by_group <- function(value, group, p) {
  keep <- rep(TRUE, length(value))
  for (gg in unique(group)) {
    idx <- which(group == gg & !is.na(value))
    if (length(idx) < 20L) next
    qs <- stats::quantile(value[idx], c(p, 1 - p), names = FALSE)
    bad <- idx[value[idx] < qs[1L] | value[idx] > qs[2L]]
    keep[bad] <- FALSE
  }
  keep
}

#' Clean MOI real-estate registration data
#'
#' A composable \code{data.frame -> data.frame} cleaning pipeline. Steps run in
#' this order and each can be toggled independently:
#' \enumerate{
#'   \item \strong{Feature engineering} (\code{add_features}) — parse raw columns
#'         into typed features via \code{\link{plvr_add_features}}. Needed by the
#'         filters below, so it runs first.
#'   \item \strong{Remove unreasonable values} (\code{drop_invalid}) — rows with
#'         a non-positive / missing price, an unparseable transaction date (e.g.
#'         month 13), or a zero building/land area inconsistent with the
#'         transaction target.
#'   \item \strong{Remove non-arm's-length transactions} (\code{drop_abnormal})
#'         — related-party, corporate, foreclosure and 凶宅 deals matched in the
#'         remark column.
#'   \item \strong{Filter transaction target} (\code{target}) — keep only
#'         房地 / 房 / 地 (and/or 車位).
#'   \item \strong{Trim extreme values} (\code{trim_extreme}) — drop the top and
#'         bottom \code{trim_prob} of unit price (單價) within each season.
#' }
#'
#' @param df Raw rows (e.g. from a Parquet file written by
#'   \code{\link{plvr_download}}).
#' @param type \code{"auto"} (default), \code{"sale"}, \code{"presale"} or
#'   \code{"rent"}.
#' @param add_features Run feature engineering. Default \code{TRUE}.
#' @param drop_invalid Remove unreasonable values. Default \code{TRUE}.
#' @param drop_abnormal Remove non-arm's-length transactions. Default
#'   \code{TRUE}.
#' @param abnormal_keywords Keyword groups for \code{drop_abnormal} (see
#'   \code{\link{plvr_abnormal_keywords}}).
#' @param target Character vector of targets to keep: any of \code{"房地"},
#'   \code{"房"}, \code{"地"}, \code{"車位"}. \code{NULL} (default) keeps all.
#' @param trim_extreme Trim per-season unit-price outliers. Default
#'   \code{FALSE}.
#' @param trim_prob Tail probability for trimming (default \code{0.01} = 1\%).
#' @param quiet Suppress per-step row-count messages.
#' @return The cleaned data frame (with feature columns when
#'   \code{add_features = TRUE}).
#' @examples
#' \dontrun{
#' df  <- arrow::read_parquet("trans/113S1.parquet")
#' out <- plvr_clean(df, type = "sale",
#'                   target = c("房地", "房"), trim_extreme = TRUE)
#' }
#' @export
plvr_clean <- function(df, type = c("auto", "sale", "presale", "rent"),
                       add_features = TRUE,
                       drop_invalid = TRUE,
                       drop_abnormal = TRUE,
                       abnormal_keywords = plvr_abnormal_keywords(),
                       target = NULL,
                       trim_extreme = FALSE,
                       trim_prob = 0.01,
                       quiet = FALSE) {
  type <- match.arg(type)
  if (type == "auto") type <- .detect_type(df)
  msg <- function(...) if (!quiet) message(...)
  n0 <- nrow(df)
  msg(sprintf("[clean:%s] start: %d rows", type, n0))

  # 1. features (required by later filters) ---------------------------------
  if (add_features || drop_invalid || trim_extreme || !is.null(target)) {
    df <- plvr_add_features(df, type = type)
  }

  # 2. unreasonable values --------------------------------------------------
  if (drop_invalid) {
    keep <- !is.na(df$trans_date) &                       # 月13 等 -> NA
      !is.na(df$price_total) & df$price_total > 0          # 0元 / 缺漏
    bld <- df$target_class %in% c("房地", "房")
    keep <- keep & !(bld & (is.na(df$building_area) | df$building_area <= 0))
    lnd <- df$target_class %in% c("地")
    keep <- keep & !(lnd & (is.na(df$land_area) | df$land_area <= 0))
    df <- df[keep, , drop = FALSE]
    msg(sprintf("  drop_invalid: -%d -> %d rows", n0 - nrow(df), nrow(df)))
  }

  # 3. non-arm's-length transactions ----------------------------------------
  if (drop_abnormal) {
    before <- nrow(df)
    df$abnormal_reason <- plvr_flag_abnormal(df, abnormal_keywords)
    df <- df[is.na(df$abnormal_reason), , drop = FALSE]
    df$abnormal_reason <- NULL
    msg(sprintf("  drop_abnormal: -%d -> %d rows", before - nrow(df), nrow(df)))
  }

  # 4. transaction-target filter --------------------------------------------
  if (!is.null(target)) {
    target <- as.character(target)
    before <- nrow(df)
    df <- df[!is.na(df$target_class) & df$target_class %in% target, ,
             drop = FALSE]
    msg(sprintf("  target[%s]: -%d -> %d rows",
                paste(target, collapse = ","), before - nrow(df), nrow(df)))
  }

  # 5. per-season unit-price trimming ---------------------------------------
  if (trim_extreme) {
    before <- nrow(df)
    grp <- if ("season" %in% names(df)) as.character(df$season) else {
      q <- (df$trans_month - 1L) %/% 3L + 1L
      paste0(df$trans_year, "S", q)
    }
    keep <- .trim_by_group(df$price_unit, grp, trim_prob)
    df <- df[keep, , drop = FALSE]
    msg(sprintf("  trim_extreme(%.0f%%, 單價/季): -%d -> %d rows",
                trim_prob * 100, before - nrow(df), nrow(df)))
  }

  rownames(df) <- NULL
  df
}
