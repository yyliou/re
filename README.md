# plvr: Retrieval of Taiwan Real Estate Transaction Open Data 

## Overview <img src="man/figures/logo.svg" align="right" height="139" alt="plvr hex logo"  />
`plvr` is an R package for the programmatic acquisition of the actual
real-estate transaction records (實價登錄) published as open data by Taiwan's
Ministry of the Interior (MOI). It covers the three transaction categories
distributed by the ministry — completed sales (買賣), pre-sale building units
(預售屋), and rental agreements (租賃). Given a calendar date range, the package
resolves the range to the set of quarterly releases it spans, downloads each
release, retains only the requested categories and administrative regions, and
stores the result in a compact columnar format suitable for subsequent
analysis. The data source is the MOI supply system at
<https://plvr.land.moi.gov.tw/DownloadOpenData>.

## Data structure of the source

The ministry does not publish records on a daily basis. Instead, it releases
data in quarterly batches, each identified by a Republic of China (民國) year
and a quarter index — for example, `113S1` denotes the first quarter of ROC
year 113 (i.e. 2024). Accordingly, `plvr` interprets a user-supplied date range
by mapping it onto the quarterly releases that it intersects; a daily range is
therefore widened to whole quarters. Where day-level precision is required,
users should filter the retrieved records on the transaction-date field after
acquisition. Coverage begins at approximately the third quarter of ROC year 101
(2012), corresponding to the inception of the registration scheme.

Within each quarterly archive, files are named `<code>_lvr_land_<type>.csv`,
where `<code>` is a single-letter identifier of the administrative region (see
the table below) and `<type>` distinguishes the transaction category (`a` for
sales, `b` for pre-sale units, `c` for rentals).

## Design rationale: managing data volume

A central design consideration is that retrieving many years of records can
produce a substantial volume of data. `plvr` addresses this through four
complementary mechanisms:

1. **Quarter-wise retrieval.** Only the quarterly releases intersecting the
   requested range are downloaded, one quarter at a time, avoiding bulk
   transfer of the entire corpus.
2. **Immediate disposal of intermediate files.** After the requested CSV files
   are extracted from a quarterly archive, the archive and any unneeded
   regional files are deleted, so that peak disk consumption remains bounded.
3. **Columnar compression.** Each quarter and category is written to a single
   Parquet file. This columnar representation is typically five to ten times
   smaller than the equivalent CSV and supports efficient querying through
   `arrow`, `dplyr`, or DuckDB.
4. **Optional regional restriction.** The `counties` argument limits retrieval
   to specified administrative regions, further reducing both transfer and
   storage requirements.

In addition, retrieval is resumable: by default, quarters whose outputs already
exist are skipped, so that an interrupted or incremental run reprocesses only
the missing quarters. This behaviour may be overridden with `overwrite = TRUE`.

## Output organisation

Outputs are written relative to the `dir` argument (the current working
directory by default):

```
trans/   <season>.parquet   # 買賣  (sales)
presale/ <season>.parquet   # 預售屋 (pre-sale units)
rent/    <season>.parquet   # 租賃  (rentals)
```

Each record is augmented with three additional fields: `county_code` and
`county` (the regional identifier and its Traditional Chinese name) and
`season` (the quarterly release code). The original Traditional Chinese column
headers are preserved; the secondary English header row embedded in each source
file is removed automatically during ingestion.

## Installation

The package requires R together with the `arrow` and `readr` packages:

```r
install.packages(c("arrow", "readr"))

# Install plvr from the repository root:
# install.packages("remotes")
remotes::install_github("yyliou/re")
```

Alternatively, the source files may be loaded directly without installation:

```r
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
```

## Usage

```r
library(plvr)

# Retrieve all three categories for ROC 112 Q4 through 113 Q2:
plvr_download("2023-11-01", "2024-04-30")

# Retrieve only sales for Taipei (a) and New Taipei (f), writing to ./data:
plvr_download("2024-01-01", "2024-12-31",
              dir = "data", types = "sale", counties = c("a", "f"))

# Inspect the quarters spanned by a date range:
seasons_in_range("2023-11-01", "2024-04-30")
#> "112S4" "113S1" "113S2"

# Consult the region-code lookup table:
plvr_county_map()
```

The package may also be invoked from the command line:

```bash
Rscript inst/scripts/plvr-download.R --start 2023-11-01 --end 2024-04-30

Rscript inst/scripts/plvr-download.R \
  --start 2024-01-01 --end 2024-12-31 \
  --types sale,rent --counties a,f --dir data
```

The recognised flags are `--start` and `--end` (both required), together with
the optional `--dir`, `--types` (`sale,presale,rent`), `--counties` (e.g.
`a,f`), `--overwrite`, and `--quiet`.

## Reading the downloaded data

The output Parquet files are read with the `arrow` package. A single quarterly
file is loaded directly into a tibble:

