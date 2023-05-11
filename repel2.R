source(here::here("scraper", "packages.R"))
library(repelpredict)
purrr::walk(list.files(here::here("scraper", "R"), full.names = TRUE), source)

# Connect to read-only database on kirby
conn <- repeldata::repel_remote_conn()
dbListTables(conn)

# Get Model from AWS
model_object <-  repelpredict::network_lme_model(
  network_model = aws.s3::s3readRDS(bucket = "repeldb/models", object = "lme_mod_network.rds"),
  network_scaling_values = aws.s3::s3readRDS(bucket = "repeldb/models", object = "network_scaling_values.rds")
)

# Pull random effects from model for data check in preprocess_outbreak_events()
lme_mod <- model_object$network_model
randef <- lme4::ranef(lme_mod)

# Get outbreak data from the database
# This data was preprocessed from WAHIS extracts from old API
# This will be some formatting differences, but this table is akin to the current `wahis_epi_events` table
# https://www.dolthub.com/repositories/ecohealthalliance/wahisdb/data/main/wahis_epi_events
# It contains high-level event information. For our current purposes, case counts and location coordinates are not needed
outbreak_reports_events <- tbl(conn, "outbreak_reports_events") |>
  filter(country_iso3c == "ZAF", disease == "rift valley fever") |>
  collect()

# Covert this data into format needed to make model predictions
events_processed <- preprocess_outbreak_events(model_object,
                                               conn,
                                               events_new = outbreak_reports_events,
                                               randef = randef,
                                               process_all = FALSE)

# Generate predictions
# this returns the outbreak probability and the augmented data used to make predictions
repel_forecast_events <- repel_forecast(model_object = model_object,
                                        conn = conn,
                                        newdata = events_processed)


network_lme_augment_predict_events <- repel_forecast_events[[1]] |>
  mutate(predicted_outbreak_probability = repel_forecast_events[[2]])

# just the predictions by month
forcasted_predictions <- network_lme_augment_predict_events |>
  select(country_iso3c, disease, month, predicted_outbreak_probability)

# Get augment with disaggregated country imports (this can take a while on the full dataset, but is fast for a few predictions)
message("Getting disaggregated country import augmented data")
a = Sys.time()
augmented_data_disagg_events <- repel_augment(model_object, conn, newdata = events_processed, sum_country_imports = FALSE)
b = Sys.time()
message(paste0("Finished getting disaggregated country import augmented data. ", round(as.numeric(difftime(time1 = b, time2 = a, units = "secs")), 3), " seconds elapsed"))

# Combine disaggregated imports with the forecasts
network_lme_augment_predict_by_origin_events <-  augmented_data_disagg_events %>%
  left_join(forcasted_predictions, by = c("country_iso3c", "disease", "month"))
