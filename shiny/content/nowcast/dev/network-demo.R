library(tidyverse)
library(rnaturalearth)
library(leaflet)
library(leafpop)
library(ggiraph)
library(patchwork)
library(glue)
library(stringi)
library(promises)
library(future)
source(here::here("shiny", "content", "nowcast",'functions.R'))

conn <- repeldata::repel_remote_conn()

network_lme_augment_predict <- DBI::dbReadTable(conn, name = "network_lme_augment_predict") %>% as_tibble()

repeldata::repel_remote_disconnect()

oie_diseases <- repelpredict:::get_oie_high_importance_diseases()
names(oie_diseases) <- stri_trans_totitle(stri_replace_all_fixed(oie_diseases, "_", " "))

mapdat <- network_lme_augment_predict %>%
  filter(disease %in% oie_diseases) %>%
  filter(disease == "highly_pathogenic_avian_influenza",
         month == "2018-07-01")

# this is cool because germany has a very high prob and then next month there's an outbreak

# World map borders
admin <- ne_countries(type='countries', scale = 'medium', returnclass = "sf") %>%
  filter(name != "Antarctica") %>%
  select(country_iso3c = iso_a3, geometry)

admin_mapdat <- admin %>%
  left_join(mapdat) %>%
  mutate(disease_country_combo_unreported = is.na(predicted_outbreak_probability)) %>%
  mutate(reported_outbreak = endemic|outbreak_subsequent_month|outbreak_start) %>%
  mutate(reported_outbreak = replace_na(reported_outbreak, FALSE)) %>%
  mutate(cat_status = if_else(disease_country_combo_unreported, "Disease never in country",
                              if_else(reported_outbreak, "Current Outbreak", "predict_prob")))

admin_mapdat_cat <- admin_mapdat %>%
  filter(cat_status != "predict_prob")

travelcast_pal <- colorNumeric(palette = "viridis", domain = network_lme_augment_predict$predicted_outbreak_probability, na.color = "transparent")
travelcast_pal_cat <- colorFactor(palette = c("#a83434", "#7f7f7f"),
                                  levels = sort(unique(admin_mapdat_cat$cat_status)))


leaflet() %>%
  addProviderTiles("CartoDB.DarkMatter") %>%
  setView(lng = 30, lat = 30, zoom = 1.5) %>%
  addPolygons(data = admin_mapdat, weight = 0.5, smoothFactor = 0.5,
              opacity = 0.2, color = "white",
              fillOpacity = 0.75, fillColor = ~travelcast_pal(predicted_outbreak_probability),
              layerId = ~country_iso3c) %>%
  addPolygons(data = admin_mapdat_cat, weight = 0.5, smoothFactor = 0.5,
              opacity = 0.2, color = "white",
              fillOpacity = 1, fillColor = ~travelcast_pal_cat(cat_status)) %>%
  addLegend_decreasing(pal = travelcast_pal, values = network_lme_augment_predict$predicted_outbreak_probability,
                       position = "bottomright", decreasing = TRUE, title = "Predicted outbreak probability") %>%
  addLegend_decreasing(pal = travelcast_pal_cat, values = unique(admin_mapdat_cat$cat_status),
                       position = "bottomright", decreasing = FALSE, title = "")


# click on non-outbreak country and get import connectivity (map_deck)
# click on outbreak country and get export connectivity (map_deck)

# click on non-outbreak country and get variable importance (dot plot)

