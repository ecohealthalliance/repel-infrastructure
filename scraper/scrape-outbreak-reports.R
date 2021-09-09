#!/usr/bin/env Rscript

dir <- ifelse(basename(getwd())=="repel-infrastructure", "scraper/", "")
source(here::here(paste0(dir, "packages.R")))
source(here::here(paste0(dir, "functions.R")))
library(repelpredict)

# Connect to database ----------------------------
message("Connect to database")
hl <- ifelse(dir == "scraper/", "reservoir", "remote")
conn <- wahis_db_connect(host_location = hl)

# Finding unfetched reports in database ----------------------------
message("Finding unfetched reports in database")

# Update db with latest outbreak reports list
reports <- scrape_outbreak_report_list()

# report_info_id is the id that is inserted into the API url
# this field is renamed to url_report_id in outbreak_reports_events

if(dbExistsTable(conn, "outbreak_reports_ingest_status_log")){
  current_report_info_ids <- dbReadTable(conn, "outbreak_reports_ingest_status_log") %>%
    mutate(report_info_id = as.integer(report_info_id)) %>%
    filter(!ingest_error) %>%
    pull(report_info_id)
}else{
  current_report_info_ids <- NA_integer_
}

new_ids <- setdiff(reports$report_info_id, current_report_info_ids)

reports_to_get <- reports %>%
  filter(report_info_id %in% new_ids) %>%
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
assertthat::are_equal(length(report_resps), nrow(reports_to_get))

# Update ingest log -------------------------------------------------------
outbreak_reports_ingest_status_log <- imap_dfr(report_resps, function(x, y){
  ingest_error <-  !is.null(x$ingest_status) && str_detect(x$ingest_status, "ingestion error") |
    !is.null(x$message) && str_detect(x$message, "Endpoint request timed out")
  reports_to_get[which(names(report_resps) == y), ] %>% mutate(ingest_error = ingest_error)
})

# write_rds(outbreak_reports_ingest_status_log, here::here("scraper", "scraper_files_for_testing/outbreak_reports_ingest_status_log.rds"))
# outbreak_reports_ingest_status_log <-read_rds(here::here("scraper", "scraper_files_for_testing/outbreak_reports_ingest_status_log.rds"))

