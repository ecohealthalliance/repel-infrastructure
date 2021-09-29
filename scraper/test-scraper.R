#!/usr/bin/env Rscript

dir <- ifelse(basename(getwd())=="repel-infrastructure", "scraper", "")
source(here::here(dir, "packages.R"))
purrr::walk(list.files(here::here(dir, "R"), full.names = TRUE), source)
source(here::here(dir, "tests/test-scrape-outbreak-reports.R"))
source(here::here(dir, "tests/test-scrape-six-month-reports.R"))

x <- try(test_scrape_outbreak_reports(dir))
if (inherits(x, "try-error")) {
  stop("Outbreak scraper test failed with error:\n", x)
} else {
  message("Outbreak scraper test passed")
}

x <- try(test_scrape_six_month_reports())
if (inherits(x, "try-error")) {
  cat(x)
  stop("Six month scraper test failed:\n", x)
} else {
  message("Six month scraper test passed")
}
