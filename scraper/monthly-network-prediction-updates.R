#!/usr/bin/env Rscript

# model augment depends on assumption that disease are ongoing in a given month if they havent been reported as closed in previous year
# basically, need to run repel_init every month to carry on assumptions to current month
# easiest to run on full dataset, as you need full time series for each disease + country combo (repel_init projects forward and back)

message("Running monthly network prediction cache update")
dir <- ifelse(basename(getwd())=="repel-infrastructure", "scraper/", "")
source(here::here(paste0(dir, "packages.R")))
purrr::walk(list.files(here::here(paste0(dir, "/R")), full.names = TRUE), source)
library(repelpredict)

message("Connect to database")
hl <- ifelse(dir == "scraper/", "reservoir", "remote")
conn <- wahis_db_connect(host_location = hl)

model_object <-  repelpredict::network_lme_model(
  network_model = aws.s3::s3readRDS(bucket = "repeldb/models", object = "lme_mod_network.rds"),
  network_scaling_values = aws.s3::s3readRDS(bucket = "repeldb/models", object = "network_scaling_values.rds")
)

# get model etag
aws_network_etag <- aws.s3::head_object(bucket = "repeldb/models", object = "lme_mod_network.rds") %>%
  attr(., "etag")

# pull disease names from model for data check below
lme_mod <- model_object$network_model
randef <- lme4::ranef(lme_mod)

assert_that(dbExistsTable(conn, "outbreak_reports_events"))
events_processed <- preprocess_outbreak_events(conn,
                                               events_new = NULL, # when NULL, just runs on outbreak_reports_events (only works when process_all = TRUE)
                                               randef = randef,
                                               process_all = TRUE)

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

message("Done updating database")


# grant permissions
grant_table_permissions(conn)

dbDisconnect(conn)

