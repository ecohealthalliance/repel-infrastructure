#!/usr/bin/env Rscript

dir <- ifelse(basename(getwd())=="repel-infrastructure", "scraper/", "")
source(here::here(paste0(dir, "packages.R")))
purrr::walk(list.files(here::here(paste0(dir, "functions")), full.names = TRUE), source)
library(repelpredict)

oie_diseases <- repelpredict:::get_oie_high_importance_diseases()

# Connect to database ----------------------------
message("Connect to database")
conn <- wahis_db_connect()

# Check if aws mod etag differs from db -----------------------------------
aws_disease_status_etag <- aws.s3::head_object(bucket = "repeldb/models", object = "boost_mod_disease_status.rds") %>%
  attr(., "etag")
aws_cases_etag <- aws.s3::head_object(bucket = "repeldb/models", object = "boost_mod_cases.rds") %>%
  attr(., "etag")

if(dbExistsTable(conn,  "nowcast_boost_augment_predict")){

  db_etag <- tbl(conn, "nowcast_boost_augment_predict") %>%
    distinct(db_disease_status_etag, db_cases_etag)

  db_disease_status_etag <- db_etag %>% pull(db_disease_status_etag)
  db_cases_etag <-  db_etag %>% pull(db_cases_etag)

}

if(!dbExistsTable(conn,  "nowcast_boost_augment_predict")   | db_disease_status_etag != aws_disease_status_etag | db_cases_etag != aws_cases_etag){

  # Cache database predictions ---------------------------------------------------

  model_object <-  nowcast_boost_model(
    disease_status_model = aws.s3::s3readRDS(bucket = "repeldb/models", object = "boost_mod_disease_status.rds"),
    cases_model = aws.s3::s3readRDS(bucket = "repeldb/models", object = "boost_mod_cases.rds"))

  # get full database
  repeldat <- repelpredict::repel_split(model_object, conn)

  # expand taxa+disease combos to all countries and years (including those not reported)
  reported_years <- repeldat %>%
    arrange(report_year, report_semester) %>%
    distinct(report_year, report_semester)

  last_sem <- reported_years %>%
    tail(1)

  if(last_sem$report_semester == 2){
    next_year <- tibble(report_year = rep(max(last_sem$report_year)+1, each = 2), report_semester = 1:2)
  }else{
    next_year <- tibble(report_year = c(max(last_sem$report_year), max(last_sem$report_year) + 1), report_semester = 2:1)
  }

  years_to_expand <- bind_rows(reported_years, next_year)

  repeldat_expand <- repeldat %>%
    distinct(disease, disease_population, taxa) %>%
    expand_grid(country_iso3c = unique(repeldat$country_iso3c),
                years_to_expand) %>%
    arrange(country_iso3c, taxa, disease, disease_population, report_year, report_semester)

  # note which diseases were reported
  repeldat_reported <- repeldat %>%
    select(colnames(repeldat_expand)) %>%
    mutate(reported = TRUE)

  # run prediction (slow)

  # augment then predict
  # augmented_data <- repel_augment(model_object, conn, repeldat_expand)
  # write_rds(augmented_data, "tmp_augmented_data.rds")
  # predictions <- repel_predict(model_object, newdata = augmented_data)

  # forecast combines augment and predict
  forecasted_repeldat <- repel_forecast(model_object = model_object,
                                        conn = conn,
                                        newdata = repeldat_expand,
                                        use_cache = FALSE)

  forecasted_repeldat <- forecasted_repeldat[[1]] %>%
    mutate(predicted_cases = forecasted_repeldat[[2]]) %>%
    mutate(db_disease_status_etag = aws_disease_status_etag,  db_cases_etag = aws_cases_etag)

  dbWriteTable(conn, name = "nowcast_boost_augment_predict", forecasted_repeldat, overwrite = TRUE)

  # simple output (used in shiny app) -----------------------------------------------------------------

  nowcast_predicted <- tbl(conn, "nowcast_boost_augment_predict")  %>%
    select(report_year, report_semester, disease, country_iso3c, taxa,
           unreported, actual_cases = cases, actual_status = disease_status,  predicted_cases) %>%
    filter(disease %in% oie_diseases) %>%
    collect() %>%
    mutate(predicted_status = predicted_cases > 0,
           actual_status = as.logical(actual_status),
           unreported = as.logical(unreported)) %>%
    group_by(country_iso3c, disease, report_year, report_semester) %>%
    summarize(predicted_status = any(predicted_status), actual_status = any2(actual_status),
              predicted_cases = sum(predicted_cases), actual_cases = sum2(actual_cases), unreported = all(unreported)) %>%
    ungroup()  %>%
    mutate(status_coalesced = case_when(
      actual_status == TRUE ~ "reported present",
      actual_status == FALSE ~ "reported absent",
      unreported == TRUE & predicted_status == TRUE ~ "unreported, predicted present",
      unreported == TRUE & predicted_status == FALSE ~ "unreported, predicted absent",
    )) %>%
    mutate(status_coalesced = factor(status_coalesced, levels = c("reported present", "unreported, predicted present",  "reported absent", "unreported, predicted absent"))) #%>%
   # mutate(cases_coalesced = coalesce(actual_cases, predicted_cases))

  dbWriteTable(conn, name = "nowcast_boost_predict_oie_diseases", nowcast_predicted, overwrite = TRUE)

}

# grant permissions
grant_table_permissions(conn)

dbDisconnect(conn)