```r
library(arrow)
df <- read_parquet("trans/113S1.parquet")
```

When several quarters are to be analysed together, `open_dataset()` treats an
entire output directory as one logical table and defers reading until the data
are actually required, which conserves memory:

```r
library(arrow)
library(dplyr)

ds <- open_dataset("trans")        # scans every .parquet in the directory
ds |>
  filter(county == "臺北市") |>    # predicates are pushed down before reading
  collect()                        # materialise the result as a tibble
```

Because retrieval operates at quarterly granularity, day-level selection is
performed after acquisition by filtering on the transaction-date field, which is
stored as a Republic of China date string (e.g. `1130115`):

```r
ds |>
  filter(交易年月日 >= "1130101", 交易年月日 <= "1130331") |>
  collect()
```

Column names follow the original source headers and may be inspected with
`names(read_parquet("trans/113S1.parquet"))`; recall that each record also
carries the added `county_code`, `county`, and `season` fields. For larger
analyses requiring SQL, the dataset may be passed to DuckDB via
`arrow::to_duckdb()`.

## Cleaning and feature engineering

The retrieved Parquet files preserve the source columns verbatim, with every
field stored as text. The `plvr_clean()` function transforms a raw data frame
into an analysis-ready table through a composable `data.frame -> data.frame`
pipeline. Each stage is governed by an argument and may be enabled or disabled
independently; the stages execute in the following order.

1. **Feature engineering** (`add_features`). The raw Traditional Chinese columns
   are parsed into typed, English-named features: transaction and construction
   dates; total and unit prices; land, building, main-building, ancillary,
   balcony, and parking areas; layout counts (`rooms`, `halls`, `baths`);
   building age in years; transfer level and total storeys (Chinese numerals are
   converted, with basements rendered negative); the `elevator`, `has_balcony`,
   `has_parking`, `has_mgmt`, and `partitioned` indicators; land-use `zoning`;
   and the `target_class` classification of the transaction object into
   房地 / 房 / 地 / 車位. Source columns absent from a given category yield `NA`
   columns, so the same call applies to sales, pre-sale units, and rentals.
2. **Removal of unreasonable values** (`drop_invalid`). Records with a
   non-positive or missing price, an unparseable transaction date (for instance
   a thirteenth month), or a zero building or land area inconsistent with the
   transaction object are discarded.
3. **Removal of non-arm's-length transactions** (`drop_abnormal`). Related-party,
   corporate, foreclosure (法拍), and "death house" (凶宅) dealings are
   identified by matching the remark field (`備註`) against the keyword groups
   returned by `plvr_abnormal_keywords()`, which may be overridden or extended.
   The function `plvr_flag_abnormal()` exposes the per-record reason without
   deleting rows.
4. **Restriction by transaction object** (`target`). Retains only the requested
   classes among 房地, 房, 地, and 車位.
5. **Trimming of extreme values** (`trim_extreme`). The highest and lowest
   `trim_prob` (one percent by default) of unit price (單價) are removed within
   each season, so that the threshold adapts to seasonal price levels.

```r
library(plvr)
library(arrow)

df <- read_parquet("trans/113S1.parquet")

# Full cleaning: drop unreasonable and non-arm's-length records, keep only
# 房地 and 房, and trim the per-season 1% unit-price tails.
clean <- plvr_clean(
  df, type = "sale",
  target = c("房地", "房"),
  trim_extreme = TRUE
)

# Feature engineering only, leaving every record in place:
feat <- plvr_add_features(df, type = "sale")
```

Each stage reports the number of records removed unless `quiet = TRUE`. The
toggles default to a conventional academic configuration — feature engineering,
unreasonable-value removal, and non-arm's-length removal enabled; extreme-value
trimming and target restriction left to the caller — and any of them may be
adjusted through the corresponding argument.

## Administrative region codes

| Code | Region | Code | Region | Code | Region |
|------|--------|------|--------|------|--------|
| a | 臺北市 | b | 臺中市 | c | 基隆市 |
| d | 臺南市 | e | 高雄市 | f | 新北市 |
| g | 宜蘭縣 | h | 桃園市 | i | 嘉義市 |
| j | 新竹縣 | k | 苗栗縣 | m | 南投縣 |
| n | 彰化縣 | o | 新竹市 | p | 雲林縣 |
| q | 嘉義縣 | t | 屏東縣 | u | 花蓮縣 |
| v | 臺東縣 | w | 金門縣 | x | 澎湖縣 |
| z | 連江縣 |   |        |   |        |

## Notes and attribution

Downloading the most recent quarterly release constitutes acceptance of the
ministry's non-exclusive licensing terms; users should attribute the source
accordingly. Quarters that have not yet been published are skipped
automatically. Network access to the ministry's servers is required and may be
unavailable from sandboxed environments; retrieval should be performed in an
environment with direct internet access.

## License

MIT. Source data © Ministry of the Interior, Republic of China (Taiwan).
