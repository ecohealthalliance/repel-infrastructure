#!/usr/bin/env Rscript

# A script get the list of available annual reports on WAHIS

source(here::here("repeldb", "scraper", "packages.R"))
source(here::here("repeldb", "scraper","functions.R"))

# Connect to database ----------------------------
message("Connect to database")
conn <- wahis_db_connect()

# Finding unfetched reports in database ----------------------------
message("Finding unfetched reports in database")

# weekly disease information
weekly_pg <-
  read_html("http://www.oie.int/wahis_2/public/wahid.php/Diseaseinformation/WI")

report_ids <- weekly_pg %>%
  html_nodes(xpath = "//a[contains(@href, 'Reviewreport')]") %>%
  html_attr("href") %>%
  stri_extract_last_regex("(?<=\\,)\\d{3,6}(?=\\))") %>%
  as.numeric() %>%
  sort(decreasing=TRUE)

current_pages <- dbReadTable(conn, "outbreak_reports_ingest_status_log") %>%
  mutate(id = as.integer(id)) %>%
  filter(in_database == TRUE)

reports_to_get <- tibble(id = setdiff(report_ids, current_pages)) %>%
  mutate(url =  paste0("https://www.oie.int/wahis_2/public/wahid.php/Reviewreport/Review?reportid=", id))

# Pulling reports ----------------------------
message("Pulling ", nrow(reports_to_get), " reports")

report_resps <- map_curl(
  urls = reports_to_get$url,
  .f = function(x) wahis::safe_ingest_outbreak(x$content),
  .host_con = 6L,
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
message("Updating database")

# tables
outbreak_report_tables <- wahis::transform_outbreak_reports(report_resps) %>%
  keep(~nrow(.) > 0) # This could probably be handled inside transform_annual_reports

iwalk(outbreak_report_tables,
      ~update_sql_table(conn,  .y, .x,
                        c("id"), fill_col_na = TRUE)
)

# ingest log
update_sql_table(conn, "outbreak_reports_ingest_status_log", ingest_status_log, c("id"))

dbDisconnect(conn)
message("Done updating outbreak reports.")

