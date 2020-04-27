# This is to manually add downloaded annual reports to database
# First run scripts/pull-aws-downloaded-wahis to download the files

source(here::here("packages.R"))
source(here::here("functions.R"))
library(fs)
library(future)
library(furrr)

# Connect to database ----------------------------
conn <- wahis_db_connect()

#Remove old tables ----------------------------
db_tables <- db_list_tables(conn)
db_tables_annual <- db_tables[grepl("annual_reports_", db_tables)]

walk(db_tables_annual, ~dbRemoveTable(conn, .))

# List all annual report files to ingest ---------------------------------------------------------
filenames <- list.files(here::here("data-raw/wahis-raw-annual-reports"),
                        pattern = "*.html",
                        full.names = TRUE)

# Set up parallel plan  --------------------------------------------------------
plan(multiprocess) # This takes a bit to load on many cores as all the processes are starting

# Run ingest (~35 mins) ---------------------------------------------------------
message(paste(length(filenames), "files to process"))
library(tictoc)
tic()
wahis_annual <- future_map(filenames, safe_ingest_annual, .progress = TRUE)
toc()
write_rds(wahis_annual, here::here("data-intermediate", "wahis_ingested_annual_reports.rds"))

# Transform files   ------------------------------------------------------
annual_reports <-  readr::read_rds(here::here("data-intermediate", "wahis_ingested_annual_reports.rds"))

assertthat::are_equal(length(filenames), length(annual_reports))
ingest_status_log <- tibble(web_page = basename(filenames),
                            ingest_status = map_chr(annual_reports, ~.x$ingest_status)) %>%
  mutate(country_iso3c = substr(web_page, 1, 3),
         report_year = substr(web_page, 5, 8),
         report_semester = substr(web_page, 13, 13),
         report = paste(country_iso3c, report_year, report_semester, sep ="_")) %>%
  select(-web_page) %>%
  mutate(in_database = ingest_status == "available") %>%
  mutate(ingest_error = ifelse(!in_database, ingest_status, NA)) %>%
  select(report, country_iso3c, report_year, report_semester, in_database, ingest_error)

annual_reports_transformed <- wahis::transform_annual_reports(annual_reports)
write_rds(annual_reports_transformed, here::here("data-intermediate", "wahis_transformed_annual_reports.rds"))

# Save files to db --------------------------------------------------------
annual_reports_transformed <- read_rds(here::here("data-intermediate", "wahis_transformed_annual_reports.rds"))

iwalk(annual_reports_transformed,
      ~dbWriteTable(conn,  name = .y, value = .x)
)

dbWriteTable(conn,  name = "annual_reports_ingest_status_log", value = ingest_status_log)

field_check(conn, "annual_reports_") #

dbDisconnect(conn)

