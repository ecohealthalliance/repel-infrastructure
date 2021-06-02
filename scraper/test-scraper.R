#!/usr/bin/env Rscript

dir <- ifelse(basename(getwd())=="repel-infrastructure", "scraper/", "")
source(here::here(paste0(dir, "packages.R")))
source(here::here(paste0(dir, "tests/test-scrape-outbreak-reports.R")))
x <- try(test_scrape_outbreak_reports())
if (inherits(x, "try-error")) {
  stop("Scraper test failed")
} else {
  message("Scraper test passed")
}

