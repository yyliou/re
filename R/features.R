# ---- internal column accessors -------------------------------------------

.has_col <- function(df, name) name %in% names(df)

# First existing column name from a set of candidate names (schemas drift by
# year, e.g. "車位移轉總面積平方公尺" vs "車位移轉總面積(平方公尺)").
.first_col <- function(df, names) {
  hit <- names[names %in% colnames(df)]
  if (length(hit)) hit[1L] else NA_character_
}

# Character column or an all-NA vector of the right length.
.chr_col <- function(df, names) {
  nm <- .first_col(df, names)
  if (is.na(nm)) rep(NA_character_, nrow(df)) else trimws(as.character(df[[nm]]))
}

# Numeric column: strip thousands separators / units, then coerce.
.num_col <- function(df, names) {
  nm <- .first_col(df, names)
  if (is.na(nm)) return(rep(NA_real_, nrow(df)))
  raw <- as.character(df[[nm]])
  suppressWarnings(as.numeric(gsub("[^0-9.-]", "", raw)))
}

# "有"/"無" -> logical.
.yn_lgl <- function(x) {
  x <- as.character(x)
  ifelse(is.na(x) | !nzchar(x), NA,
         ifelse(grepl("有", x), TRUE, ifelse(grepl("無", x), FALSE, NA)))
}

# ---- Chinese numeral parsing ---------------------------------------------

.cn_num_one <- function(s) {
  if (is.na(s) || !nzchar(s)) return(NA_real_)
  if (grepl("^[0-9]+$", s)) return(as.numeric(s))
  dig <- c("零" = 0, "一" = 1, "二" = 2, "兩" = 2, "三" = 3,
           "四" = 4, "五" = 5, "六" = 6, "七" = 7, "八" = 8,
           "九" = 9)
  uni <- c("十" = 10, "百" = 100, "千" = 1000, "萬" = 10000)
  total <- 0; cur <- 0; got <- FALSE
  for (ch in strsplit(s, "")[[1]]) {
    if (ch %in% names(dig)) {
      cur <- dig[[ch]]; got <- TRUE
    } else if (ch %in% names(uni)) {
      u <- uni[[ch]]; if (cur == 0) cur <- 1
      total <- total + cur * u; cur <- 0; got <- TRUE
    }
  }
  if (!got) return(NA_real_)
  total + cur
}

# Parse a transfer-level string ("移轉層次"): first numeric level, basement
# negative, whole-building ("全") -> NA.
.parse_floor <- function(x) {
  x <- as.character(x)
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    s <- x[i]
    if (is.na(s) || !nzchar(s) || grepl("全", s)) next     # 全棟
    neg <- grepl("地下", s)                            # 地下 (basement)
    s2 <- sub("層.*$", "", s)                              # text before 層
    s2 <- gsub("地下|地上|第", "", s2)
    s2 <- gsub("[、,，及/].*$", "", s2)            # keep first token
    s2 <- gsub("\\s", "", s2)
    v <- .cn_num_one(s2)
    if (!is.na(v) && neg) v <- -v
    out[i] <- v
  }
  out
}

# Number of "層" tokens in a transfer-level string.
.count_floors <- function(x) {
  x <- as.character(x)
  vapply(seq_along(x), function(i) {
    s <- x[i]
    if (is.na(s) || !nzchar(s)) return(NA_integer_)
    m <- gregexpr("層", s)[[1]]
    as.integer(sum(m > 0))
  }, integer(1))
}

# Classify 交易標的 into 房地 / 房 / 地 / 車位 / 其他.
.classify_target <- function(x) {
  x <- as.character(x)
  ifelse(is.na(x) | !nzchar(x), NA_character_,
  ifelse(grepl("房地", x), "房地",          # 房地(土地+建物)...
  ifelse(grepl("建物", x), "房",                # 建物 -> 房
  ifelse(grepl("土地", x), "地",                # 土地 -> 地
  ifelse(grepl("車位", x), "車位", "其他")))))
}

