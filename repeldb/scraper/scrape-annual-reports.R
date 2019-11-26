#!/usr/bin/env Rscript

# A script get the list of available annual reports on WAHIS


suppressMessages(suppressWarnings(suppressPackageStartupMessages({
  library(tidyverse)
  library(xml2)
  library(rvest)
  library(stringi)
  library(RPostgres)
  library(scrapetools)
  library(DBI)
  library(assertthat)
  library(wahis)
  library(glue)
})))


# Connect to database ----------------------------
message("Connect to database")

# This block is nice for allowsing both interactive and deployment use
if (interactive() && Sys.getenv("RSTUDIO") == "1") {
  base::readRenviron(".env")
  conn <- dbConnect(
    RPostgres::Postgres(),
    host = Sys.getenv("DEPLOYMENT_SERVER_URL"),
    port = Sys.getenv("POSTGRES_EXTERNAL_PORT"),
    user = Sys.getenv("POSTGRES_USER"),
    password = Sys.getenv("POSTGRES_PASSWORD"),
    dbname = Sys.getenv("POSTGRES_DB")
  )
  if (require("connections")) {
    connections::connection_view(conn, name = "repel", connection_code = "repel")
  }
} else {
  conn <- dbConnect(
    RPostgres::Postgres(),
    host = Sys.getenv("POSTGRES_HOST"),
    port = Sys.getenv("POSTGRES_PORT"),
    user = Sys.getenv("POSTGRES_USER"),
    password = Sys.getenv("POSTGRES_PASSWORD"),
    dbname = Sys.getenv("POSTGRES_DB")
  )
}

# Finding unfetched reports in database ----------------------------
message("Finding unfetched reports in database")

annual_reports_status <- tbl(conn, "annual_reports_status") %>%
  collect() %>%
  rename(report_year = year) %>%
  mutate(report_year = as.character(report_year))

ingest_log <- dbReadTable(conn, "annual_reports_ingest_status_log") %>% mutate(in_database = as.logical(in_database))

# annual_reports_metadata <- tbl(conn, "annual_reports_metadata")  %>%
#   distinct(country, report_year, report_months) %>%
#   collect() %>%
#   mutate(semester = recode(report_months, "Jan-Dec" = "semester0", "Jan-Jun" = "semester1", "Jul-Dec" = "semester2")) %>%
#   arrange(country, report_year, semester) %>%
#   select(-report_months) %>%
#   mutate(in_database = TRUE)

reports_to_get <- left_join(annual_reports_status, ingest_log, by = c("code", "report_year", "semester")) %>%
  mutate(in_database = coalesce(in_database, FALSE)) %>%
  filter(reported & !in_database) %>%
  mutate(semester = substr(semester, nchar(semester), nchar(semester))) %>%
  mutate(url = glue("https://www.oie.int/wahis_2/public/wahid.php/Reviewreport/semestrial/review?year={report_year}&semester={semester}&wild=0&country={code}&this_country_code={code}&detailed=1"),
       filename = glue("{country}_{report_year}_sem{semester}.html")) %>%
#  sample_n(10) %>% # selecting a random sample is useful for testing
  sample_frac(1)


# update annual report status with existing errors


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


# Updating databae  ----------------------------
message("Updating database")

# This replaces the rows in the database table with the ones in `updates`,
# matching on `id_fields`. The replacements are just appended on the end.
# There might be a better way using SQL UPDATE.  It returns the fields that were
# removed.
#TODO: This works with characters, but change so it works with other types
update_sql_table <- function(conn, table, updates, id_fields, verbose = TRUE) {
  sql_table <- tbl(conn, table)
  assert_that(identical(sort(colnames(sql_table)), sort(colnames(updates))))
  criteria <- distinct(select(updates, id_fields))
  selector <- paste0("(", do.call(paste, c(imap(criteria, ~paste0("", .y, " = \'", .x, "\'")), sep = " AND ")), ")", collapse = " OR ")
  removed <- DBI::dbGetQuery(conn, glue("DELETE FROM {table} WHERE {selector} RETURNING * ;"))
  dbAppendTable(conn, table, updates)
  if (verbose) message("Replacing ", nrow(removed), " old records with ", nrow(updates), " new records")
  return(removed)
}

reports_to_update <- reports_to_get %>%
  mutate(year = report_year) %>%
  select(colnames(tbl(conn, "annual_reports_status"))) %>%
  mutate(datetime_fetched = Sys.time(),
         fetched_status = map_chr(report_resps, "ingest_status"))

removed <- update_sql_table(conn, "annual_reports_status", reports_to_update, c("country", "code", "year", "semester"))

annual_report_tables <- wahis::transform_annual_reports(report_resps) %>%
  keep(~nrow(.) > 0) # This could probably be handled inside transform_annual_reports

iwalk(annual_report_tables,
      ~update_sql_table(conn,  .y, .x,
                        c("country", "report_year", "report_months"))
)

# update ingest log
update_sql_table(conn, "annual_reports_ingest_status_log", ingest_status_log, c("code", "report_year", "semester"))

