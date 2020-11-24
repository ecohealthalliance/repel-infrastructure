#!/usr/bin/env Rscript

dir <- ifelse(basename(getwd())=="repel-infrastructure", "scraper/", "")
source(here::here(paste0(dir, "packages.R")))
source(here::here(paste0(dir, "functions.R")))
library(repelpredict)

# Connect to database ----------------------------
message("Connect to database")
conn <- wahis_db_connect()

# Check if aws mod etag differs from db -----------------------------------
aws_disease_status_etag <- aws.s3::head_object(bucket = "repeldb/models", object = "boost_mod_disease_status.rds") %>%
  attr(., "etag")
aws_cases_etag <- aws.s3::head_object(bucket = "repeldb/models", object = "boost_mod_cases.rds") %>%
  attr(., "etag")

if(dbExistsTable(conn,  "nowcast_boost_augment_predict")){

  forecasted_repeldat <- dbReadTable(conn, name = "nowcast_boost_augment_predict")
  db_disease_status_etag <- unique(forecasted_repeldat$db_disease_status_etag)
  db_cases_etag <- unique(forecasted_repeldat$db_cases_etag)

}

if(!dbExistsTable(conn,  "nowcast_boost_augment_predict")   | db_disease_status_etag != aws_disease_status_etag | db_cases_etag != aws_cases_etag){

  # Cache full database predictions ---------------------------------------------------
  repeldat <- repelpredict:::repel_cases(conn) %>%
    select(all_of(repelpredict:::grouping_vars), validation_set) %>%
    distinct()

  model_object <-  nowcast_boost_model(
    disease_status_model = aws.s3::s3readRDS(bucket = "repeldb/models", object = "boost_mod_disease_status.rds"),
    cases_model = aws.s3::s3readRDS(bucket = "repeldb/models", object = "boost_mod_cases.rds"))

  forecasted_repeldat <- repel_forecast(model_object = model_object,
                                        conn = conn,
                                        newdata = repeldat)

  forecasted_repeldat <- forecasted_repeldat[[1]] %>%
    mutate(predicted_cases = forecasted_repeldat[[2]]) %>%
    mutate(db_disease_status_etag = aws_disease_status_etag,  db_cases_etag = aws_cases_etag)

  dbWriteTable(conn, name = "nowcast_boost_augment_predict", forecasted_repeldat, overwrite = TRUE)
}

dbDisconnect(conn)
