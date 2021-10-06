#!/usr/bin/env Rscript

dir <- ifelse(basename(getwd())=="repel-infrastructure", "scraper", "")
source(here::here(dir, "packages.R"))
purrr::walk(list.files(here::here(dir, "R"), full.names = TRUE), source)
library(repelpredict)

oie_diseases <- repelpredict:::get_oie_high_importance_diseases()

# Connect to database ----------------------------
message("Connect to database")
hl <- ifelse(dir == "scraper", "reservoir", "remote")
conn <- wahis_db_connect(host_location = hl)

# Finding unfetched reports in database ----------------------------
message("Finding unfetched six month reports in database")

# Update db with latest six month reports list
# Report API is available via paste0("https://wahis.oie.int/smr/pi/report/", report_id, "?format=preview").
# Formatted reports can be viewed as https://wahis.oie.int/#/report-smr/view?reportId=20038&period=SEM01&areaId=2&isAquatic=false.
reports <- scrape_six_month_report_list()

if(dbExistsTable(conn, "six_month_reports_ingest_status_log")){
  current_report_ids <- dbReadTable(conn, "six_month_reports_ingest_status_log") %>%
    mutate(report_id = as.integer(report_id)) %>%
    filter(!ingest_error) %>%
    pull(report_id)
}else{
  current_report_ids <- NA_integer_
}

new_ids <- setdiff(reports$report_id, current_report_ids)

reports_to_get <- reports %>%
  filter(report_id %in% new_ids) %>%
  mutate(url =  paste0("https://wahis.oie.int/smr/pi/report/", report_id, "?format=preview")) %>%
  slice(sample(nrow(.), size = 100))
# write_rds(reports_to_get, here::here("scraper", "scraper_files_for_testing/reports_to_get_six_month.rds"))
# reports_to_get <- read_rds(here::here("scraper", "scraper_files_for_testing/reports_to_get_six_month.rds"))

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
assertthat::are_equal(length(report_resps), nrow(reports_to_get))

# Update ingest log -------------------------------------------------------
six_month_reports_ingest_status_log <- imap_dfr(report_resps, function(x, y){
  ingest_error <-  !is.null(x$ingest_status) && str_detect(x$ingest_status, "ingestion error") |
    !is.null(x$message) && str_detect(x$message, "Endpoint request timed out")
  reports_to_get[which(names(report_resps) == y), ] %>% mutate(ingest_error = ingest_error)
})


