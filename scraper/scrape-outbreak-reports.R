#!/usr/bin/env Rscript

dir <- ifelse(basename(getwd())=="repel-infrastructure", "scraper/", "")
source(here::here(paste0(dir, "packages.R")))
source(here::here(paste0(dir, "functions.R")))
library(repelpredict)

# Connect to database ----------------------------
message("Connect to database")
conn <- wahis_db_connect()

# Finding unfetched reports in database ----------------------------
message("Finding unfetched reports in database")

# Update db with latest outbreak reports list
reports <- scrape_outbreak_report_list()

if(dbExistsTable(conn, "outbreak_reports_ingest_status_log")){
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

# write_rds(report_resps, here::here("scraper", "scraper_files_for_testing/report_resps_outbreak.rds"))
# report_resps <- read_rds(here::here("scraper", "scraper_files_for_testing/report_resps_outbreak.rds"))

report_resps <- reduce(report_resps, c)

# Update ingest log -------------------------------------------------------
outbreak_reports_ingest_status_log <- map_dfr(report_resps, function(x){
  ingest_error <-  !is.null(x$ingest_status) && str_detect(x$ingest_status, "ingestion error") |
    !is.null(x$message) && str_detect(x$message, "Endpoint request timed out")
  tibble(report_info_id = x$report_info_id, ingest_error)
})

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

  outbreak_report_tables$outbreak_reports_diseases_unmatched <- outbreak_report_tables$outbreak_reports_diseases_unmatched %>% unique()

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

  message("Done updating outbreak reports")

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

  # Update model predictions with new data------------------------------------------------
  message("Updating cached model predictions")

  # get model from aws
  model_object <-  repelpredict::network_lme_model(
    network_model = aws.s3::s3readRDS(bucket = "repeldb/models", object = "lme_mod_network.rds"),
    network_scaling_values = aws.s3::s3readRDS(bucket = "repeldb/models", object = "network_scaling_values.rds")
  )

  aws_network_etag <- aws.s3::head_object(bucket = "repeldb/models", object = "lme_mod_network.rds") %>%
    attr(., "etag")

  # get full database
  repeldat <- repelpredict::repel_split(model_object, conn)

  # forecast combines augment and predict
  repel_forecast_out <- repel_forecast(model_object = model_object,
                                       conn = conn,
                                       newdata = repeldat,
                                       use_cache = FALSE)

  network_lme_augment_predict <- repel_forecast_out[[1]] %>%
    mutate(predicted_outbreak_probability = repel_forecast_out[[2]]) %>%
    mutate(db_network_etag = aws_network_etag)

  forecasted_predictions <- network_lme_augment_predict %>%
    distinct(country_iso3c, disease, month, predicted_outbreak_probability)

  # write_rds(network_lme_augment_predict, "tmp_forecasted_data.rds")
  # network_lme_augment_predict <- read_rds("tmp_forecasted_data.rds")
  dbWriteTable(conn, name = "network_lme_augment_predict", network_lme_augment_predict, overwrite = TRUE)

  ### cache augment with disaggregated country imports
  augmented_data_disagg <- repel_augment(model_object, conn, newdata = network_lme_augment_predict, sum_country_imports = FALSE)

  network_lme_augment_predict_by_origin <- augmented_data_disagg %>%
    drop_na(country_origin) %>%
    left_join(forecasted_predictions)

  dbWriteTable(conn, name = "network_lme_augment_predict_by_origin", network_lme_augment_predict_by_origin, overwrite = TRUE)

  ### cache model coefficients (not necessary every time there is new data, but doesn't hurt to override to ensure everything is current)
  lme_mod <- model_object$network_model

  randef <- lme4::ranef(lme_mod)
  randef_disease <- randef$disease %>%
    tibble::rownames_to_column(var = "disease") %>%
    as_tibble() %>%
    pivot_longer(-disease, names_to = "variable", values_to = "coef") %>%
    mutate(disease_clean = str_to_title(str_replace_all(disease, "_", " "))) %>%
    mutate(variable_clean = str_replace(variable, "_from_outbreaks", " from countries with existing outbreak"),
           variable_clean = str_replace(variable_clean, "fao_trade_", ""),
           variable_clean = str_replace(variable_clean, "_other", " (other)"),
           variable_clean = str_replace_all(variable_clean, "_", " "),
           variable_clean = str_remove(variable_clean, "continent"),
           variable_clean = str_replace(variable_clean, "shared borders from countries with existing outbreak", "shared borders with country with existing outbreak"))

  dbWriteTable(conn, name = "network_lme_coefficients", randef_disease, overwrite = TRUE)

  network_scaling_values <- model_object$network_scaling_values
  dbWriteTable(conn, name = "network_lme_scaling_values", network_scaling_values, overwrite = TRUE)


  ########
  #TODO try alternative which is just predicting on new subset of the data. use init/split to preformat, then predict

  outbreak_reports_events <- outbreak_report_tables[["outbreak_reports_events"]]
  outbreak_reports_events_for_predict <- outbreak_reports_events %>%
    mutate(month = lubridate::floor_date(report_date, unit = "month")) %>%
    distinct(country_iso3c, disease, month)

  # get predictions for the month, disease, country combos represented here
  forecasted_data <- repel_forecast(model_object = model_object,
                                    conn = conn,
                                    newdata = outbreak_reports_events_for_predict,
                                    use_cache = FALSE)

  # but missing how these events impact other country predictions?


}

# grant permissions
grant_table_permissions(conn)

dbDisconnect(conn)
