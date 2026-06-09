# Dataset -> (zip filename suffix letter, output subfolder)
.plvr_types <- list(
  sale    = list(letter = "a", dir = "trans"),    # 買賣
  presale = list(letter = "b", dir = "presale"),  # 預售屋
  rent    = list(letter = "c", dir = "rent")      # 租賃
)

# Read one MOI county CSV.
# These files carry TWO header rows: row 1 = Traditional Chinese names,
# row 2 = English names. read_csv() takes row 1 as the header, so the first
# data row is the English header and must be dropped. Everything is read as
# character to avoid type-guessing on mixed/empty columns.
.read_plvr_csv <- function(path) {
  df <- readr::read_csv(
    path,
    col_types = readr::cols(.default = "c"),
    locale = readr::locale(encoding = "UTF-8"),
    show_col_types = FALSE,
    progress = FALSE
  )
  if (nrow(df) > 0L) df <- df[-1L, , drop = FALSE]  # drop English header row
  df
}

# Combine the per-county CSVs for one dataset in one season into a tibble,
# tagging each row with its county code/name and the season.
.collect_dataset <- function(extract_dir, letter, season, counties) {
  pattern <- sprintf("^[a-z]_lvr_land_%s\\.csv$", letter)
  files <- list.files(extract_dir, pattern = pattern, full.names = TRUE)
  if (!is.null(counties)) {
    keep <- substr(basename(files), 1L, 1L) %in% counties
    files <- files[keep]
  }
  if (length(files) == 0L) return(NULL)

  cmap <- plvr_county_map()
  parts <- lapply(files, function(f) {
    code <- substr(basename(f), 1L, 1L)
    df <- tryCatch(.read_plvr_csv(f), error = function(e) NULL)
    if (is.null(df) || nrow(df) == 0L) return(NULL)
    df[["county_code"]] <- code
    df[["county"]] <- unname(cmap[code])
    df[["season"]] <- season
    df
  })
  parts <- parts[!vapply(parts, is.null, logical(1))]
  if (length(parts) == 0L) return(NULL)

  # Union columns across counties (schemas can differ slightly by year).
  all_cols <- unique(unlist(lapply(parts, names)))
  parts <- lapply(parts, function(df) {
    miss <- setdiff(all_cols, names(df))
    for (m in miss) df[[m]] <- NA_character_
    df[all_cols]
  })
  do.call(rbind, parts)
}

