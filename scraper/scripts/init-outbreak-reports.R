# This is to manually add downloaded outbreak reports to database
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
db_tables_wahis <- db_tables[grepl("outbreak_reports_", db_tables)]

walk(db_tables_wahis, ~dbRemoveTable(conn, .))

# List all outbreak report files to ingest ---------------------------------------------------------
filenames <- list.files(here::here("data-raw/wahis-raw-outbreak-reports"),
                        pattern = "*.html",
                        full.names = TRUE)

# Set up parallel plan  --------------------------------------------------------
plan(multiprocess) # This takes a bit to load on many cores as all the processes are starting

# Run ingest (~5 mins) ---------------------------------------------------------
message(paste(length(filenames), "files to process"))
library(tictoc)
tic()
wahis_outbreak <- future_map(filenames, safe_ingest_outbreak, .progress = TRUE)
toc()
write_rds(wahis_outbreak, here::here("data-intermediate", "wahis_ingested_outbreak_reports.rds"))

# Transform files   ------------------------------------------------------
outbreak_reports <-  readr::read_rds(here::here("data-intermediate", "wahis_ingested_outbreak_reports.rds"))
assertthat::are_equal(length(filenames), length(outbreak_reports))
ingest_status_log <- tibble(id = gsub(".html", "", basename(filenames)),
                            ingest_status = map_chr(outbreak_reports, ~.x$ingest_status)) %>%
  mutate(in_database = ingest_status == "available") %>%
  mutate(ingest_error = ifelse(!in_database, ingest_status, NA)) %>%
  select(-ingest_status)

outbreak_reports_transformed <- transform_outbreak_reports(outbreak_reports)
write_rds(outbreak_reports_transformed, here::here("data-intermediate", "wahis_transformed_outbreak_reports.rds"))


# Save files to db --------------------------------------------------------
outbreak_reports_transformed <- read_rds(here::here("data-intermediate", "wahis_transformed_outbreak_reports.rds"))

iwalk(outbreak_reports_transformed,
      ~dbWriteTable(conn,  name = .y, value = .x)
)

dbWriteTable(conn,  name = "outbreak_reports_ingest_status_log", value = ingest_status_log)
