# this is run one time to populate the DB, from here is it updated in the pipeline

suppressMessages(suppressWarnings(suppressPackageStartupMessages({
  library(tidyverse)
  library(xml2)
  library(rvest)
  library(stringi)
  library(RPostgres)
  library(scrapetools)
  library(DBI)
  library(assertthat)
  library(arkdb)
})))

# DB connect
base::readRenviron(here::here("repeldb", ".env"))
conn <- dbConnect(
  RPostgres::Postgres(),
  host = Sys.getenv("DEPLOYMENT_SERVER_URL"),
  port = Sys.getenv("POSTGRES_EXTERNAL_PORT"),
  user = Sys.getenv("POSTGRES_USER"),
  password = Sys.getenv("POSTGRES_PASSWORD"),
  dbname = Sys.getenv("POSTGRES_DB")
)

# Get data from AWS

# Script to sync data files
# See https://ecohealthalliance.github.io/eha-ma-handbook/11-cloud-computing-services.html
# For credentials setup

wahis:::pull_aws(bucket = "wahis-data", object = "data-processed.tar.xz", dir = here::here("repeldb/db-data-entry")) # pushed up in wahis/inst/process_annual_reports.r

# Add to db
files <- fs::dir_ls(path = here::here("repeldb/db-data-entry/data-processed/db"), regexp = "annual_reports")
arkdb::unark(files, db_con = conn, overwrite = TRUE,
             streamable_table = streamable_readr_csv(), lines = 50000L, col_types = cols(.default = col_character()))


