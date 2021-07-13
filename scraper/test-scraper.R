#!/usr/bin/env Rscript

dir <- ifelse(basename(getwd())=="repel-infrastructure", "scraper/", "")
source(here::here(paste0(dir, "packages.R")))
source(here::here(paste0(dir, "tests/test-scrape-outbreak-reports.R")))
source(here::here(paste0(dir, "tests/test-scrape-six-month-reports.R")))

x <- try(test_scrape_outbreak_reports())
if (inherits(x, "try-error")) {
  stop("Outbreak scraper test failed")
} else {
  message("Outbreak scraper test passed")
}

x <- try(test_scrape_six_month_reports())
if (inherits(x, "try-error")) {
  stop("Six month scraper test failed")
} else {
  message("Six month scraper test passed")
}
