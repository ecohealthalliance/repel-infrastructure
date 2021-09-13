#!/usr/bin/env Rscript

dir <- ifelse(basename(getwd())=="repel-infrastructure", "scraper/", "")
source(here::here(paste0(dir, "packages.R")))
purrr::walk(list.files(here::here(paste0(dir, "R")), full.names = TRUE), source)

# Connect to database ----------------------------
message("Connect to database")
conn <- wahis_db_connect(host_location = "remote")
#conn <- wahis_db_connect(host_location = "reservoir")

# Finding unfetched reports in database ----------------------------
message("Finding unfetched reports in database")

# Update db with latest outbreak reports list
reports <- scrape_six_month_report_list()

if(dbExistsTable(conn, "six_reports_ingest_status_log")){
  current_report_info_ids <- dbReadTable(conn, "outbreak_reports_ingest_status_log") %>%
    mutate(report_info_id = as.integer(report_info_id)) %>%
    filter(!ingest_error) %>%
    pull(report_info_id)
}else{
  current_report_info_ids <- NA_integer_
}

new_ids <- setdiff(reports$report_id, current_report_info_ids)

reports_to_get <- tibble(report_id = new_ids) %>%
  mutate(url =  paste0("https://wahis.oie.int/smr/pi/report/", report_id, "?format=preview"))

# Pulling reports ----------------------------
message("Pulling ", nrow(reports_to_get), " reports")
report_resps <- split(reports_to_get, (1:nrow(reports_to_get)-1) %/% 100) %>% # batching by 100s
  map(function(reports_to_get_split){
    map_curl(
      urls = reports_to_get_split$url,
      .f = function(x) wahis::safe_ingest(x),
      .host_con = 8L,
      .delay = 0.5,
      .handle_opts = list(low_speed_limit = 100, low_speed_time = 300), # bytes/sec
      .retry = 2,
      .handle_headers = list(`Accept-Language` = "en")
    )
  })
#2.5 hrs to run 10k reports 2021-07-08

# write_rds(report_resps, here::here("scraper", "scraper_files_for_testing/report_resps_six_month.rds"))
# report_resps <- read_rds(here::here("scraper", "scraper_files_for_testing/report_resps_six_month.rds"))

report_resps <- reduce(report_resps, c)

# Update ingest log -------------------------------------------------------
six_month_reports_ingest_status_log <- map_dfr(report_resps, function(x){
  ingest_error <-  !is.null(x$ingest_status) && str_detect(x$ingest_status, "ingestion error") |
    !is.null(x$message) && str_detect(x$message, "Endpoint request timed out")
  report_id <- x$reportId
  if(is.null(report_id)) report_id <- NA_integer_
  tibble(report_id, ingest_error)
})
#TODO need to be able to identify which reports caused timeout error

# Updating database  ----------------------------
if(any(!unique(six_month_reports_ingest_status_log$ingest_error))){ # check if there are any non-error responses
  message("Updating database")

  # tables
  six_month_report_tables <- split(report_resps, (1:length(report_resps)-1) %/% 1000) %>% # batching by 1000s (probably only necessary for initial run)
    map(., transform_six_month_reports)
  six_month_report_tables <- reduce(six_month_report_tables, c)

  # write_rds(six_month_report_tables, here::here("scraper", "scraper_files_for_testing/six_month_report_tables.rds"))
  # six_month_report_tables <- read_rds(here::here("scraper", "scraper_files_for_testing/six_month_report_tables.rds"))

  purrr:::walk(unique(names(six_month_report_tables)), function(y){

    x <- reduce(six_month_report_tables[names(six_month_report_tables)== y],
                bind_rows) %>%
      distinct()

    if(is.null(x)) return()

    idfield <- switch(y,
                      "six_month_reports_summary" =  "report_id",
                      "six_month_reports_detail" = "report_id",
                      "six_month_reports_diseases_unmatched" = "disease")

    if(!dbExistsTable(conn, y)){
      dbWriteTable(conn,  name = y, value = x)
    }else{
      update_sql_table(conn,  y, x,
                       c(idfield), fill_col_na = TRUE)
      Sys.sleep(1)

    }
  })

  message("Done updating six month reports.")

  # add prediction caching
  # fot this model, it's possible to predict on a subset of data
}

# grant permissions
grant_table_permissions(conn)

dbDisconnect(conn)

