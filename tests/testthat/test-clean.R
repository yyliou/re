make_df <- function() {
  data.frame(
    交易標的 = c("房地(土地+建物)", "房地(土地+建物)", "房地(土地+建物)",
                 "房地(土地+建物)", "土地", "房地(土地+建物)"),
    交易年月日 = c("1130215", "1131301", "1130310", "1130311",
                   "1130312", "1130315"),
    建築完成年月 = c("1000101", "1000101", "1000101", "1000101",
                     "", "1000101"),
    建物移轉總面積平方公尺 = c("100", "100", "100", "100", "0", "100"),
    土地移轉總面積平方公尺 = c("30", "30", "30", "30", "50", "30"),
    總價元 = c("10000000", "10000000", "0", "10000000",
               "5000000", "999999999"),
    單價元平方公尺 = c("100000", "100000", "100000", "100000",
                       NA, "9999999"),
    備註 = c("", "", "", "親友間交易", "", ""),
    season = rep("113S1", 6),
    check.names = FALSE
  )
}

test_that("drop_invalid removes 0-price, bad date, zero-area", {
  out <- plvr_clean(make_df(), type = "sale",
                    drop_abnormal = FALSE, quiet = TRUE)
  # row2 bad date(月13), row3 price 0, row5 land-target w/ 0 building is fine
  # but row5 is 土地 target with land_area>0 -> kept; building 0 ok for 地
  expect_false(any(is.na(out$trans_date)))
  expect_true(all(out$price_total > 0))
})

test_that("drop_abnormal removes related-party deals", {
  out <- plvr_clean(make_df(), type = "sale",
                    drop_invalid = FALSE, quiet = TRUE)
  expect_equal(nrow(out), 5)  # the 親友 row removed
})

test_that("target filter keeps only requested classes", {
  out <- plvr_clean(make_df(), type = "sale", target = "地",
                    drop_invalid = FALSE, drop_abnormal = FALSE,
                    quiet = TRUE)
  expect_true(all(out$target_class == "地"))
})

test_that("flag_abnormal reports reasons", {
  df <- data.frame(備註 = c("法拍屋", "凶宅", "法人間移轉", "正常"),
                   check.names = FALSE)
  f <- plvr_flag_abnormal(df)
  expect_equal(f[1], "foreclosure")
  expect_equal(f[2], "death_house")
  expect_equal(f[3], "corporate")
  expect_true(is.na(f[4]))
})

test_that("trim_extreme drops per-season unit-price tails", {
  df <- data.frame(
    交易標的 = "房地(土地+建物)",
    交易年月日 = "1130215",
    建物移轉總面積平方公尺 = "100",
    總價元 = "10000000",
    單價元平方公尺 = as.character(1:100),
    season = "113S1",
    check.names = FALSE
  )
  out <- plvr_clean(df, type = "sale", drop_invalid = FALSE,
                    drop_abnormal = FALSE, trim_extreme = TRUE,
                    trim_prob = 0.01, quiet = TRUE)
  expect_equal(nrow(out), 98)  # 1 and 100 trimmed
})
