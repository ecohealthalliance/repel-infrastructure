#!/usr/bin/env Rscript

dir <- ifelse(basename(getwd())=="repel-infrastructure", "scraper", "")
source(here::here(dir, "packages.R"))
purrr::walk(list.files(here::here(dir, "R"), full.names = TRUE), source)
library(repelpredict)

#TODO add ernest to git-crypt

# Connect to database ----------------------------
message("Connect to database")
hl <- ifelse(dir == "scraper", "reservoir", "remote")
conn <- wahis_db_connect(host_location = hl)

# Get Model from AWS ----------------------------
model_object <-  repelpredict::network_lme_model(
  network_model = aws.s3::s3readRDS(bucket = "repeldb/models", object = "lme_mod_network.rds"),
  network_scaling_values = aws.s3::s3readRDS(bucket = "repeldb/models", object = "network_scaling_values.rds")
)

# Pull random effects from model for data check in preprocess_outbreak_events()
lme_mod <- model_object$network_model
randef <- lme4::ranef(lme_mod)

# Get outbreak data from the database
outbreak_reports_events <- tbl(conn, "outbreak_reports_events") |>
  # filter for disease/country
  collect()

# Preprocess this data
events_processed <- preprocess_outbreak_events(model_object,
                                               conn,
                                               events_new = outbreak_reports_events,
                                               randef = randef,
                                               process_all = FALSE)


repel_forecast_events <- repel_forecast(model_object = model_object,
                                        conn = conn,
                                        newdata = events_processed)

network_lme_augment_predict_events <- repel_forecast_events[[1]] %>%
  mutate(predicted_outbreak_probability = repel_forecast_events[[2]])

forcasted_predictions <- network_lme_augment_predict_events %>%
  distinct(country_iso3c, disease, month, predicted_outbreak_probability)


