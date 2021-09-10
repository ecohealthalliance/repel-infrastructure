
preprocess_outbreak_events <- function(conn, events_new, process_all = FALSE){

  if(process_all){ # if processing all data

    # check for outbreak_reports_events in db - it may not be there if this is a fresh run of the scraper (ie populating db from scratch)
    if(dbExistsTable(conn, "outbreak_reports_events")){

      # combine all existing data with new data
      events_existing <- tbl(conn, "outbreak_reports_events") %>% collect()
      events <- bind_rows(events_existing, events_new) %>%
        filter(!is_aquatic)

    }else{
      # if outbreak_reports_events does not exist, then full dataset is events_new
      events <- events_new %>%
        filter(!is_aquatic)
    }

    # these are the country + disease combos (full dataset)
    events_lookup <- events %>%
      distinct(country_iso3c, disease)

  }else{ # if only processing new data

    # these are the new country + disease combos (new dataset only)
    events_lookup <- events_new %>%
      distinct(country_iso3c, disease)

    # pull existing dataset for each country + disease combo (all months)
    assert_that(dbExistsTable(conn, "outbreak_reports_events"), msg = "can only run preprocess_events on subset of the data if outbreak_reports_events already exists for lookup")
    events_existing <- tbl(conn, "outbreak_reports_events") %>%
      inner_join(events_lookup, copy = TRUE, by = c("country_iso3c", "disease")) %>%
      collect()

    # combine new data with relevant existing data
    events <- bind_rows(events_existing, events_new) %>%
      filter(!is_aquatic)
  }

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

  # if events is empty after removing unrecognized diseases, return null df
  if(nrow(events) == 0){
    events_processed <- NULL
    return(events_processed)
  }

  # process all data with latest events added
  events_processed <- repel_init(model_object = model_object,
                                 conn = conn,
                                 outbreak_reports_events = events,
                                 remove_single_country_disease = FALSE,
                                 remove_non_primary_taxa_disease = FALSE)

  if(!process_all){
    # only need relevant disease/country combos (not full expanded dataset)
    events_processed <- events_processed %>%
      right_join(events_lookup_clean, by = c("country_iso3c", "disease", "disease_name_uncleaned")) %>%
      select(-disease_in_single_country) # this field does not apply when only looking at a subset of the data
  }

  # identify and remove diseases that do not affect primary taxa
  events_disease_not_primary_taxa <- events_processed %>%
    filter(!disease_primary_taxa) %>%
    distinct(country_iso3c, disease_name_uncleaned, disease) %>%
    mutate(reason_for_exclusion = "disease not in primary taxa")

  events_unrecognized_disease <- bind_rows(events_unrecognized_disease, events_disease_not_primary_taxa)

  events_processed <- events_processed %>%
    filter(disease_primary_taxa) %>%
    select(-disease_primary_taxa)

  # if running on full dataset, identify and remove diseases that only occur in single country
  if(process_all){
    events_disease_in_single_country <- events_processed %>%
      filter(disease_in_single_country) %>%
      distinct(country_iso3c, disease_name_uncleaned, disease) %>%
      mutate(reason_for_exclusion = "disease in single country")

    events_unrecognized_disease <- bind_rows(events_unrecognized_disease, events_disease_in_single_country)

    events_processed <- events_processed %>%
      filter(!disease_in_single_country)

  }

  # also remove any other diseases that were not part of model fitting
  events_disease_not_modeled <- events_processed %>%
    filter(!disease %in% model_disease_names) %>%
    distinct(country_iso3c, disease_name_uncleaned, disease) %>%
    mutate(reason_for_exclusion = "disease not represented in model")

  events_unrecognized_disease <- bind_rows(events_unrecognized_disease, events_disease_not_modeled)

  events_processed <- events_processed %>%
    filter(disease %in% model_disease_names)

  # if running on subset of data, determine which disease + country combos have changed status
  if(!process_all){
    # get existing cache for relevant data
    network_lme_augment_predict <- tbl(conn, "network_lme_augment_predict") %>%
      inner_join(events_lookup_clean, copy = TRUE, by = c("country_iso3c", "disease")) %>%
      select(!!colnames(events_processed)) %>%
      collect()

    # compare new processed data with existing cache
    events_processed  <- setdiff(events_processed, network_lme_augment_predict)
    if(nrow(events_processed) == 0) events_processed <- NULL
  }

  return(events_processed)

}


