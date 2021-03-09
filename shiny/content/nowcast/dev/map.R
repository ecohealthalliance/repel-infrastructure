library(shiny)
library(tidyverse)
library(rnaturalearth)
library(rnaturalearthdata)
library(sf)
library(leaflet)
library(leaflet.extras)
library(RColorBrewer)

any2 <- function(x) ifelse(all(is.na(x)), NA, any(x, na.rm = TRUE))

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
  select(report_year, report_semester, disease, country_iso3c, continent,
         unreported, actual_cases = cases, actual_status = disease_status,  predicted_cases) %>%
  filter(disease %in% diseases) %>%
  collect() %>%
  mutate(predicted_status = predicted_cases > 0,
         actual_status = as.logical(actual_status),
         unreported = as.logical(unreported))

report_year <- 2019
report_semester <- 1

nowcast_world_map <- function(disease, report_year, report_semester){

  # proj <-  "+proj=robin +lon_0=0 +x_0=0 +y_0=0 +ellps=WGS84 +datum=WGS84 +units=m +no_defs"
  # proj_leaflet <- leafletCRS(proj4def = proj)

  dat <- nowcast_predicted %>%
    filter(disease == !!disease, report_year == !!report_year, report_semester == !!report_semester) %>%
    group_by(country_iso3c) %>%
    summarize(predicted_status = any(predicted_status), actual_status = any2(actual_status), unreported = all(unreported),
              predicted_cases = sum(predicted_cases), actual_cases = sum(actual_cases, na.rm = TRUE)
              ) %>%
    ungroup()  %>%
    mutate(status = case_when(
      actual_status == TRUE ~ "reported present",
      actual_status == FALSE ~ "reported absent",
      unreported == TRUE & predicted_status == TRUE ~ "unreported, predicted present",
      unreported == TRUE & predicted_status == FALSE ~ "unreported, predicted absent",
    )) %>%
    mutate(status = factor(status, levels = c("reported present", "unreported, predicted present",  "reported absent", "unreported, predicted absent"))) %>%
    mutate(tooltip_lab = paste0(countrycode::countrycode(country_iso3c, origin = "iso3c", destination = "country.name"),
                                ":",
                                if_else(unreported, paste0(" ", predicted_cases, " predicted cases"), paste0(" ", actual_cases, " reported cases"))
                               ))

  admin <- ne_countries(type='countries', scale = 'medium', returnclass = "sf") %>%
    filter(name != "Antarctica") %>%
    select(country_iso3c = iso_a3, geometry) %>%
    right_join(dat)

  pal <- colorFactor(palette = c("#E31A1C", "#FB9A99", "#1F78B4", "#A6CEE3"), domain = levels(dat$status))
  admin <- admin %>% left_join(tibble(fill = c("#E31A1C", "#FB9A99", "#1F78B4", "#A6CEE3"), status = levels(dat$status)))

  leaflet() %>%
    addProviderTiles("CartoDB.DarkMatter") %>%
    addPolygons(data = admin, weight = 0.5, smoothFactor = 0.5,
                opacity = 0.5,  color = ~fill,
                fillOpacity = 0.75, fillColor = ~fill,
                label = ~tooltip_lab) %>%
    addLegend(pal = pal, values = levels(dat$status), position = "bottomright",
              labFormat = labelFormat(transform = function(x) levels(dat$status)))

  # ggplot(data = admin) +
  #   geom_sf(aes(fill = actual_presence)) +
  #     scale_fill_manual(values = c("present" = "#d67b74", "absent" =  "#21908CFF")) +
  #     labs(fill  = "") +
  #     ggthemes::theme_map() +
  #     theme(legend.position = "right")

  # # failed 1
  # admin <- ne_countries(type='countries', scale = 'small', returnclass = "sf") %>%
  #   filter(name != "Antarctica") %>%
  #   select(country_iso3c = iso_a3, geometry) %>%
  #   right_join(dat)
  #
  # ggplot(admin) +
  #   geom_sf_pattern(aes(fill = test, pattern_type = test)) +
  #   scale_pattern_type_discrete(choices = ggpattern::magick_pattern_names)
  #
  #
  # # failed 2
  # admin <- map_data("world") %>%
  #   filter(region != "Antarctica") %>%
  #   mutate(country_iso3c = suppressWarnings(countrycode::countrycode(region,
  #                                                   origin = "country.name",
  #                                                   destination = "iso3c"))) %>%
  #   right_join(dat)
  #
  # ggplot(data = admin,  aes(map_id = test)) +
  #   geom_map_pattern(map = admin, aes(pattern = test),
  #                    pattern              = 'magick',
  #                    pattern_fill         = 'black',
  #                    pattern_aspect_ratio = 1.75,
  #                    fill                 = 'white',
  #                    colour               = 'black') +
  #   expand_limits(x = admin$long, y = admin$lat) +
  #   coord_map() +
  #   theme_bw(18)


  # also failed: leaflet HatchedPolygons
  # hatched <- HatchedPolygons::hatched.SpatialPolygons(admin %>% filter(predicted_presence == "present"), density = c(6,4), angle = c(45, 135))

  # admin_predicted <- admin %>%
  #   filter(predicted_presence) %>%
  #   st_rasterize()


