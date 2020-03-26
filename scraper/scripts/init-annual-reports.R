# This is to manually add downloaded annual reports to database
# First run scripts/pull-aws to download the files

source(here::here("packages.R"))
source(here::here("functions.R"))
library(fs)
library(future)
library(furrr)

# Connect to database ----------------------------
message("Connect to database")
conn <- wahis_db_connect()

#Remove old tables ----------------------------
db_tables <- db_list_tables(conn)
db_tables_wahis <- db_tables[grepl("annual_reports_", db_tables)]

walk(db_tables_wahis, ~dbRemoveTable(conn, .))

# List all annual report files to ingest ---------------------------------------------------------
filenames <- list.files(here::here("data-raw/wahis-raw-annual-reports"),
                        pattern = "*.html",
                        full.names = TRUE)

# Set up parallel plan  --------------------------------------------------------
plan(multiprocess) # This takes a bit to load on many cores as all the processes are starting

# Run ingest (~25 mins) ---------------------------------------------------------
message(paste(length(filenames), "files to process"))
library(tictoc)
tic()
wahis_annual <- future_map(filenames, safe_ingest_annual, .progress = TRUE)
toc()
write_rds(wahis_annual, here::here("data-intermediate/wahis_ingested_annual_reports.rds"))
