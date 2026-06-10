test_that("Chinese numerals convert", {
  expect_equal(plvr:::.cn_num_one("十二"), 12)
  expect_equal(plvr:::.cn_num_one("二十"), 20)
  expect_equal(plvr:::.cn_num_one("一百零五"), 105)
  expect_true(is.na(plvr:::.cn_num_one("見其他登記事項")))
})

test_that("transfer floors parse, basements negative", {
  expect_equal(plvr:::.parse_floor("五層"), 5)
  expect_equal(plvr:::.parse_floor("地下一層"), -1)
  expect_true(is.na(plvr:::.parse_floor("全")))
  expect_equal(plvr:::.parse_floor("三層、四層"), 3)
})

test_that("transaction targets classify", {
  expect_equal(plvr:::.classify_target("房地(土地+建物)"), "房地")
  expect_equal(plvr:::.classify_target("房地(土地+建物)+車位"), "房地")
  expect_equal(plvr:::.classify_target("土地"), "地")
  expect_equal(plvr:::.classify_target("建物"), "房")
})

test_that("plvr_add_features builds typed columns", {
  df <- data.frame(
    交易標的 = "房地(土地+建物)",
    交易年月日 = "1130215",
    建築完成年月 = "1000101",
    建物移轉總面積平方公尺 = "100.5",
    土地移轉總面積平方公尺 = "30",
    總價元 = "10000000",
    單價元平方公尺 = "99502",
    `建物現況格局-房` = "3",
    `建物現況格局-廳` = "2",
    `建物現況格局-衛` = "2",
    移轉層次 = "五層",
    總樓層數 = "十二層",
    電梯 = "有",
    陽台面積 = "5",
    車位類別 = "坡道平面",
    check.names = FALSE
  )
  out <- plvr_add_features(df, type = "sale")
  expect_equal(out$trans_date, as.Date("2024-02-15"))
  expect_equal(out$building_area, 100.5)
  expect_equal(out$rooms, 3)
  expect_equal(out$floor, 5)
  expect_equal(out$total_floors, 12)
  expect_true(out$elevator)
  expect_true(out$has_balcony)
  expect_true(out$has_parking)
  expect_equal(out$target_class, "房地")
  expect_true(out$age_years > 13 && out$age_years < 14)
})
