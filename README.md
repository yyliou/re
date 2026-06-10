# plvr 

## 1. Overview <img src="man/figures/logo.svg" align="right" height="139" alt="plvr hex logo" />

`plvr` is an R package for the programmatic acquisition of Taiwan's actual
real-estate transaction records (實價登錄) published as open data by the Ministry
of the Interior (MOI). It covers the three transaction categories distributed by
the ministry — completed sales (買賣), pre-sale building units (預售屋), and
rental agreements (租賃). Given a calendar date range, the package resolves it to
the quarterly releases it spans, downloads each release, retains only the
requested categories and administrative regions, and writes the result as
compact Parquet files for subsequent analysis. Source:
<https://plvr.land.moi.gov.tw/DownloadOpenData>.

The ministry releases data in **quarterly batches** labelled by Republic-of-China
(民國) year and quarter (e.g. `113S1` = ROC 113 / 2024, Q1); coverage begins
around ROC 101 Q3 (2012). A daily range is therefore widened to whole quarters;
where day-level precision is required, filter the retrieved records on the
transaction-date field afterward.

To bound data volume the package downloads only the intersecting quarters one at
a time, deletes the raw zips after extraction, writes columnar Parquet (5–10×
smaller than CSV), and optionally restricts to selected regions. Retrieval is
resumable: existing outputs are skipped unless `overwrite = TRUE`.

```r
install.packages(c("arrow", "readr"))
# install.packages("remotes")
remotes::install_github("yyliou/re")
```

## 2. Functions

| Function | Purpose |
|---|---|
| `plvr_download()` | Main function: download a date range to one Parquet file per quarter per category. |
| `plvr_clean()` | Composable cleaning pipeline (features → drop invalid → drop abnormal → target filter → trim). |
| `plvr_add_features()` | Parse raw Chinese columns into typed, English-named features. |
| `plvr_flag_abnormal()` | Flag non-arm's-length transactions without deleting rows. |
| `plvr_abnormal_keywords()` | Default keyword groups used to flag abnormal transactions. |
| `seasons_in_range()` / `date_to_season()` | Map a date range / a date to ROC season code(s). |
| `plvr_season_url()` | Build the download URL for a season's CSV zip. |
| `plvr_county_map()` | Region code → name lookup. |
| `roc_to_date()` / `date_to_roc()` | Convert between ROC date strings (`"1130215"`) and `Date`. |

## 3. Arguments

**`plvr_download(start, end, dir, types, counties, overwrite, timeout, quiet)`**

| Argument | Description | Default |
|---|---|---|
| `start`, `end` | Date range (inclusive), `Date` or `"yyyy-mm-dd"`. | required |
| `dir` | Output root directory. | current dir |
| `types` | Datasets to fetch: any of `"sale"`, `"presale"`, `"rent"`. | all three |
| `counties` | Single-letter county codes to keep (see `plvr_county_map()`); `NULL` keeps all. | `NULL` |
| `overwrite` | If `FALSE`, skip seasons whose outputs already exist (resume-friendly). | `FALSE` |
| `timeout` | Per-file download timeout (seconds). | `600` |
| `quiet` | Suppress progress messages. | `FALSE` |

**`plvr_clean(df, type, add_features, drop_invalid, drop_abnormal, abnormal_keywords, target, trim_extreme, trim_prob, quiet)`**

| Argument | Description | Default |
|---|---|---|
| `df` | Raw rows (e.g. from a Parquet file). | required |
| `type` | `"auto"`, `"sale"`, `"presale"`, or `"rent"`. | `"auto"` |
| `add_features` | Run feature engineering (needed by later filters). | `TRUE` |
| `drop_invalid` | Remove unreasonable values (non-positive/missing price, unparseable date, inconsistent zero area). | `TRUE` |
| `drop_abnormal` | Remove non-arm's-length transactions (related-party, corporate, foreclosure, 凶宅). | `TRUE` |
| `abnormal_keywords` | Keyword groups for `drop_abnormal`. | `plvr_abnormal_keywords()` |
| `target` | Transaction objects to keep: any of `"房地"`, `"房"`, `"地"`, `"車位"`; `NULL` keeps all. | `NULL` |
| `trim_extreme` | Trim per-season unit-price (單價) tails. | `FALSE` |
| `trim_prob` | Tail probability for trimming. | `0.01` |
| `quiet` | Suppress per-step row-count messages. | `FALSE` |

