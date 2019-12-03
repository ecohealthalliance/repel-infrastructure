#!/usr/bin/env Rscript

# A script get the list of available annual reports on WAHIS

source(here::here("repeldb", "packages.R"))
source(here::here("repeldb", "functions.R"))

# Connect to database ----------------------------
message("Connect to database")
conn <- wahis_db_connect()

# Finding unfetched reports in database ----------------------------
message("Finding unfetched reports in database")

annual_reports_status <- tbl(conn, "annual_reports_status") %>%
  collect() %>%
  rename(report_year = year) %>%
  mutate(report_year = as.character(report_year))

ingest_log <- dbReadTable(conn, "annual_reports_ingest_status_log") %>% mutate(in_database = as.logical(in_database))

reports_to_get <- left_join(annual_reports_status, ingest_log, by = c("code", "report_year", "semester")) %>%
  mutate(in_database = coalesce(in_database, FALSE)) %>%
  filter(reported & !in_database) %>%
  mutate(url = glue("https://www.oie.int/wahis_2/public/wahid.php/Reviewreport/semestrial/review?year={report_year}&semester={semester}&wild=0&country={code}&this_country_code={code}&detailed=1")) %>%
  sample_frac(1)

# Pulling reports ----------------------------
message("Pulling ", nrow(reports_to_get), " reports")

report_resps <- map_curl(
  urls = reports_to_get$url,
  .f = function(x) wahis::safe_ingest_annual(x$content),
  .host_con = 6L,
  .timeout = nrow(reports_to_get)*120L,
  .handle_opts = list(low_speed_limit = 100, low_speed_time = 300),
  .retry = 3
)

report_resps <- map_if(report_resps, is.null,
                          function(x) list(ingest_status = "failed to fetch"))


# Update ingest log -------------------------------------------------------

ingest_status_log <- reports_to_get %>%
  select(code, report_year, semester) %>%
  mutate(ingest_status = map_chr(report_resps, ~.x$ingest_status)) %>%
  mutate(in_database = ingest_status == "available") %>%
  mutate(ingest_error = ifelse(!in_database, ingest_status, NA)) %>%
  select(-ingest_status)


# Updating database  ----------------------------
message("Updating database")

# tables
annual_report_tables <- wahis::transform_annual_reports(report_resps) %>%
  keep(~nrow(.) > 0) # This could probably be handled inside transform_annual_reports

iwalk(annual_report_tables,
      ~update_sql_table(conn,  .y, .x,
                        c("country_iso3c", "report_year", "report_months"))
)

# ingest log
update_sql_table(conn, "annual_reports_ingest_status_log", ingest_status_log, c("code", "report_year", "semester"))

dbDisconnect(conn)
message("Done updating annual reports.")
