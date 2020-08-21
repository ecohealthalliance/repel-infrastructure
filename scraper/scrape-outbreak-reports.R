#!/usr/bin/env Rscript

source(here::here("scraper/packages.R"))
source(here::here("scraper/functions.R"))

# Connect to database ----------------------------
message("Connect to database")
conn <- wahis_db_connect()

# Finding unfetched reports in database ----------------------------
message("Finding unfetched reports in database")

# Update db with latest outbreak reports list
new_ids <- scrape_outbreak_report_list()

current_ids <- dbReadTable(conn, "outbreak_reports_ingest_status_log") %>%
  mutate(id = as.integer(id)) %>%
  filter(in_database == TRUE) %>%
  pull(id)

# new IDs only go back ~ 1 yr. Check that there is no gap in coverage. If there is, then add all integers between last report in DB and oldest report in new IDs.
if(min(new_ids) > max(current_ids)) {
  new_ids <- c(new_ids, seq(max(current_ids), min(new_ids)))
}

reports_to_get <- tibble(id = setdiff(new_ids, current_ids)) %>%
  mutate(url =  paste0("https://www.oie.int/wahis_2/public/wahid.php/Reviewreport/Review?reportid=", id))

# Pulling reports ----------------------------
message("Pulling ", nrow(reports_to_get), " reports")

report_resps <- map_curl(
  urls = reports_to_get$url,
  .f = function(x) wahis::safe_ingest_outbreak(x$content),
  .host_con = 6L,
  .delay = 2L,
  .timeout = nrow(reports_to_get)*120L,
  .handle_opts = list(low_speed_limit = 100, low_speed_time = 300),
  .retry = 3
)

report_resps <- map_if(report_resps, is.null,
                       function(x) list(ingest_status = "failed to fetch"))

# Update ingest log -------------------------------------------------------

ingest_status_log <- reports_to_get %>%
  select(id) %>%
  mutate(ingest_status = map_chr(report_resps, ~.x$ingest_status)) %>%
  mutate(in_database = ingest_status == "available") %>%
  mutate(ingest_error = ifelse(!in_database, ingest_status, NA)) %>%
  select(-ingest_status)

# Updating database  ----------------------------
if(any(unique(ingest_status_log$in_database))){ # check if there are any non-error responses
  message("Updating database")

  # tables
  outbreak_report_tables <- wahis::transform_outbreak_reports(report_resps)

  iwalk(outbreak_report_tables[c("outbreak_reports_events", "outbreak_reports_outbreaks", "outbreak_reports_outbreaks_summary",  "outbreak_reports_laboratories")],
        ~update_sql_table(conn,  .y, .x,
                          c("id"), fill_col_na = TRUE)
  )

  # unmatched diseases
  update_sql_table(conn, table = "outbreak_reports_diseases_unmatched",
                   updates = outbreak_report_tables[[ "outbreak_reports_diseases_unmatched"]],
                   id_fields = "disease")

  # ingest log
  update_sql_table(conn, table = "outbreak_reports_ingest_status_log",
                   updates = ingest_status_log,
                   id_fields = c("id"))

  message("Done updating outbreak reports.")

  # Schema lookup -----------------------------------------------------------
  field_check(conn, "outbreak_reports_")

  # Generate QA report ------------------------------------------------------
  assert_that(dbExistsTable(conn, "outbreak_reports_events"))
  assert_that(dbExistsTable(conn, "outbreak_reports_ingest_status_log"))
  assert_that(dbExistsTable(conn, "outbreak_reports_outbreaks"))
  assert_that(dbExistsTable(conn, "outbreak_reports_outbreaks_summary"))

  safely(rmarkdown::render, quiet = FALSE)(
    here::here("scraper/qa-outbreak-reports.Rmd"),
    output_file = paste0("outbreak-report-qa.html"),
    output_dir = "scraper/reports"
  )

}
dbDisconnect(conn)
