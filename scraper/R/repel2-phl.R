# Script adapted from scrape-outbreak-reports.R
# Setup ------------------------------------------------------------------------

source(here::here("scraper", "packages.R"))
library(repelpredict)
purrr::walk(list.files(here::here("scraper", "R"), full.names = TRUE), source)

# Generate model predictions for actual outbreaks ------------------------------

## Connect to read-only database on kirby ----
conn <- repeldata::repel_remote_conn()
#dbListTables(conn)

## Get Model from AWS ----
model_object <- repelpredict::network_lme_model(
  network_model = aws.s3::s3readRDS(
    bucket = "repeldb/models",
    object = "lme_mod_network.rds"
  ),
  network_scaling_values = aws.s3::s3readRDS(
    bucket = "repeldb/models",
    object = "network_scaling_values.rds"
  )
)

## Pull random effects from model ----
## for data check in preprocess_outbreak_events()
lme_mod <- model_object$network_model
randef <- lme4::ranef(lme_mod)

## Get outbreak data from the database ----
## This data was preprocessed from WAHIS extracts from old API
## Subset the data to Philippines (PHL)
phl_outbreak_reports_events <- tbl(conn, "outbreak_reports_events") |>
  filter(country_iso3c == "PHL") |>
  collect()


## Covert this data into format needed to make model predictions ----
phl_events_processed <- preprocess_outbreak_events(
  model_object, conn, events_new = phl_outbreak_reports_events, randef = randef,
  process_all = FALSE
)

## Generate predictions ----
## this returns the outbreak probability and the augmented data used to make
## predictions
repel_forecast_phl_events <- repel_forecast(
  model_object = model_object, conn = conn, newdata = phl_events_processed
)

network_lme_augment_predict_events <- repel_forecast_phl_events[[1]] |>
  mutate(predicted_outbreak_probability = repel_forecast_phl_events[[2]])

## just the predictions by month ----
phl_forcasted_predictions <- network_lme_augment_predict_events |>
  select(country_iso3c, disease, month, predicted_outbreak_probability)

## Get augment with disaggregated country imports ----
## (this can take a while on the full dataset, but is fast for a few predictions)
message("Getting disaggregated Philippines import augmented data")
a = Sys.time()

augmented_data_disagg_events <- repel_augment(
  model_object, conn, newdata = phl_events_processed, sum_country_imports = FALSE
)

b = Sys.time()

message(
  paste0(
    "Finished getting disaggregated Philippines import augmented data. ",
    round(as.numeric(difftime(time1 = b, time2 = a, units = "secs")), 3),
    " seconds elapsed"
  )
)


## Create barplot for yearly predictions per disease ----

phl_forcasted_predictions |>
  mutate(
    year = year(month),
    disease = stringr::str_replace_all(
      string = disease, pattern = "_", replacement = " "
    ) |>
      stringr::str_to_title()
  ) |>
  summarise(
    mean_predicted_outbreak_probability = mean(predicted_outbreak_probability),
    .by = c(disease, year)
  ) |>
  ggplot(
    mapping = aes(
      x = mean_predicted_outbreak_probability,
      y = fct_reorder(disease, mean_predicted_outbreak_probability)
    )
  ) +
  geom_col() +
  facet_wrap(year ~ ., nrow = 3, scales = "free_y") +
  labs(x = "Mean predicted outbreak probability", y = NULL) +
  theme_bw()

# found some tables and functions that are very useful!! ---------------------------------------------------
# lets understand how these are all generated

##  all PHL diseases
phl_predicts <- tbl(conn, "network_lme_augment_predict") |>
  filter(country_iso3c == "PHL") |>
  collect()
# network_lme_augment_predict is generated from "outbreak_report_events" (which is raw wahis data) -> repel_init() -> repel_forecast()
# it contains all possible combinations of country, disease, month
# we had regularly updated and cached this table in the database to facilitate easy queries (see monthly-network-prediction-updates.R)

# example code (this takes a long time to run)
# NOTE this currently fails on one of the function tests, I think the wrapping of repel_init with preprocess_outbreak_events is necessary to deal with some edge cases in the data
all_data <- repel_init(model_object = model_object,
                       conn = conn,
                       outbreak_reports_events = NULL,
                       remove_single_country_disease = FALSE,
                       remove_non_primary_taxa_disease = FALSE)
forecasted_data <- repel_forecast(
  model_object = model_object, conn = conn, newdata = all_data
)

# ok this works
all_data <- preprocess_outbreak_events(model_object = model_object,
                                       conn,
                                       events_new = NULL, # when NULL, just runs on outbreak_reports_events (only works when process_all = TRUE)
                                       randef = randef,
                                       process_all = TRUE)
forecasted_data <- repel_forecast(
  model_object = model_object, conn = conn, newdata = all_data
)

## all PHL diseases by month disaggregated
phl_predicts_disagg <- tbl(conn, "network_lme_augment_predict_by_origin") |>
  filter(country_iso3c == "PHL") |>
  collect()
# network_lme_augment_predict_by_origin is generated from "outbreak_report_events" -> repel_init() -> repel_augment(sum_country_imports = FALSE)
# this provides all the disaggregated imports of trade, livestock, and wildlife migration by source country
# it also has the predictions from network_lme_augment_predict added on for reference
# we had regularly updated and cached this table in the database to facilitate easy queries (see monthly-network-prediction-updates.R)

# function get_network_variable_importance for priority diseases
origin_contribution_import_risk <- repelpredict::get_network_origin_contribution_import_risk(conn, country_iso3c = "PHL",  month = "2021-05-01")

# other functions that may be relevant in the future
phl_predict_status <- repelpredict::get_disease_status_predict(conn, country_iso3c = "PHL")
var_importance <- repelpredict::get_network_variable_importance(conn, country_iso3c = "PHL", month = "2021-05-01")
var_importance_with_orig <- repelpredict::get_network_variable_importance_with_origins(conn, country_iso3c = "PHL",  month = "2021-05-01")

# See EHA-ASF-outbreak-in-DR-2021 for some applications of this