`plvr_add_features(df, type = "auto")`; `roc_to_date(x, day_zero_to_one = FALSE)`.

## 4. Output codebook

`plvr_download()` writes Parquet files relative to `dir`:

```
trans/   <season>.parquet   # 買賣  (sales)
presale/ <season>.parquet   # 預售屋 (pre-sale units)
rent/    <season>.parquet   # 租賃  (rentals)
```

Each record preserves the **original Traditional-Chinese column headers** (the
secondary English header row in each source file is removed on ingestion), all
stored as text, plus three added fields:

| Column | Description |
|---|---|
| `county_code` | Single-letter regional identifier. |
| `county` | Region name (Traditional Chinese). |
| `season` | Quarterly release code (e.g. `"113S1"`). |

Transaction dates are ROC strings (e.g. `1130115`). `plvr_clean()` /
`plvr_add_features()` append typed, English-named columns, including
`trans_date`, `trans_year`, `trans_month`, `price_total`, `price_unit`,
`land_area`, `building_area`, `main_building_area`, `aux_building_area`,
`balcony_area`, `parking_area`, `parking_price`, `rooms`, `halls`, `baths`,
`age_years`, `floor`, `total_floors`, `elevator`, `has_balcony`, `has_parking`,
`has_mgmt`, `partitioned`, `zoning`, `target_class` (房地/房/地/車位), and
`district`. Rent adds `rent_type` and `furnished`. Source columns absent for a
category yield `NA`, so the same call applies to all three datasets.

## 5. Examples

```r
library(plvr)

# Retrieve all three categories for ROC 112 Q4 through 113 Q2:
plvr_download("2023-11-01", "2024-04-30")

# Only sales for Taipei (a) and New Taipei (f), writing to ./data:
plvr_download("2024-01-01", "2024-12-31",
              dir = "data", types = "sale", counties = c("a", "f"))

# Inspect the quarters a date range spans:
seasons_in_range("2023-11-01", "2024-04-30")   # "112S4" "113S1" "113S2"

# Read and clean one quarter:
library(arrow)
df    <- read_parquet("trans/113S1.parquet")
clean <- plvr_clean(df, type = "sale",
                    target = c("房地", "房"), trim_extreme = TRUE)

# Lazily query many quarters; predicates are pushed down before reading:
library(dplyr)
open_dataset("trans") |>
  filter(county == "臺北市",
         交易年月日 >= "1130101", 交易年月日 <= "1130331") |>
  collect()
```

A command-line wrapper is also provided:

```bash
Rscript inst/scripts/plvr-download.R --start 2024-01-01 --end 2024-12-31 \
  --types sale,rent --counties a,f --dir data
```

Recognised flags: `--start`, `--end` (required), `--dir`, `--types`,
`--counties`, `--overwrite`, `--quiet`.

## 6. Notes

- **Administrative region codes:**

  | Code | Region | Code | Region | Code | Region |
  |---|---|---|---|---|---|
  | a | 臺北市 | b | 臺中市 | c | 基隆市 |
  | d | 臺南市 | e | 高雄市 | f | 新北市 |
  | g | 宜蘭縣 | h | 桃園市 | i | 嘉義市 |
  | j | 新竹縣 | k | 苗栗縣 | m | 南投縣 |
  | n | 彰化縣 | o | 新竹市 | p | 雲林縣 |
  | q | 嘉義縣 | t | 屏東縣 | u | 花蓮縣 |
  | v | 臺東縣 | w | 金門縣 | x | 澎湖縣 |
  | z | 連江縣 | | | | |

- The `plvr_clean()` stages run in order and each can be toggled independently;
  the defaults reflect a conventional academic configuration (features +
  invalid + abnormal removal on, target/trim left to the caller).
- Quarters not yet published are skipped automatically.
- For SQL-scale analysis, pass the Arrow dataset to DuckDB via
  `arrow::to_duckdb()`.

## 7. Data source & citation

Data © Taiwan Ministry of the Interior (MOI), real-price registration open data,
<https://plvr.land.moi.gov.tw/DownloadOpenData>. Downloading a release
constitutes acceptance of the ministry's non-exclusive licensing terms; attribute
the so
