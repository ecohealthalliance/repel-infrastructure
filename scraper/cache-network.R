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

  forecasted_repeldat <- dbReadTable(conn, name = "network_lme_augment_predict")
  db_network_etag <- unique(forecasted_repeldat$db_network_etag)
}

if(!dbExistsTable(conn,  "nowcast_boost_augment_predict")   | db_network_etag != aws_network_etag ){

  # Cache database predictions ---------------------------------------------------

  model_object <-  network_lme_model(
    network_model = aws.s3::s3readRDS(bucket = "repeldb/models", object = "lme_mod_network.rds"),
    network_scaling_values = aws.s3::s3readRDS(bucket = "repeldb/models", object = "network_scaling_values.rds")
  )

  # get full database
  repeldat <- repelpredict::repel_split(model_object, conn)

  # augment then predict
  # augmented_data <- repel_augment(model_object, conn, newdata = repeldat)
  # write_rds(augmented_data, "tmp_augmented_data.rds")
  # augmented_data <-read_rds("tmp_augmented_data.rds")
  # predictions <- repel_predict(model_object, newdata = augmented_data)

  # forecast combines augment and predict
  forecasted_repeldat <- repel_forecast(model_object = model_object,
                                        conn = conn,
                                        newdata = repeldat,
                                        use_cache = FALSE)

  forecasted_repeldat2 <- forecasted_repeldat[[1]] %>%
    select(country_iso3c, disease, month, outbreak_start, outbreak_subsequent_month, endemic, !!predictor_vars) %>%
    mutate(predicted_outbreak_probability = forecasted_repeldat[[2]]) %>%
    mutate(db_network_etag = aws_network_etag)

  write_rds(forecasted_repeldat2, "tmp_forecasted_data.rds")
  # forecasted_repeldat2 <- read_rds("tmp_forecasted_data.rds")

  dbWriteTable(conn, name = "network_lme_augment_predict", forecasted_repeldat2, overwrite = TRUE)

  # disaggregate country imports
  augmented_data_disagg <- repel_augment(model_object, conn, newdata = forecasted_repeldat2, sum_country_imports = FALSE)

  augmented_data_disagg2 <- augmented_data_disagg %>%
    drop_na(country_origin)

  dbWriteTable(conn, name = "network_lme_augment_disaggregated", augmented_data_disagg2, overwrite = TRUE)

}

# set grant permissions
grant_table_permissions(conn)

dbDisconnect(conn)


