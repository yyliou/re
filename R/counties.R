#' MOI county codes
#'
#' Inside each season zip, every CSV is named \code{<code>_lvr_land_<type>.csv}
#' where \code{<code>} is a single lowercase letter identifying the county/city.
#' This returns the code -> name lookup (Traditional Chinese).
#'
#' @return A named character vector (names = single-letter codes).
#' @examples
#' plvr_county_map()[["a"]]  # "臺北市"
#' @export
plvr_county_map <- function() {
  c(
    a = "臺北市", # 臺北市
    b = "臺中市", # 臺中市
    c = "基隆市", # 基隆市
    d = "臺南市", # 臺南市
    e = "高雄市", # 高雄市
    f = "新北市", # 新北市
    g = "宜蘭縣", # 宜蘭縣
    h = "桃園市", # 桃園市
    i = "嘉義市", # 嘉義市
    j = "新竹縣", # 新竹縣
    k = "苗栗縣", # 苗栗縣
    m = "南投縣", # 南投縣
    n = "彰化縣", # 彰化縣
    o = "新竹市", # 新竹市
    p = "雲林縣", # 雲林縣
    q = "嘉義縣", # 嘉義縣
    t = "屏東縣", # 屏東縣
    u = "花蓮縣", # 花蓮縣
    v = "臺東縣", # 臺東縣
    w = "金門縣", # 金門縣
    x = "澎湖縣", # 澎湖縣
    z = "連江縣"  # 連江縣
  )
}
