#!/usr/bin/env Rscript
# Command-line wrapper around plvr::plvr_download().
#
# Usage:
#   Rscript inst/scripts/plvr-download.R --start 2023-11-01 --end 2024-04-30
#   Rscript inst/scripts/plvr-download.R --start 2024-01-01 --end 2024-12-31 \
#       --types sale,rent --counties a,f --dir data
#
# Flags:
#   --start YYYY-MM-DD   (required)
#   --end   YYYY-MM-DD   (required)
#   --dir   PATH         output root (default: .)
#   --types LIST         comma-separated: sale,presale,rent (default: all)
#   --counties LIST      comma-separated county codes, e.g. a,f (default: all)
#   --overwrite          re-download even if outputs exist
#   --quiet              suppress progress

args <- commandArgs(trailingOnly = TRUE)

get_flag <- function(name, default = NULL) {
  hit <- which(args == paste0("--", name))
  if (length(hit) == 0L) return(default)
  if (hit[1L] == length(args)) return(default)
  args[hit[1L] + 1L]
}
has_flag <- function(name) any(args == paste0("--", name))
split_csv <- function(x) if (is.null(x)) NULL else trimws(strsplit(x, ",")[[1]])

start <- get_flag("start")
end   <- get_flag("end")
if (is.null(start) || is.null(end)) {
  stop("Both --start and --end (YYYY-MM-DD) are required.", call. = FALSE)
}

types <- split_csv(get_flag("types"))
if (is.null(types)) types <- c("sale", "presale", "rent")

# Load the package if installed, else source the R/ files directly.
if (requireNamespace("plvr", quietly = TRUE)) {
  library(plvr)
} else {
  here <- dirname(sub("^--file=", "",
                      commandArgs(trailingOnly = FALSE)[grep("^--file=", commandArgs(FALSE))]))
  rdir <- normalizePath(file.path(here, "..", "..", "R"), mustWork = FALSE)
  for (f in list.files(rdir, pattern = "\\.R$", full.names = TRUE)) source(f)
}

plvr_download(
  start = start, end = end,
  dir = get_flag("dir", "."),
  types = types,
  counties = split_csv(get_flag("counties")),
  overwrite = has_flag("overwrite"),
  quiet = has_flag("quiet")
)