#' Download MOI real-estate data for a date range
#'
#' Maps \code{[start, end]} to the calendar quarters it overlaps, downloads each
#' quarter's CSV zip from the MOI open-data site, extracts only the requested
#' datasets (and optionally counties), writes one Parquet file per quarter per
#' dataset, then deletes the raw zip to keep disk use low.
#'
#' Output layout (relative to \code{dir}):
#' \itemize{
#'   \item \code{trans/<season>.parquet}   — 買賣 (sale)
#'   \item \code{presale/<season>.parquet} — 預售屋 (presale)
#'   \item \code{rent/<season>.parquet}    — 租賃 (rent)
#' }
#'
#' @param start,end Date range (inclusive), as \code{Date} or \code{"yyyy-mm-dd"}.
#' @param dir Output root directory. Default current directory.
#' @param types Datasets to fetch: any of \code{"sale"}, \code{"presale"},
#'   \code{"rent"}. Default all three.
#' @param counties Optional vector of single-letter county codes
#'   (see \code{\link{plvr_county_map}}) to keep only those counties.
#'   \code{NULL} keeps all.
#' @param overwrite If \code{FALSE} (default), seasons whose Parquet outputs all
#'   already exist are skipped (resume-friendly).
#' @param timeout Per-file download timeout in seconds (default 600).
#' @param quiet Suppress progress messages.
#' @return Invisibly, a data frame logging each (season, type) result.
#' @examples
#' \dontrun{
#' # Everything from 2023-Q4 through 2024-Q2, all datasets:
#' plvr_download("2023-11-01", "2024-04-30")
#'
#' # Only Taipei (a) and New Taipei (f) sales, into ./data:
#' plvr_download("2024-01-01", "2024-12-31", dir = "data",
#'               types = "sale", counties = c("a", "f"))
#' }
#' @export
plvr_download <- function(start, end, dir = ".",
                          types = c("sale", "presale", "rent"),
                          counties = NULL, overwrite = FALSE,
                          timeout = 600, quiet = FALSE) {
  types <- match.arg(types, names(.plvr_types), several.ok = TRUE)
  if (!is.null(counties)) {
    counties <- tolower(as.character(counties))
    bad <- setdiff(counties, names(plvr_county_map()))
    if (length(bad)) stop("Unknown county code(s): ", paste(bad, collapse = ", "))
  }
  seasons <- seasons_in_range(start, end)

  for (ti in types) {
    d <- file.path(dir, .plvr_types[[ti]]$dir)
    if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  }

  old_timeout <- getOption("timeout")
  options(timeout = max(timeout, old_timeout))
  on.exit(options(timeout = old_timeout), add = TRUE)

  msg <- function(...) if (!quiet) message(...)
  log <- list()

  for (season in seasons) {
    targets <- vapply(types, function(ti) {
      file.path(dir, .plvr_types[[ti]]$dir, paste0(season, ".parquet"))
    }, character(1))

    if (!overwrite && all(file.exists(targets))) {
      msg(sprintf("[%s] already present, skipping.", season))
      for (ti in types) log[[length(log) + 1L]] <-
        data.frame(season = season, type = ti, status = "skipped", rows = NA_integer_)
      next
    }

    zip_path <- tempfile(fileext = ".zip")
    ex_dir <- tempfile()
    dir.create(ex_dir)
    on.exit(unlink(c(zip_path, ex_dir), recursive = TRUE, force = TRUE), add = TRUE)

    msg(sprintf("[%s] downloading ...", season))
    ok <- tryCatch({
      utils::download.file(
        plvr_season_url(season), destfile = zip_path,
        mode = "wb", quiet = TRUE,
        headers = c("User-Agent" = "plvr-r (https://plvr.land.moi.gov.tw)")
      )
      file.exists(zip_path) && file.info(zip_path)$size > 0
    }, error = function(e) { msg("  download failed: ", conditionMessage(e)); FALSE })

    contents <- if (ok) tryCatch(utils::unzip(zip_path, list = TRUE),
                                 error = function(e) NULL) else NULL
    if (is.null(contents) || nrow(contents) == 0L) {
      msg(sprintf("  [%s] no data available (season not published yet?), skipping.", season))
      unlink(c(zip_path, ex_dir), recursive = TRUE, force = TRUE)
      for (ti in types) log[[length(log) + 1L]] <-
        data.frame(season = season, type = ti, status = "unavailable", rows = NA_integer_)
      next
    }

    utils::unzip(zip_path, exdir = ex_dir)
    unlink(zip_path, force = TRUE)  # delete raw zip immediately

    for (ti in types) {
      target <- file.path(dir, .plvr_types[[ti]]$dir, paste0(season, ".parquet"))
      if (!overwrite && file.exists(target)) next
      df <- .collect_dataset(ex_dir, .plvr_types[[ti]]$letter, season, counties)
      if (is.null(df) || nrow(df) == 0L) {
        msg(sprintf("  [%s] %s: no rows.", season, ti))
        log[[length(log) + 1L]] <-
          data.frame(season = season, type = ti, status = "empty", rows = 0L)
        next
      }
      arrow::write_parquet(df, target)
      msg(sprintf("  [%s] %s -> %s (%d rows)", season, ti, target, nrow(df)))
      log[[length(log) + 1L]] <-
        data.frame(season = season, type = ti, status = "written", rows = nrow(df))
    }

    unlink(ex_dir, recursive = TRUE, force = TRUE)  # delete extracted CSVs
  }

  invisible(do.call(rbind, log))
}
