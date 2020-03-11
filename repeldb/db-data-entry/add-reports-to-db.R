# this is run one time to populate the DB, from here is it updated in the pipeline

source(here::here("repeldb", "scraper", "packages.R"))
source(here::here("repeldb", "scraper","functions.R"))

# DB connect
conn <- wahis_db_connect()

# Get data from AWS

# Script to sync data files
# See https://ecohealthalliance.github.io/eha-ma-handbook/11-cloud-computing-services.html
# For credentials setup

wahis:::pull_aws(bucket = "wahis-data", object = "data-processed.tar.xz", dir = here::here("repeldb/db-data-entry")) # pushed up in wahis/inst/process_annual_reports.r

# Add to db
files <- fs::dir_ls(path = here::here("repeldb/db-data-entry/data-processed/db"), regexp = "annual_reports")
arkdb::unark(files, db_con = conn, overwrite = TRUE,
             streamable_table = streamable_readr_csv(), lines = 50000L, col_types = cols(.default = col_character()))


files <- fs::dir_ls(path = here::here("repeldb/db-data-entry/data-processed/db"), regexp = "outbreak_reports")
arkdb::unark(files, db_con = conn, overwrite = TRUE,
             streamable_table = streamable_readr_csv(), lines = 50000L, col_types = cols(.default = col_character()))

dbDisconnect(conn)