#' Build analysis-ready features from raw MOI registration columns
#'
#' Parses the raw Traditional-Chinese columns into typed, English-named feature
#' columns (areas, layout, age, floors, balcony/elevator/parking flags, zoning,
#' transaction-target class, dates). Raw columns are kept; new columns are
#' appended. Source columns that are absent for a given dataset simply yield
#' \code{NA} columns, so the same call works for sale / presale / rent.
#'
#' @param df A data frame of raw rows (e.g. read from a Parquet file written by
#'   \code{\link{plvr_download}}).
#' @param type Dataset type: \code{"sale"}, \code{"presale"} or \code{"rent"}.
#'   \code{"auto"} (default) infers it from the columns present.
#' @return \code{df} with appended feature columns (see Details).
#' @details Key added columns: \code{trans_date}, \code{trans_year},
#'   \code{trans_month}, \code{price_total}, \code{price_unit}, \code{land_area},
#'   \code{building_area}, \code{main_building_area}, \code{aux_building_area},
#'   \code{balcony_area}, \code{parking_area}, \code{parking_price},
#'   \code{rooms}, \code{halls}, \code{baths}, \code{partitioned},
#'   \code{has_mgmt}, \code{elevator}, \code{has_balcony}, \code{has_parking},
#'   \code{floor}, \code{floor_count}, \code{total_floors}, \code{built_date},
#'   \code{age_years}, \code{building_type}, \code{main_use}, \code{material},
#'   \code{zoning}, \code{zoning_type}, \code{target_raw}, \code{target_class},
#'   \code{district}. Rent adds \code{rent_type} and \code{furnished}.
#' @export
plvr_add_features <- function(df, type = c("auto", "sale", "presale", "rent")) {
  type <- match.arg(type)
  if (type == "auto") type <- .detect_type(df)
  n <- nrow(df)

  # --- dates ---------------------------------------------------------------
  trans_raw <- .chr_col(df, c("交易年月日",       # 交易年月日
                              "租賃年月日"))      # 租賃年月日
  df$trans_date  <- roc_to_date(trans_raw)
  df$trans_year  <- as.integer(format(df$trans_date, "%Y"))
  df$trans_month <- as.integer(format(df$trans_date, "%m"))

  built_raw <- .chr_col(df, "建築完成年月")   # 建築完成年月
  df$built_date <- roc_to_date(built_raw, day_zero_to_one = TRUE)
  df$age_years  <- as.numeric(df$trans_date - df$built_date) / 365.25
  df$age_years[!is.na(df$age_years) & df$age_years < 0] <- NA_real_

  # --- prices --------------------------------------------------------------
  if (type == "rent") {
    df$price_total <- .num_col(df, c("總額元",            # 總額元
                                     "租賃總額元"))# 租賃總額元
  } else {
    df$price_total <- .num_col(df, "總價元")              # 總價元
  }
  df$price_unit  <- .num_col(df, "單價元平方公尺") # 單價元平方公尺
  df$parking_price <- .num_col(df, "車位總價元")  # 車位總價元

  # --- areas ---------------------------------------------------------------
  df$land_area          <- .num_col(df, "土地移轉總面積平方公尺")
  df$building_area      <- .num_col(df, "建物移轉總面積平方公尺")
  df$main_building_area <- .num_col(df, "主建物面積")
  df$aux_building_area  <- .num_col(df, "附屬建物面積")
  df$balcony_area       <- .num_col(df, "陽台面積")
  df$parking_area       <- .num_col(df, c("車位移轉總面積平方公尺",
                                          "車位移轉總面積(平方公尺)"))

  # --- layout (房/廳/衛/隔間) ---------------------------------------------
  df$rooms <- .num_col(df, "建物現況格局-房")
  df$halls <- .num_col(df, "建物現況格局-廳")
  df$baths <- .num_col(df, "建物現況格局-衛")
  df$partitioned <- .yn_lgl(.chr_col(df, "建物現況格局-隔間"))

  # --- floors --------------------------------------------------------------
  floor_raw <- .chr_col(df, "移轉層次")               # 移轉層次
  df$floor        <- .parse_floor(floor_raw)
  df$floor_count  <- .count_floors(floor_raw)
  df$total_floors <- vapply(.chr_col(df, "總樓層數"), # 總樓層數
                            .cn_num_one, numeric(1), USE.NAMES = FALSE)

  # --- amenities -----------------------------------------------------------
  df$elevator   <- .yn_lgl(.chr_col(df, "電梯"))             # 電梯
  df$has_mgmt   <- .yn_lgl(.chr_col(df, "有無管理組織")) # 有無管理組織
  df$has_balcony <- ifelse(is.na(df$balcony_area), NA, df$balcony_area > 0)
  park_cat <- .chr_col(df, "車位類別")               # 車位類別
  df$has_parking <- ifelse(is.na(park_cat), NA,
                           nzchar(park_cat) & !grepl("^無$", park_cat))

  # --- categorical / zoning ------------------------------------------------
  df$building_type <- .chr_col(df, "建物型態")       # 建物型態
  df$main_use      <- .chr_col(df, "主要用途")       # 主要用途
  df$material      <- .chr_col(df, "主要建材")       # 主要建材
  df$district      <- .chr_col(df, "鄉鎮市區")       # 鄉鎮市區

  urban    <- .chr_col(df, "都市土地使用分區")           # 都市土地使用分區
  nonurban <- .chr_col(df, c("非都市土地使用分區",   # 非都市土地使用分區
                             "非都市土地使用編定"))  # 非都市土地使用編定
  has_u  <- !is.na(urban)    & nzchar(urban)
  has_nu <- !is.na(nonurban) & nzchar(nonurban)
  df$zoning      <- ifelse(has_u, urban, ifelse(has_nu, nonurban, NA_character_))
  df$zoning_type <- ifelse(has_u, "都市", ifelse(has_nu, "非都市", NA_character_))

  # --- transaction target --------------------------------------------------
  df$target_raw   <- .chr_col(df, "交易標的")        # 交易標的
  df$target_class <- .classify_target(df$target_raw)

  # --- rent-specific -------------------------------------------------------
  if (type == "rent") {
    df$rent_type  <- .chr_col(df, "出租型態")        # 出租型態
    df$furnished  <- .yn_lgl(.chr_col(df, "有無附傢俱")) # 有無附傢俱
  }

  df
}

# Guess dataset type from the columns present.
.detect_type <- function(df) {
  cn <- colnames(df)
  if (any(grepl("租賃", cn))) return("rent")        # 租賃*
  if ("建案名稱" %in% cn) return("presale")  # 建案名稱
  "sale"
}