if(any(!unique(outbreak_reports_ingest_status_log$ingest_error))){ # check if there are any non-error responses

  # Transform reports  ----------------------------
  # tables
  outbreak_report_tables <- split(report_resps, (1:length(report_resps)-1) %/% 1000) %>% # batching by 1000s (probably only necessary for initial run)
    map(., transform_outbreak_reports, reports)

  # write_rds(outbreak_report_tables, here::here("scraper", "scraper_files_for_testing/outbreak_report_tables.rds"))
  # outbreak_report_tables <- read_rds(here::here("scraper", "scraper_files_for_testing/outbreak_report_tables.rds"))

  outbreak_report_tables <- transpose(outbreak_report_tables) %>%
    map(function(x) reduce(x, bind_rows))

  outbreak_report_tables$outbreak_reports_diseases_unmatched <- outbreak_report_tables$outbreak_reports_diseases_unmatched %>% unique()

  outbreak_report_tables$outbreak_reports_ingest_status_log <- outbreak_reports_ingest_status_log

  # Run repel_init on transformed data  ------------------------------------------------
  # get model from aws
  model_object <-  repelpredict::network_lme_model(
    network_model = aws.s3::s3readRDS(bucket = "repeldb/models", object = "lme_mod_network.rds"),
    network_scaling_values = aws.s3::s3readRDS(bucket = "repeldb/models", object = "network_scaling_values.rds")
  )
  # get model etag
  aws_network_etag <- aws.s3::head_object(bucket = "repeldb/models", object = "lme_mod_network.rds") %>%
    attr(., "etag")
  # pull etag of last used model in db cache
  if(dbExistsTable(conn, "network_lme_augment_predict")){
    db_network_etag <- tbl(conn, "network_lme_augment_predict") %>%
      pull(db_network_etag) %>% unique()
  }else{
    db_network_etag <- "dne"
  }

  # pull disease names from model for data check below
  lme_mod <- model_object$network_model
  randef <- lme4::ranef(lme_mod)
  model_disease_names <- randef$disease %>%
    tibble::rownames_to_column(var = "disease") %>%
    distinct(disease) %>%
    pull(disease)

  # if there is a new model, combine old with new data and run init, prior to predictions
  if(aws_network_etag != db_network_etag){
    message("New model detected. Preparing to predict on full dataset.")

    events_new <- outbreak_report_tables[["outbreak_reports_events"]]
    if(dbExistsTable(conn, "outbreak_reports_events")){ # table may not be there if this is a fresh run of the scraper (ie populating db from scratch)
      events_existing <- tbl(conn, "outbreak_reports_events") %>% collect()
      events <- bind_rows(events_existing, events_new) %>%
        filter(!is_aquatic)
    }else{
      events <- events_new %>%
        filter(!is_aquatic)
    }

    # these are the country + disease combos
    events_lookup <- events %>%
      distinct(country_iso3c, disease)

    # clean disease names in lookup
    events_lookup_clean <- repel_clean_disease_names(model_object, events_lookup)

    # pull out unrecognized diseases and remove from events
    #TODO use non-disease specific model coefficient for prediction (to be implemented in repelpredict).
    events_unrecognized_disease <- events_lookup_clean %>%
      filter(is.na(disease)) %>%
      mutate(reason_for_exclusion = "unrecognized disease")

    events <- events %>%
      filter(!disease %in% unique(events_unrecognized_disease$disease_name_uncleaned))

    if(nrow(events) == 0){
      events_processed <- NULL
    }else{
      # process all data with latest events added
      events_processed <- repel_init(model_object = model_object,
                                     conn = conn,
                                     outbreak_reports_events = events,
                                     remove_single_country_disease = FALSE,
                                     remove_non_primary_taxa_disease = FALSE)

      # identify and remove diseases that are in single country or do not affect primary taxa
      events_disease_in_single_country <- events_processed %>%
        filter(disease_in_single_country) %>%
        distinct(country_iso3c, disease_name_uncleaned, disease) %>%
        mutate(reason_for_exclusion = "disease in single country")

      events_disease_not_primary_taxa <- events_processed %>%
        filter(!disease_primary_taxa) %>%
        distinct(country_iso3c, disease_name_uncleaned, disease) %>%
        mutate(reason_for_exclusion = "disease not in primary taxa")

      events_unrecognized_disease <- bind_rows(events_unrecognized_disease, events_disease_in_single_country) %>%
        bind_rows(events_disease_not_primary_taxa)

      events_processed <- events_processed %>%
        filter(!disease_in_single_country, disease_primary_taxa)

      # also remove any other diseases that were not part of model fitting
      events_disease_not_modeled <- events_processed %>%
        filter(!disease %in% model_disease_names) %>%
        distinct(country_iso3c, disease_name_uncleaned, disease) %>%
        mutate(reason_for_exclusion = "disease not represented in model")

      events_unrecognized_disease <- bind_rows(events_unrecognized_disease, events_disease_not_modeled)

      events_processed <- events_processed %>%
        filter(disease %in% model_disease_names)

    } # events_processed not NULL
  }else{ # if there is not a new model, identify which reports are affected by new data. we only need to run predictions on new data

    message("Preparing to predict on new data only")
    events_new <- outbreak_report_tables[["outbreak_reports_events"]]
    # write_csv(events_new, "tmp_events_new2.csv")
    # events_new <- read_csv("tmp_events_new2.csv") %>% #TODO delete this, only for dev
    #   mutate(follow_up_count = as.character(follow_up_count))

    # these are the country + disease combos
    events_lookup <- events_new %>%
      distinct(country_iso3c, disease)

    # pull exisiting dataset for each country/disease combo
    events_existing <- tbl(conn, "outbreak_reports_events") %>%
      inner_join(events_lookup, copy = TRUE, by = c("country_iso3c", "disease")) %>%
      collect()

    events <- bind_rows(events_existing, events_new) %>%
      filter(!is_aquatic)

    # clean disease names in lookup
    events_lookup_clean <- repel_clean_disease_names(model_object, events_lookup)

    # pull out unrecognized diseases and remove from events
    #TODO use non-disease specific model coefficient for prediction (to be implemented in repelpredict).
    events_unrecognized_disease <- events_lookup_clean %>%
      filter(is.na(disease)) %>%
      mutate(reason_for_exclusion = "unrecognized disease")

    events_lookup_clean <- events_lookup_clean %>%
      drop_na(disease)

    events <- events %>%
      filter(!disease %in% unique(events_unrecognized_disease$disease_name_uncleaned))

    if(nrow(events) == 0){
      events_processed <- NULL
    }else{

      # process all data with latest events added
      events_processed <- repel_init(model_object = model_object,
                                     conn = conn,
                                     outbreak_reports_events = events,
                                     remove_single_country_disease = FALSE,
                                     remove_non_primary_taxa_disease = FALSE) %>%
        right_join(events_lookup_clean, by = c("country_iso3c", "disease", "disease_name_uncleaned")) %>% # only need relevant disease/country combos
        select(-disease_in_single_country) # does not apply when only a subset of the data

      # identify and remove diseases that do not affect primary taxa (cannot identify single country diseases here because we are only looking at subset of data)
      events_disease_not_primary_taxa <- events_processed %>%
        filter(!disease_primary_taxa) %>%
        distinct(country_iso3c, disease_name_uncleaned, disease) %>%
        mutate(reason_for_exclusion = "disease not in primary taxa")

      events_unrecognized_disease <- bind_rows(events_unrecognized_disease, events_disease_not_primary_taxa)

      events_processed <- events_processed %>%
        filter(disease_primary_taxa) %>%
        select(-disease_primary_taxa)

      # also remove any other diseases that were not part of model fitting
      events_disease_not_modeled <- events_processed %>%
        filter(!disease %in% model_disease_names) %>%
        distinct(country_iso3c, disease_name_uncleaned, disease) %>%
        mutate(reason_for_exclusion = "disease not represented in model")

      events_unrecognized_disease <- bind_rows(events_unrecognized_disease, events_disease_not_modeled)

      events_processed <- events_processed %>%
        filter(disease %in% model_disease_names)

      # get existing cache for relevant data
      network_lme_augment_predict <- tbl(conn, "network_lme_augment_predict") %>%
        inner_join(events_lookup_clean, copy = TRUE, by = c("country_iso3c", "disease")) %>%
        select(!!colnames(events_processed)) %>%
        collect()

      # compare new processed data with existing cache
      events_processed  <- setdiff(events_processed, network_lme_augment_predict)
      if(nrow(events_processed) == 0) events_processed <- NULL
    } # events_processed not NULL
  }

  # Update outbreak reports in database  ------------------------------------------------
  message("Updating outbreak reports in database") # this is necessary before running predictions because database lookups are needed in augment

  # update raw data
  outbreak_reports_events <- outbreak_report_tables[["outbreak_reports_events"]]
  db_update(conn, table_name = "outbreak_reports_events", table_content = outbreak_reports_events, id_field = "report_id", fill_col_na = TRUE)

  outbreak_reports_outbreaks <- outbreak_report_tables[["outbreak_reports_outbreaks"]]
  # write_rds(outbreak_reports_outbreaks, "tmp_outbreak_reports_outbreaks.rds") # for checking dupes
  outbreak_reports_outbreaks <- outbreak_reports_outbreaks %>%
    mutate(id = paste0(report_id, outbreak_location_id, species_name)) %>%
    select(id, everything()) %>%
    distinct()
  outbreak_reports_outbreaks_dup_ids <- outbreak_reports_outbreaks %>%
    janitor::get_dupes(id) %>%
    pull(id) %>%
    unique()
  # ^ some wonky stuff happening here
  outbreak_reports_outbreaks <- outbreak_reports_outbreaks %>% filter(!id %in% outbreak_reports_outbreaks_dup_ids)
  db_update(conn, table_name = "outbreak_reports_outbreaks", table_content = outbreak_reports_outbreaks, id_field = "id",  fill_col_na = TRUE)

  outbreak_reports_diseases_unmatched <- outbreak_report_tables[["outbreak_reports_diseases_unmatched"]] %>%
    distinct(disease)
  db_update(conn, table_name = "outbreak_reports_diseases_unmatched", table_content = outbreak_reports_diseases_unmatched, id_field = "disease")

  outbreak_reports_ingest_status_log <- outbreak_report_tables[["outbreak_reports_ingest_status_log"]]
  db_update(conn, table_name = "outbreak_reports_ingest_status_log", table_content = outbreak_reports_ingest_status_log, id_field = "report_info_id",  fill_col_na = TRUE)

  # Predict on new data  ------------------------------------------------
  # Get outbreak probabilities
  # augmented_events <- repel_augment(model_object = model_object,
  #                                   conn = conn,
  #                                   newdata = events_processed)
  #
  # predicted_events <- repel_predict(model_object = model_object,
  #                                   newdata = augmented_events)

  if(is.null(events_processed)){
    message("New reports do not affect predictions. Skipping augment/predict.")
  }else{
    message(paste("Running augment and predict on", nrow(events_processed), "rows of data"))
    a = Sys.time()
    repel_forecast_events <- repel_forecast(model_object = model_object,
                                            conn = conn,
                                            newdata = events_processed,
                                            use_cache = FALSE)
    b = Sys.time()
    message(paste0("Finished running augment and predict. ", round(as.numeric(difftime(time1 = b, time2 = a, units = "secs")), 3), " seconds elapsed"))

    network_lme_augment_predict_events <- repel_forecast_events[[1]] %>%
      mutate(predicted_outbreak_probability = repel_forecast_events[[2]]) %>%
      mutate(db_network_etag = aws_network_etag)
    #^ network_lme_augment_predict_events to be added to database below

    forcasted_predictions <- network_lme_augment_predict_events %>%
      distinct(country_iso3c, disease, month, predicted_outbreak_probability)

    # Get augment with disaggregated country imports
    message("Getting disaggregated country import augmented data")
    a = Sys.time()
    augmented_data_disagg_events <- repel_augment(model_object, conn, newdata = events_processed, sum_country_imports = FALSE)
    b = Sys.time()
    message(paste0("Finished getting disaggregated country import augmented data. ", round(as.numeric(difftime(time1 = b, time2 = a, units = "secs")), 3), " seconds elapsed"))

    network_lme_augment_predict_by_origin_events <-  augmented_data_disagg_events %>%
      left_join(forcasted_predictions, by = c("country_iso3c", "disease", "month"))
    #^ network_lme_augment_predict_by_origin_events to be added to database below

    # Get model coefficients (only necessary when there is a new model)
    lme_mod <- model_object$network_model

    randef <- lme4::ranef(lme_mod)
    network_lme_coefficients <- randef$disease %>%
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
    #^ network_lme_coefficients to be added to database below

    # Get scaling values (only necessary when there is a new model)
    network_lme_scaling_values <- model_object$network_scaling_values
    #^ network_lme_scaling_values to be added to database below

    # Update db
    message("Updating cached predictions in database")

    network_lme_augment_predict_events <- network_lme_augment_predict_events %>%
      mutate(id =  paste0(country_iso3c, disease, month)) %>%
      select(id, everything())
    db_update(conn, table_name = "network_lme_augment_predict", table_content = network_lme_augment_predict_events, id_field = "id")

    network_lme_augment_predict_by_origin_events <- network_lme_augment_predict_by_origin_events %>%
      mutate(id =  paste0(country_iso3c, country_origin, disease, month)) %>%
      select(id, everything())
    db_update(conn, table_name = "network_lme_augment_predict_by_origin", table_content = network_lme_augment_predict_by_origin_events, id_field = "id")

    # Update model results cache
    message("Updating cached model coefficients and scaling values")
    DBI::dbWriteTable(conn, name = "network_lme_coefficients", value = network_lme_coefficients, overwrite = TRUE)
    DBI::dbWriteTable(conn, name = "network_lme_scaling_values", value = network_lme_scaling_values, overwrite = TRUE)
  }
  message("Done updating database")

  # Schema lookup -----------------------------------------------------------
  # field_check(conn, "outbreak_reports_")

  # Generate QA report ------------------------------------------------------
  # assert_that(dbExistsTable(conn, "outbreak_reports_events"))
  # assert_that(dbExistsTable(conn, "outbreak_reports_ingest_status_log"))
  # assert_that(dbExistsTable(conn, "outbreak_reports_outbreaks"))

  # safely(rmarkdown::render, quiet = FALSE)(
  #   here::here(paste0(dir, "qa-outbreak-reports.Rmd")),
  #   output_file = paste0("outbreak-report-qa.html"),
  #   output_dir = here::here(paste0(dir, "reports"))
  # )

}

# grant permissions
grant_table_permissions(conn)

dbDisconnect(conn)
