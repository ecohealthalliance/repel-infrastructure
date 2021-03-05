library(shiny)
library(tidyverse)
library(rnaturalearth)
library(rnaturalearthdata)
library(sf)
library(leaflet)
library(leaflet.extras)
library(RColorBrewer)
library(stars)
diseases <-  c("foot_and_mouth_disease", "vesicular_stomatitis",
               "swine_vesicular_disease", "rinderpest",
               "peste_des_petits_ruminants", "ovine_bluetongue_disease",
               "lumpy_skin_disease", "rift_valley_fever",
               "african_horse_sickness", "african_swine_fever",
               "classical_swine_fever", "highly_pathogenic_avian_influenza",
               "newcastle_disease", "pleuropneumonia", "ovine_pox_disease")
disease <- diseases[[1]]

conn <- repeldata::repel_remote_conn()

nowcast_predicted <- tbl(conn, "nowcast_boost_augment_predict")  %>%
  select(report_year, report_semester, disease, country_iso3c, continent, cases, predicted_cases) %>%
  filter(disease %in% diseases) %>%
  collect() %>%
  filter(report_year == max(report_year)) %>%
  mutate(predicted_presence = predicted_cases > 0) %>%
  mutate(actual_presence = cases > 0 | is.na(cases))

#TODO - add to augment whether report is missing
#TODO - why arent all country/disease combo here?
# ^ will happen when model is rerun, then predicted and cached in DB

report_year <- 2019
report_semester <- 1
nowcast_world_map <- function(disease, report_year, report_semester){

  proj <-  "+proj=robin +lon_0=0 +x_0=0 +y_0=0 +ellps=WGS84 +datum=WGS84 +units=m +no_defs"
  proj_leaflet <- leafletCRS(proj4def = proj)

  dat <- nowcast_predicted %>%
    filter(disease == !!disease, report_year == 2019, report_semester == 1) %>%
    group_by(country_iso3c, continent) %>%
    summarize(predicted_presence = any(predicted_presence), actual_presence = any(actual_presence)) %>%
    ungroup() %>%
    mutate(actual_presence = factor(actual_presence, levels = c(TRUE, FALSE), labels = c("present", "absent"))) %>%  # add unreported
    mutate(predicted_presence = factor(predicted_presence, levels = c(TRUE, FALSE), labels = c("present", "absent"))) # add unreported

  admin <- ne_countries(type='countries', scale = 'large') %>%
    st_as_sf() %>%
    filter(name != "Antarctica") %>%
    select(country_iso3c = iso_a3, geometry) %>%
    right_join(dat)

  admin_predicted <- admin %>%
    filter(predicted_presence) %>%
    st_rasterize()

  #TODO get transformation working
  pal <- colorFactor(palette = c("#d67b74", "#21908CFF"), domain = levels(dat$actual_presence))

  leaflet() %>%
    addProviderTiles("CartoDB.DarkMatter") %>%
    addPolygons(data = admin, weight = 1, smoothFactor = 0.5,
                opacity = 1, color = ~pal(predicted_presence),
                fillOpacity = 0.5, fillColor = ~pal(actual_presence)) %>%
    addLegend(pal = pal, values = levels(dat$actual_presence), position = "bottomright",
              labFormat = labelFormat(transform = function(x) sort(x, decreasing = TRUE)))


