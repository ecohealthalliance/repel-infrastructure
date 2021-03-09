library(tidyverse)
library(rnaturalearth)
library(rnaturalearthdata)
library(sf)
library(RColorBrewer)

any2 <- function(x) ifelse(all(is.na(x)), NA, any(x, na.rm = TRUE))
sum2 <- function(x) ifelse(all(is.na(x)), NA, sum(x, na.rm = TRUE))

oie_diseases <- repelpredict:::get_oie_high_importance_diseases()

# conn <- repeldata::repel_remote_conn(
#     host = "postgres",
#     port = 5432,
#     user = "repel_reader",
#     password = Sys.getenv("REPEL_READER_PASS")
# )

conn <- repeldata::repel_remote_conn()

nowcast_predicted <- tbl(conn, "nowcast_boost_augment_predict")  %>%
  select(report_year, report_semester, disease, country_iso3c, taxa,
         unreported, actual_cases = cases, actual_status = disease_status,  predicted_cases) %>%
  filter(disease %in% oie_diseases) %>%
  collect() %>%
  mutate(predicted_status = predicted_cases > 0,
         actual_status = as.logical(actual_status),
         unreported = as.logical(unreported))

write_csv(nowcast_predicted, here::here("shiny", "content", "nowcast", "data", "nowcast_predicted_raw.csv"))

nowcast_predicted_sum <- nowcast_predicted %>%
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
  mutate(status_coalesced = factor(status_coalesced, levels = c("reported present", "unreported, predicted present",  "reported absent", "unreported, predicted absent"))) %>%
  mutate(cases_coalesced = coalesce(actual_cases, predicted_cases)) %>%
  mutate(tooltip_lab = paste0(countrycode::countrycode(country_iso3c, origin = "iso3c", destination = "country.name"),
                              ":",
                              if_else(unreported, paste0(" ", cases_coalesced, " predicted cases"), paste0(" ", cases_coalesced, " reported cases"))
  ))

write_csv(nowcast_predicted_sum, here::here("shiny", "content", "nowcast", "data", "nowcast_predicted_sum.csv"))

repeldata::repel_remote_disconnect()

