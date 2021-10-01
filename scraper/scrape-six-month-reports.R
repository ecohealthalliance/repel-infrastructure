#!/usr/bin/env Rscript

#TODO
# fix ingest log lookup
# get IDs for viewing the reports on oie website
# include more info in ingest status log
# make sure checks for duplicate reports are sound

dir <- ifelse(basename(getwd())=="repel-infrastructure", "scraper", "")
source(here::here(dir, "packages.R"))
purrr::walk(list.files(here::here(dir, "R"), full.names = TRUE), source)
library(repelpredict)

# Connect to database ----------------------------
message("Connect to database")
hl <- ifelse(dir == "scraper", "reservoir", "remote")
conn <- wahis_db_connect(host_location = hl)

# Finding unfetched reports in database ----------------------------
message("Finding unfetched six month reports in database")

# Update db with latest outbreak reports list
reports <- scrape_six_month_report_list()

# if(dbExistsTable(conn, "six_reports_ingest_status_log")){
#   current_report_info_ids <- dbReadTable(conn, "outbreak_reports_ingest_status_log") %>%
#     mutate(report_info_id = as.integer(report_info_id)) %>%
#     filter(!ingest_error) %>%
#     pull(report_info_id)
# }else{
current_report_info_ids <- NA_integer_
# }

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

write_rds(report_resps, here::here("scraper", "scraper_files_for_testing/report_resps_six_month.rds"))
#report_resps <- read_rds(here::here("scraper", "scraper_files_for_testing/report_resps_six_month.rds"))

report_resps <- reduce(report_resps, c)
assertthat::are_equal(length(report_resps), nrow(reports_to_get))

# Update ingest log -------------------------------------------------------
six_month_reports_ingest_status_log <- map_dfr(report_resps, function(x){
  ingest_error <-  !is.null(x$ingest_status) && str_detect(x$ingest_status, "ingestion error") |
    !is.null(x$message) && str_detect(x$message, "Endpoint request timed out")
  report_id <- x$reportId
  if(is.null(report_id)) report_id <- NA_integer_
  tibble(report_id, ingest_error)
})
#TODO need to be able to identify which reports caused timeout error

if(any(!unique(six_month_reports_ingest_status_log$ingest_error))){ # check if there are any non-error responses

  # Transform reports  ----------------------------
  # tables
  six_month_report_tables <- split(report_resps, (1:length(report_resps)-1) %/% 1000) %>% # batching by 1000s (probably only necessary for initial run)
    map(., transform_six_month_reports)

  six_month_report_tables <- transpose(six_month_report_tables) %>%
    map(function(x) reduce(x, bind_rows))

  six_month_report_tables$six_month_reports_diseases_unmatched <- six_month_report_tables$six_month_reports_diseases_unmatched %>% unique()

  six_month_report_tables$six_month_reports_ingest_status_log <- six_month_reports_ingest_status_log

  #write_rds(six_month_report_tables, here::here("scraper", "scraper_files_for_testing/six_month_report_tables.rds"))
  #six_month_report_tables <- read_rds(here::here("scraper", "scraper_files_for_testing/six_month_report_tables.rds"))


  # Run repel_init on transformed data  ------------------------------------------------
  # get model from aws
  model_object <-  nowcast_boost_model(
    disease_status_model = aws.s3::s3readRDS(bucket = "repeldb/models", object = "boost_mod_disease_status.rds"),
    cases_model = aws.s3::s3readRDS(bucket = "repeldb/models", object = "boost_mod_cases.rds")
  )

  # get model etags
  aws_disease_status_etag <- aws.s3::head_object(bucket = "repeldb/models", object = "boost_mod_disease_status.rds") %>%
    attr(., "etag")
  aws_cases_etag <- aws.s3::head_object(bucket = "repeldb/models", object = "boost_mod_cases.rds") %>%
    attr(., "etag")
  # pull etag of last used model in db cache
  if(dbExistsTable(conn, "nowcast_boost_augment_predict")){
    db_etag <- tbl(conn, "nowcast_boost_augment_predict") %>%
      distinct(db_disease_status_etag, db_cases_etag)
    db_disease_status_etag <- db_etag %>% pull(db_disease_status_etag)
    db_cases_etag <-  db_etag %>% pull(db_cases_etag)
  }else{
    db_disease_status_etag <- db_cases_etag <- "dne"
  }

  # if there is a new model, combine old with new data and run init, prior to predictions
  if(aws_disease_status_etag != db_disease_status_etag | aws_cases_etag != db_cases_etag){
    message("New model detected. Preparing to predict on full dataset.")

    # check for six_month_reports_summary in db - it may not be there if this is a fresh run of the scraper (ie populating db from scratch)
    if(dbExistsTable(conn, "six_month_reports_summary")){
      # combine all existing data with new data
      six_month_existing <- tbl(conn, "six_month_reports_summary") %>% collect()
      six_month <- bind_rows(six_month_existing, six_month_report_tables$six_month_reports_summary)
    }else{

      # if six_month_reports_summary does not exist, then full dataset is newly scraped data
      six_month <- six_month_report_tables$six_month_reports_summary
    }
    six_month_processed <- repel_init(model_object, conn, six_month_reports_summary = six_month)
  }else{ # if there is not a new model, we only need to run predictions on new data
    message("Preparing to predict on new data only")
    six_month_processed <- repel_init(model_object, conn,
                                      six_month_reports_summary = six_month_report_tables$six_month_reports_summary)
  }


  # Update six month reports in database  ------------------------------------------------
  message("Updating six month reports in database") # this is necessary before running predictions because database lookups are needed in augment

  # update raw data
  six_month_reports_summary <- six_month_report_tables[["six_month_reports_summary"]]
  six_month_reports_summary <- six_month_reports_summary %>%
    mutate(id = paste0(country_iso3c, report_year, report_semester, disease, disease_population, taxa, serotype, control_measures)) %>%
    select(id, everything())
  test = get_dupes(six_month_reports_summary, id)
  assert_that(n_distinct(six_month_reports_summary$id) == nrow(six_month_reports_summary))
  db_update(conn, table_name = "six_month_reports_summary", table_content = six_month_reports_summary, id_field = "id", fill_col_na = TRUE)

  six_month_reports_detail <- six_month_report_tables[["six_month_reports_detail"]]
  six_month_reports_detail <- six_month_reports_detail %>%
    mutate(id = paste0(country_iso3c, report_year, report_semester, disease, disease_population, taxa, serotype, adm, period)) %>%
    select(id, everything())
  assert_that(n_distinct(six_month_reports_detail$id) == nrow(six_month_reports_detail))
  db_update(conn, table_name = "six_month_reports_detail", table_content = six_month_reports_detail, id_field = "id", fill_col_na = TRUE)

  six_month_reports_diseases_unmatched <- six_month_report_tables[["six_month_reports_diseases_unmatched"]] %>%
    distinct(disease)
  db_update(conn, table_name = "six_month_reports_diseases_unmatched", table_content = six_month_reports_diseases_unmatched, id_field = "disease")

  six_month_reports_ingest_status_log <- six_month_report_tables[["six_month_reports_ingest_status_log"]] %>%
    drop_na(report_id) %>%
    distinct()
  db_update(conn, table_name = "six_month_reports_ingest_status_log", table_content = six_month_reports_ingest_status_log, id_field = "report_id",  fill_col_na = TRUE)

  # Predict on new data  ------------------------------------------------
  # augmented_events <- repel_augment(model_object = model_object,
  #                                   conn = conn,
  #                                   newdata = events_processed)
  #
  # predicted_events <- repel_predict(model_object = model_object,
  #                                   newdata = augmented_events)





}

