
# function to apply repelpredict::repel_init to new events outbreak data. option to process full dataset or a subset of data.
preprocess_six_month_reports <- function(model_object, conn, six_months_new, process_all = TRUE){

  if(process_all){ # if processing all data

    # check for six_month_reports_summary in db - it may not be there if this is a fresh run of the scraper (ie populating db from scratch)
    if(dbExistsTable(conn, "six_month_reports_summary")){
      # combine all existing data with new data
      six_months_existing <- tbl(conn, "six_month_reports_summary") %>% collect()
      assert_that(!all(six_months_new$id %in% six_months_existing$id))
      six_months <- bind_rows(six_months_existing, six_months_new) %>%
        filter(!is_aquatic)
    }else{
      # if six_month_reports_summary does not exist, then full dataset is events_new
      six_months <- six_months_new %>%
        filter(!is_aquatic)
    }

    # these are the country + disease combos (full dataset)
    six_months_lookup <- six_months %>%
      distinct(country_iso3c, report_year, report_semester, disease, disease_population)

  }else{ # if only processing new data

    # # these are the new country + disease combos (new dataset only)
    # events_lookup <- events_new %>%
    #   distinct(country_iso3c, disease)
    #
    # # pull existing dataset for each country + disease combo (all months)
    # assert_that(dbExistsTable(conn, "outbreak_reports_events"), msg = "can only run preprocess_events on subset of the data if outbreak_reports_events already exists for lookup")
    # events_existing <- tbl(conn, "outbreak_reports_events") %>%
    #   inner_join(events_lookup, copy = TRUE, by = c("country_iso3c", "disease")) %>%
    #   collect()
    #
    # # combine new data with relevant existing data
    # events <- bind_rows(events_existing, events_new) %>%
    #   filter(!is_aquatic)
  }

  # clean disease names in lookup
  six_month_lookup_clean <- repel_clean_disease_names(model_object, six_months_lookup)

  # pull out unrecognized diseases and remove from events
  #TODO use non-disease specific model coefficient for prediction (to be implemented in repelpredict).
  six_month_unrecognized_disease <-  six_month_lookup_clean %>%
    filter(is.na(disease)) %>%
    mutate(reason_for_exclusion = "unrecognized disease")

  six_month_lookup_clean <-  six_month_lookup_clean %>%
    drop_na(disease)

  six_months <- six_months %>%
    filter(!disease %in% unique(six_month_unrecognized_disease$disease_name_uncleaned))

  # if events is empty after removing unrecognized diseases, return null df
  if(nrow(six_months) == 0){
    six_months_processed <- NULL
    return(six_months_processed)
  }

  # if running on full dataset, expand taxa+disease combos to all countries and years (including those not reported)
  if(process_all){

    # expand taxa+disease combos to all countries and years (including those not reported)
    reported_years <- six_months %>%
      arrange(report_year, report_semester) %>%
      distinct(report_year, report_semester)

    last_sem <- reported_years %>% tail(1)
    if(last_sem$report_semester == 2){
      next_year <- tibble(report_year = rep(max(last_sem$report_year)+1, each = 2), report_semester = 1:2)
    }else{
      next_year <- tibble(report_year = c(max(last_sem$report_year), max(last_sem$report_year) + 1), report_semester = 2:1)
    }
    years_to_expand <- bind_rows(reported_years, next_year)

    six_months_expand <- six_months %>%
      distinct(disease, disease_population, taxa) %>%
      expand_grid(country_iso3c = unique(six_months$country_iso3c),
                  years_to_expand) %>%
      arrange(country_iso3c, taxa, disease, disease_population, report_year, report_semester)

    to_add <- six_months_expand%>%
      anti_join(six_months,  by = c("taxa", "disease_population", "disease", "country_iso3c", "report_semester", "report_year")) %>%
      mutate(disease_status = "unreported")

    six_months <- bind_rows(six_months, to_add)

  }

  # process all data with latest events added
  six_months_processed <- repel_init(model_object = model_object,
                                     conn = conn,
                                     six_month_reports_summary = six_months)

  if(!process_all){
    # only need relevant disease/country combos (not full expanded dataset)
    # events_processed <- events_processed %>%
    #   right_join(events_lookup_clean, by = c("country_iso3c", "disease", "disease_name_uncleaned")) %>%
    #   select(-disease_in_single_country) # this field does not apply when only looking at a subset of the data
  }

  # if running on subset of data, determine which disease + country combos have changed status
  if(!process_all){
    # # get existing cache for relevant data
    # network_lme_augment_predict <- tbl(conn, "network_lme_augment_predict") %>%
    #   inner_join(events_lookup_clean, copy = TRUE, by = c("country_iso3c", "disease")) %>%
    #   select(!!colnames(events_processed)) %>%
    #   collect()
    #
    # # compare new processed data with existing cache
    # events_processed  <- setdiff(events_processed, network_lme_augment_predict)
    # if(nrow(events_processed) == 0) events_processed <- NULL
  }

  return(six_months_processed)

}
