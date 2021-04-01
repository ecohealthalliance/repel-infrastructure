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
  db_network_etag <- unique(forecasted_repeldat$db_disease_status_etag)
}

if(!dbExistsTable(conn,  "nowcast_boost_augment_predict")   | db_network_etag != aws_network_etag ){

  # Cache database predictions ---------------------------------------------------

  model_object <-  network_lme_model(
    network_model = aws.s3::s3readRDS(bucket = "repeldb/models", object = "lme_mod_network.rds")
  )

  # get full database
  repeldat <- repelpredict::repel_split(model_object, conn)

  # run prediction (slow)

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

  #TODO move network_recipe into augment?
  forecasted_repeldat2 <- repelpredict:::network_recipe(forecasted_repeldat[[1]], predictor_vars = c("shared_borders_from_outbreaks", "ots_trade_dollars_from_outbreaks", "fao_livestock_heads_from_outbreaks")) %>%
    mutate(predicted_outbreak_probability = forecasted_repeldat[[2]]) %>%
    mutate(db_network_etag = aws_network_etag)

  dbWriteTable(conn, name = "network_lme_augment_predict", forecasted_repeldat2, overwrite = TRUE)

}

dbDisconnect(conn)
