#!/usr/bin/env Rscript

dir <- ifelse(basename(getwd())=="repel-infrastructure", "scraper/", "")
source(here::here(paste0(dir, "packages.R")))
source(here::here(paste0(dir, "functions.R")))
library(repelpredict)

oie_diseases <- repelpredict:::get_oie_high_importance_diseases()

# Connect to database ----------------------------
message("Connect to database")
conn <- wahis_db_connect()

# Check if aws mod etag differs from db -----------------------------------
aws_network_etag <- aws.s3::head_object(bucket = "repeldb/models", object = "lme_mod_network.rds") %>%
  attr(., "etag")

if(dbExistsTable(conn,  "network_lme_augment_predict")){

  db_network_etag <- tbl(conn, "network_lme_augment_predict") %>%
    distinct(db_network_etag) %>%
    pull(db_network_etag)

}

if(!dbExistsTable(conn,  "nowcast_boost_augment_predict")   | db_network_etag != aws_network_etag ){

  # Cache database predictions ---------------------------------------------------

  model_object <-  network_lme_model(
    network_model = aws.s3::s3readRDS(bucket = "repeldb/models", object = "lme_mod_network.rds"),
    network_scaling_values = aws.s3::s3readRDS(bucket = "repeldb/models", object = "network_scaling_values.rds")
  )

  ### cache full database and prediction
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

  ### cache model coefficients
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

}

# grant permissions
grant_table_permissions(conn)

dbDisconnect(conn)
