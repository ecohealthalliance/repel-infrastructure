#!/usr/bin/env Rscript

dir <- ifelse(basename(getwd())=="repel-infrastructure", "scraper/", "")
source(here::here(paste0(dir, "packages.R")))
purrr::walk(list.files(here::here(paste0(dir, "R")), full.names = TRUE), source)

# Connect to database ----------------------------
message("Connect to database")
conn <- wahis_db_connect()

# Scrape list of all annual reports ----------------------------
annual_reports_status <- scrape_annual_report_list()
# write_csv(annual_reports_status, here::here("scraper", "scraper_files_for_testing/annual_reports_status.csv"))
# annual_reports_status <- read_csv(here::here("scraper", "scraper_files_for_testing/annual_reports_status.csv"))

# Update db with latest annual reports list
if (dbExistsTable(conn, "annual_reports_status")) {
  dbRemoveTable(conn, "annual_reports_status")
}

dbWriteTable(conn, "annual_reports_status",  annual_reports_status)
message("Done collecting list of annual reports.")

# Finding unfetched reports in database ----------------------------
message("Finding unfetched reports in database")

# Get ingest status log produces by ingest function (if it exists)
if (dbExistsTable(conn, "annual_reports_ingest_status_log")) {
  ingest_log <- dbReadTable(conn, "annual_reports_ingest_status_log") %>%
    mutate(in_database = as.logical(in_database))
} else {
  ingest_log <- tibble("country_iso3c" = character(), "report_year" = numeric(), "report_semester" = numeric(), "in_database" = logical())
}

# Make list of reports not in DB
reports_to_get <- left_join(annual_reports_status, ingest_log, by = c("report", "country_iso3c", "report_year", "report_semester")) %>%
  mutate(in_database = coalesce(in_database, FALSE)) %>%
  filter(reported & !in_database) %>%
  mutate(url = glue("https://www.oie.int/wahis_2/public/wahid.php/Reviewreport/semestrial/review?year={report_year}&semester={report_semester}&wild=0&country={country_iso3c}&this_country_code={country_iso3c}&detailed=1")) %>%
  sample_frac(1)

# Pulling unfetched reports ----------------------------
message("Pulling ", nrow(reports_to_get), " reports")

report_resps <- map_curl(
  urls = reports_to_get$url,
  .f = function(x) wahis::safe_ingest_annual(x$content),
  .host_con = 6L,
  .delay = 2L,
  .timeout = nrow(reports_to_get)*120L,
  .handle_opts = list(low_speed_limit = 100, low_speed_time = 300),
  .retry = 3
)
# write_rds(report_resps, here::here("scraper", "scraper_files_for_testing/report_resps_annual.rds"))
# report_resps <- read_rds(here::here("scraper", "scraper_files_for_testing/report_resps_annual.rds"))

report_resps <- map_if(report_resps, is.null,
                       function(x) list(ingest_status = "failed to fetch"))


# Update ingest log -------------------------------------------------------

ingest_status_log <- reports_to_get %>%
  select(report, country_iso3c, report_year, report_semester) %>%
  mutate(ingest_status = map_chr(report_resps, ~.x$ingest_status)) %>%
  mutate(in_database = ingest_status == "available") %>%
  mutate(ingest_error = ifelse(!in_database, ingest_status, NA)) %>%
  select(-ingest_status)

# Updating database  ----------------------------
message("Updating database")

# All annual report tables
annual_report_tables <- wahis::transform_annual_reports(report_resps)

if(!is.null(annual_report_tables)){
  iwalk(annual_report_tables[names(annual_report_tables) != "annual_reports_diseases_unmatched"],
        function(x, y){
          update_sql_table(conn, y, x, c("report"))
          Sys.sleep(1)
  })
}

# unmatched diseases
if(!is.null(annual_report_tables[[ "annual_reports_diseases_unmatched"]])){
  update_sql_table(conn, table = "annual_reports_diseases_unmatched",
                   updates = annual_report_tables[[ "annual_reports_diseases_unmatched"]],
                   id_fields = "disease")
}

# ingest log
update_sql_table(conn, table = "annual_reports_ingest_status_log",
                 updates = ingest_status_log,
                 id_fields = c("report"))

# Schema lookup -----------------------------------------------------------
field_check(conn, "annual_reports_") #move up

# Generate QA report ------------------------------------------------------
assert_that(dbExistsTable(conn, "annual_reports_ingest_status_log"))
assert_that(dbExistsTable(conn, "annual_reports_status"))
assert_that(dbExistsTable(conn, "annual_reports_animal_diseases"))

safely(rmarkdown::render, quiet = FALSE)(
  here::here(paste0(dir, "qa-annual-reports.Rmd")),
  output_file = paste0("annual-report-qa.html"),
  output_dir = here::here(paste0(dir, "reports")),
)

dbDisconnect(conn)
