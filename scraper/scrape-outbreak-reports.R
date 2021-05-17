#!/usr/bin/env Rscript

dir <- ifelse(basename(getwd())=="repel-infrastructure", "scraper/", "")
source(here::here(paste0(dir, "packages.R")))
source(here::here(paste0(dir, "functions.R")))

# Connect to database ----------------------------
message("Connect to database")
conn <- wahis_db_connect()
# db_tables <- dbListTables(conn)

#TODO remove init script

# Finding unfetched reports in database ----------------------------
message("Finding unfetched reports in database")

# Update db with latest outbreak reports list
reports <- scrape_outbreak_report_list()

# if(dbExistsTable(conn, "outbreak_reports_ingest_status_log")){
current_report_info_ids <- dbReadTable(conn, "outbreak_reports_ingest_status_log") %>%
  mutate(report_info_id = as.integer(report_info_id)) %>%
  filter(!ingest_error) %>%
  pull(report_info_id)
}else{
  current_report_info_ids <- NA_integer_
}

new_ids <- setdiff(reports$report_info_id, current_report_info_ids)

reports_to_get <- tibble(report_info_id = new_ids) %>%
  mutate(url =  paste0("https://wahis.oie.int/pi/getReport/", report_info_id))

# Pulling reports ----------------------------
message("Pulling ", nrow(reports_to_get), " reports")

# need to add language here?
# report_resps <- split(reports_to_get, (1:nrow(reports_to_get)-1) %/% 100) %>% # batching by 100s
map(function(reports_to_get_split){
  map_curl(
    urls = reports_to_get_split$url,
    .f = function(x) wahis::safe_ingest_outbreak(x),
    .host_con = 8L, # can turn up
    .delay = 0.5,
    #.timeout = nrow(reports_to_get)*120L,
    .handle_opts = list(low_speed_limit = 100, low_speed_time = 300), # bytes/sec
    .retry = 2
  )
})

# write_rds(report_resps, here::here("scraper", "scraper_files_for_testing/report_resps_outbreak.rds"))
# report_resps <- read_rds(here::here("scraper", "scraper_files_for_testing/report_resps_outbreak.rds"))

report_resps <- reduce(report_resps, c)

# Update ingest log -------------------------------------------------------
ingest_error <- map_lgl(report_resps, function(x){
  !is.null(x$ingest_status) && str_detect(x$ingest_status, "ingestion error") |
    !is.null(x$message) && str_detect(x$message, "Endpoint request timed out")
})

outbreak_reports_ingest_status_log <- reports_to_get %>%
  select(report_info_id) %>%
  mutate(ingest_error = ingest_error)

# write_rds(outbreak_reports_ingest_status_log, here::here("scraper", "scraper_files_for_testing/outbreak_reports_ingest_status_log.rds"))
# outbreak_reports_ingest_status_log <-read_rds(here::here("scraper", "scraper_files_for_testing/outbreak_reports_ingest_status_log.rds"))

# Updating database  ----------------------------
if(any(!unique(outbreak_reports_ingest_status_log$ingest_error))){ # check if there are any non-error responses
  message("Updating database")

  # tables
  outbreak_report_tables <- split(report_resps, (1:length(report_resps)-1) %/% 1000) %>% # batching by 1000s (probably only necessary for initial run)
    map(., transform_outbreak_reports, reports)

  # write_rds(outbreak_report_tables, here::here("scraper", "scraper_files_for_testing/outbreak_report_tables.rds"))
  # outbreak_report_tables <- read_rds(here::here("scraper", "scraper_files_for_testing/outbreak_report_tables.rds"))

  outbreak_report_tables <- transpose(outbreak_report_tables) %>%
    map(function(x) reduce(x, bind_rows))

  outbreak_report_tables$outbreak_reports_diseases_unmatched <- distinct(outbreak_report_tables$outbreak_reports_diseases_unmatched)

  outbreak_report_tables$outbreak_reports_ingest_status_log <- outbreak_reports_ingest_status_log

  if(!is.null(outbreak_report_tables)){
    iwalk(outbreak_report_tables[c("outbreak_reports_events", # report_id
                                   "outbreak_reports_outbreaks", # report_id
                                   "outbreak_reports_diseases_unmatched", # disease
                                   "outbreak_reports_ingest_status_log")], # report_info_id
          function(x, y){
            idfield <- switch(y,
                              "outbreak_reports_events" =  "report_id",
                              "outbreak_reports_outbreaks" = "report_id",
                              "outbreak_reports_diseases_unmatched" = "disease",
                              "outbreak_reports_ingest_status_log" = "report_info_id")
            if(is.null(x)) return()
            if(!dbExistsTable(conn, y)){
              dbWriteTable(conn,  name = y, value = x)
            }else{
              update_sql_table(conn,  y, x,
                               c(idfield), fill_col_na = TRUE)
              Sys.sleep(1)
            }
          })
  }

  message("Done updating outbreak reports.")

  # Schema lookup -----------------------------------------------------------
  # field_check(conn, "outbreak_reports_")

  # Generate QA report ------------------------------------------------------
  assert_that(dbExistsTable(conn, "outbreak_reports_events"))
  assert_that(dbExistsTable(conn, "outbreak_reports_ingest_status_log"))
  assert_that(dbExistsTable(conn, "outbreak_reports_outbreaks"))

  # safely(rmarkdown::render, quiet = FALSE)(
  #   here::here(paste0(dir, "qa-outbreak-reports.Rmd")),
  #   output_file = paste0("outbreak-report-qa.html"),
  #   output_dir = here::here(paste0(dir, "reports"))
  # )

}
dbDisconnect(conn)
