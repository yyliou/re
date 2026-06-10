test_that("roc_to_date parses valid ROC dates", {
  expect_equal(roc_to_date("1130215"), as.Date("2024-02-15"))
  expect_equal(roc_to_date("0990101"), as.Date("2010-01-01"))
})

test_that("roc_to_date returns NA for unreasonable dates", {
  expect_true(is.na(roc_to_date("1131301")))  # month 13
  expect_true(is.na(roc_to_date("1130230")))  # Feb 30
  expect_true(is.na(roc_to_date("0")))        # too short
  expect_true(is.na(roc_to_date("1100600")))  # day 00
})

test_that("day_zero_to_one rescues year-month-only build dates", {
  expect_equal(roc_to_date("1080500", day_zero_to_one = TRUE),
               as.Date("2019-05-01"))
})

test_that("date_to_roc round-trips", {
  expect_equal(date_to_roc("2024-02-15"), "1130215")
})
