library(tidyverse)
library(rnaturalearth)
library(leaflet)
library(leafpop)
library(stringi)
library(repelpredict)
library(lme4)
source(here::here("shiny", "content", "nowcast",'functions.R'))

# Read cached data
conn <- repeldata::repel_remote_conn()
network_lme_augment_predict <- DBI::dbReadTable(conn, name = "network_lme_augment_predict") %>% as_tibble()
network_lme_augment_disaggregated <- DBI::dbReadTable(conn, name = "network_lme_augment_disaggregated") %>% as_tibble()
repeldata::repel_remote_disconnect()

# Focus on OIE
oie_diseases <- repelpredict:::get_oie_high_importance_diseases()
names(oie_diseases) <- stri_trans_totitle(stri_replace_all_fixed(oie_diseases, "_", " "))

disease_select <- "highly_pathogenic_avian_influenza"
month_select <- "2018-07-01"

# Get model coeffs
model_object <-  network_lme_model(
  network_model = aws.s3::s3readRDS(bucket = "repeldb/models", object = "lme_mod_network.rds"),
  network_scaling_values = aws.s3::s3readRDS(bucket = "repeldb/models", object = "network_scaling_values.rds")
)
lme_mod <- model_object$network_model
randef <- ranef(lme_mod)
randef_disease <- randef$disease %>%
  tibble::rownames_to_column(var = "disease") %>%
  as_tibble() %>%
  pivot_longer(-disease, names_to = "variable", values_to = "coef")

# Set up data for basemap
admin <- ne_countries(type='countries', scale = 'medium', returnclass = "sf") %>%
  filter(name != "Antarctica") %>%
  select(country_iso3c = iso_a3, geometry)

basemap_probability <- network_lme_augment_predict %>%
  filter(disease %in% oie_diseases) %>%
  filter(disease == disease_select, # select disease
         month == month_select)  # select month
  # (germany has a very high prob and then next month there's an outbreak)
basemap_probability <- left_join(admin, basemap_probability)

basemap_status <- basemap_probability %>%
  mutate(disease_country_combo_unreported = is.na(predicted_outbreak_probability)) %>%
  mutate(reported_outbreak = endemic|outbreak_subsequent_month|outbreak_start) %>%
  mutate(reported_outbreak = replace_na(reported_outbreak, FALSE)) %>%
  filter(disease_country_combo_unreported | reported_outbreak) %>%
  mutate(cat_status = if_else(disease_country_combo_unreported, "Disease never in country", "Current Outbreak"))

# for import/exports, id countries with current outbreaks
country_outbreaks <- basemap_status %>%
  as_tibble() %>%
  filter(cat_status == "Current Outbreak") %>%
  distinct(country_iso3c, disease, month, cat_status)

# Set up data for import/export weights
country_trade_disagg <- network_lme_augment_disaggregated %>%
  drop_na(country_origin) %>%
  pivot_longer(cols = c("shared_borders_from_outbreaks", "ots_trade_dollars_from_outbreaks", "fao_livestock_heads_from_outbreaks"),
               names_to = "variable", values_to = "value") %>%
  select(-outbreak_start) %>%
  left_join(randef_disease) %>%
  mutate(rel_import = value * coef) %>%
  group_by(country_iso3c, disease, month, country_origin) %>%
  summarize(country_rel_import = sum(rel_import)) %>%
  ungroup() %>%
  filter(disease == disease_select, # select disease
         month == month_select)  # select month

country_import_weights <- country_trade_disagg %>%
  left_join(country_outbreaks,  by = c("country_iso3c", "disease", "month")) %>%
  filter(is.na(cat_status)) %>%
  select(-cat_status) %>%
  arrange(country_iso3c, -country_rel_import)

country_export_weights <- country_trade_disagg %>%
  arrange(country_origin, -country_rel_import)

# Get overall variable importance for each country (dot plot)

# Leaflet
probability_pal <- colorNumeric(palette = "viridis", domain = network_lme_augment_predict$predicted_outbreak_probability, na.color = "transparent")
status_pal <- colorFactor(palette = c("#a83434", "#7f7f7f"),
                                  levels = sort(unique(basemap_status$cat_status)))
leaflet() %>%
  addProviderTiles("CartoDB.DarkMatter") %>%
  setView(lng = 30, lat = 30, zoom = 1.5) %>%
  addPolygons(data = basemap_probability, weight = 0.5, smoothFactor = 0.5,
              opacity = 0.2, color = "white",
              fillOpacity = 0.75, fillColor = ~probability_pal(predicted_outbreak_probability),
              layerId = ~country_iso3c) %>%
  addPolygons(data = basemap_status, weight = 0.5, smoothFactor = 0.5,
              opacity = 0.2, color = "white",
              fillOpacity = 1, fillColor = ~status_pal(cat_status)) %>%
  addLegend_decreasing(pal = probability_pal, values = network_lme_augment_predict$predicted_outbreak_probability,
                       position = "bottomright", decreasing = TRUE, title = "Predicted outbreak probability") %>%
  addLegend_decreasing(pal = status_pal, values = unique(basemap_status$cat_status),
                       position = "bottomright", decreasing = FALSE, title = "")