if(any(!unique(six_month_reports_ingest_status_log$ingest_error))){ # check if there are any non-error responses

  # Transform reports  ----------------------------
  # tables
  six_month_report_tables <- split(report_resps, (1:length(report_resps)-1) %/% 1000) %>% # batching by 1000s (probably only necessary for initial run)
    map(., transform_six_month_reports)

  six_month_report_tables <- transpose(six_month_report_tables) %>%
    map(function(x) reduce(x, bind_rows))

  six_month_report_tables$six_month_reports_summary <- six_month_report_tables$six_month_reports_summary %>%
    mutate(id = paste0(country_iso3c, report_year, report_semester, disease, disease_population, taxa, serotype, control_measures)) %>%
    select(id, everything())
  assert_that(n_distinct(six_month_report_tables$six_month_reports_summary$id) == nrow(six_month_report_tables$six_month_reports_summary))

  six_month_report_tables$six_month_reports_detail <-  six_month_report_tables$six_month_reports_detail %>%
    mutate(id = paste0(country_iso3c, report_year, report_semester, disease, disease_population, taxa, serotype, adm, period)) %>%
    select(id, everything())
  #test = get_dupes(six_month_reports_detail, id)
  assert_that(n_distinct( six_month_report_tables$six_month_reports_summary$id) == nrow(six_month_report_tables$six_month_reports_summary))

  six_month_report_tables$six_month_reports_diseases_unmatched <- six_month_report_tables$six_month_reports_diseases_unmatched %>% unique()

  six_month_report_tables$six_month_reports_ingest_status_log <- six_month_reports_ingest_status_log

  # write_rds(six_month_report_tables, here::here("scraper", "scraper_files_for_testing/six_month_report_tables.rds"))
  # six_month_report_tables <- read_rds(here::here("scraper", "scraper_files_for_testing/six_month_report_tables.rds"))

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

  # for now, running only full dataset - expanded to all combinations of country, disease, taxa etc (this is not done within repel_init, which is why we cannot rely on directly reading data from conn)
  message("Preparing to predict on full dataset.")
  six_month_processed <- preprocess_six_month_reports(model_object, conn,
                                                      six_months_new = six_month_report_tables[["six_month_reports_summary"]],
                                                      process_all = TRUE)

  # write_rds(six_month_processed, here::here("scraper", "scraper_files_for_testing/six_month_processed.rds"))
  # six_month_processed <- read_rds(here::here("scraper", "scraper_files_for_testing/six_month_processed.rds"))

  # Predict on new data  ------------------------------------------------
  message(paste("Running augment and predict on", nrow(six_month_processed), "rows of data"))
  a = Sys.time()
  six_month_processed_augment <- repel_augment(model_object = model_object,
                                               conn = conn,
                                               subset = NULL,
                                               six_month_processed = six_month_processed) %>%
    arrange(country_iso3c, disease, taxa, report_year, report_semester)

  six_month_processed_predict <- repel_predict(model_object = model_object,
                                               newdata = six_month_processed_augment)

  b = Sys.time()
  message(paste0("Finished running augment and predict. ", round(as.numeric(difftime(time1 = b, time2 = a, units = "secs")), 3), " seconds elapsed"))

  message("Caching model predictions in the database")

  nowcast_boost_augment_predict <- six_month_processed_augment %>%
    mutate(predicted_cases = six_month_processed_predict) %>%
    mutate(db_disease_status_etag = aws_disease_status_etag,  db_cases_etag = aws_cases_etag) %>%
    mutate(id = paste0(country_iso3c, report_year, report_semester, disease, disease_population, taxa)) %>%
    select(id, everything())
  assert_that(n_distinct(nowcast_boost_augment_predict$id) == nrow(nowcast_boost_augment_predict))
  # for now, delete exisiting table before saving due to some column name issues (too long) and because we are only running predictions on full dataset
  dbRemoveTable(conn, "nowcast_boost_augment_predict")
  db_update(conn, table_name = "nowcast_boost_augment_predict", table_content = nowcast_boost_augment_predict, id_field = "id",  fill_col_na = TRUE)

  # summarize OIE diseases over taxa, population - for Shiny app
  nowcast_boost_predict_oie_diseases <- nowcast_boost_augment_predict  %>%
    select(report_year, report_semester, disease, country_iso3c, taxa,
           disease_status_unreported, actual_cases = cases, actual_status = disease_status,  predicted_cases) %>%
    filter(disease %in% oie_diseases) %>%
    collect() %>%
    mutate(predicted_status = predicted_cases > 0,
           actual_status = as.logical(actual_status),
           disease_status_unreported = as.logical(disease_status_unreported)) %>%
    group_by(country_iso3c, disease, report_year, report_semester) %>%
    summarize(predicted_status = any(predicted_status), actual_status = any2(actual_status),
              predicted_cases = sum(predicted_cases), actual_cases = sum2(actual_cases), disease_status_unreported = all(disease_status_unreported)) %>%
    ungroup()  %>%
    mutate(status_coalesced = case_when(
      actual_status == TRUE ~ "reported present",
      actual_status == FALSE ~ "reported absent",
      disease_status_unreported == TRUE & predicted_status == TRUE ~ "unreported, predicted present",
      disease_status_unreported == TRUE & predicted_status == FALSE ~ "unreported, predicted absent",
    )) %>%
    mutate(status_coalesced = factor(status_coalesced, levels = c("reported present", "unreported, predicted present",  "reported absent", "unreported, predicted absent"))) %>%
    mutate(id = paste0(country_iso3c, disease, report_year, report_semester)) %>%
    select(id, everything())
  assert_that(n_distinct(nowcast_boost_predict_oie_diseases$id) == nrow(nowcast_boost_predict_oie_diseases))
  # for now, delete exisiting table before saving due to some column name issues (too long) and because we are only running predictions on full dataset
  dbRemoveTable(conn, "nowcast_boost_predict_oie_diseases")
  db_update(conn, table_name = "nowcast_boost_predict_oie_diseases", table_content = nowcast_boost_predict_oie_diseases, id_field = "id",  fill_col_na = TRUE)

  # Update six month reports in database  ------------------------------------------------
  message("Updating six month reports in database")

  # update raw data
  six_month_reports_summary <- six_month_report_tables[["six_month_reports_summary"]]
  db_update(conn, table_name = "six_month_reports_summary", table_content = six_month_reports_summary, id_field = "id", fill_col_na = TRUE)

  six_month_reports_detail <- six_month_report_tables[["six_month_reports_detail"]]
  db_update(conn, table_name = "six_month_reports_detail", table_content = six_month_reports_detail, id_field = "id", fill_col_na = TRUE)

  six_month_reports_diseases_unmatched <- six_month_report_tables[["six_month_reports_diseases_unmatched"]] %>%
    distinct(disease)
  db_update(conn, table_name = "six_month_reports_diseases_unmatched", table_content = six_month_reports_diseases_unmatched, id_field = "disease")

  six_month_reports_ingest_status_log <- six_month_report_tables[["six_month_reports_ingest_status_log"]]
  db_update(conn, table_name = "six_month_reports_ingest_status_log", table_content = six_month_reports_ingest_status_log, id_field = "report_id",  fill_col_na = TRUE)

}

# grant permissions
grant_table_permissions(conn)

dbDisconnect(conn)
