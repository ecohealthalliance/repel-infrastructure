library(tidyverse)
library(rnaturalearth)
library(leaflet)
library(leafpop)
library(stringi)
library(repelpredict)
library(lme4)
library(mapdeck)
library(sf)
source(here::here("shiny", "content", "nowcast",'functions.R'))

# Read cached data
conn <- repeldata::repel_remote_conn()
network_lme_augment_predict0 <- DBI::dbReadTable(conn, name = "network_lme_augment_predict") %>% as_tibble() %>% select(-db_network_etag)
network_lme_augment_disaggregated0 <- DBI::dbReadTable(conn, name = "network_lme_augment_disaggregated") %>% as_tibble()
repeldata::repel_remote_disconnect()

# Focus on OIE
oie_diseases <- repelpredict:::get_oie_high_importance_diseases()
names(oie_diseases) <- stri_trans_totitle(stri_replace_all_fixed(oie_diseases, "_", " "))

# Filter data for example cases
disease_select <- "highly_pathogenic_avian_influenza"
month_select <- "2018-07-01"

network_lme_augment_predict <-  network_lme_augment_predict0 %>%
  filter(disease == disease_select,
         month == month_select)

network_lme_augment_disaggregated <- network_lme_augment_disaggregated0 %>%
  filter(disease == disease_select,
         month == month_select)

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

basemap_probability <- left_join(admin, network_lme_augment_predict) ## for plotting risk of outbreak in countries without outbreats

basemap_status <- basemap_probability %>% ## for plotting if country already has outbreak, or if disease was never in country (which is currently NA for predicted risk)
  mutate(disease_country_combo_unreported = is.na(predicted_outbreak_probability)) %>%
  mutate(reported_outbreak = endemic|outbreak_subsequent_month|outbreak_start) %>%
  mutate(reported_outbreak = replace_na(reported_outbreak, FALSE)) %>%
  filter(disease_country_combo_unreported | reported_outbreak) %>%
  mutate(cat_status = if_else(disease_country_combo_unreported, "Disease never in country", "Current Outbreak"))

# for import/exports, first id countries with current outbreaks
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
  group_by(country_iso3c, disease, month, country_origin) %>% ## summarizing relative importance over variables, by country import/export combo
  summarize(country_rel_import = sum(rel_import)) %>%
  ungroup()

country_import_weights <- country_trade_disagg %>%
  left_join(country_outbreaks,  by = c("country_iso3c", "disease", "month")) %>%
  filter(is.na(cat_status)) %>%
  select(-cat_status) %>%
  arrange(country_iso3c, -country_rel_import) ## country_iso3c is the country with a given probability of disease arrival, country_origin is the country that has the disease and is exporting to country_iso3c

country_export_weights <- country_trade_disagg %>% ## country_origin is the country that is contributing (exporting) risk
  arrange(country_origin, -country_rel_import)

# Get overall variable importance for each country (dot plot)
var_importance <- network_lme_augment_predict %>%
  pivot_longer(cols = c("shared_borders_from_outbreaks", "ots_trade_dollars_from_outbreaks", "fao_livestock_heads_from_outbreaks"),
               names_to = "variable", values_to = "value") %>%
  select(-outbreak_start) %>%
  left_join(randef_disease) %>%
  mutate(variable_importance = value * coef) %>%
  mutate(pos = variable_importance > 0) %>%
  mutate(country_name = countrycode::countrycode(country_iso3c, origin = "iso3c", destination = "country.name")) %>%
  mutate(disease_name = stri_trans_totitle(stri_replace_all_fixed(disease, "_", " "))) %>%
  mutate(variable = stri_trans_totitle(stri_replace_all_fixed(variable, "_", " ")))

# generate dot plots
dot_plots <- var_importance %>%
  filter(country_iso3c %in% c("DEU", "IRN", "USA")) %>%  # example countries
  mutate(variable = recode(variable, "Shared Borders From Outbreaks" = "Border Contact", "Ots Trade Dollars From Outbreaks" = "Economic Trade",
                             "Fao Livestock Heads From Outbreaks" = "Livestock Imports")) %>%
  group_split(country_iso3c, disease, month) %>%
  map(., function(df){

    country_name <- unique(df$country_name)
    month <- unique(df$month)
    disease_name <- unique(df$disease_name)
    outbreak_prob <- paste0(100 *  signif(unique(df$predicted_outbreak_probability), 2) , "%")

    ggplot(df) +
      geom_vline(aes(xintercept = 0), color = "gray50") +
      geom_point(aes(x = variable_importance, y = variable, color = pos), size = 2) +
      geom_segment(aes(x = variable_importance, xend = 0, y = variable, yend = variable, color = pos)) +
      scale_color_manual(values = c("TRUE" = "#0072B2", "FALSE" = "#D55E00")) +
      labs(y = "", x = "Variable importance", title = glue::glue("{month} {disease_name} outbreak probability in {country_name}: {outbreak_prob}")) +
      theme_minimal() +
      theme(text = element_text(family = "Avenir Medium"),
            legend.position = "none",
            axis.text = element_text(size = 15),
            axis.title = element_text(size = 16),
            title = element_text(size = 17),
            plot.title.position = "plot") +
      NULL
  })
dot_plots[[1]]

dot_plots[[2]]
# Leaflet
probability_pal <- colorNumeric(palette = "viridis", domain =  c(0,1), na.color = "000000")
status_pal <- colorFactor(palette = c("#a83434", "#7f7f7f"),
                          levels = sort(unique(basemap_status$cat_status)))
# leaflet() %>%
#   addProviderTiles("CartoDB.DarkMatter") %>%
#   setView(lng = 30, lat = 30, zoom = 1.5) %>%
#   addPolygons(data = basemap_probability, weight = 0.5, smoothFactor = 0.5,
#               opacity = 0.2, color = "white",
#               fillOpacity = 0.75, fillColor = ~sqrt(probability_pal(predicted_outbreak_probability)),
#               layerId = ~country_iso3c) %>%
#   addPolygons(data = basemap_status, weight = 0.5, smoothFactor = 0.5,
#               opacity = 0.2, color = "white",
#               fillOpacity = 1, fillColor = ~status_pal(cat_status)) %>%
#   addLegend_decreasing(pal = probability_pal, values = sqrt(na.omit(basemap_probability$predicted_outbreak_probability)),
#                        position = "bottomright", decreasing = TRUE, title = "Predicted outbreak probability") %>%
#   addLegend_decreasing(pal = status_pal, values = unique(basemap_status$cat_status),opacity = 0.8,
#                        position = "bottomright", decreasing = FALSE, title = "")

admin_centers <- admin %>%
  mutate(geometry = sf::st_centroid(geometry)) # fix for exact centroids

country_select = "IRN"
arc_data <- country_import_weights %>%
  filter(disease == disease_select,
         country_iso3c == country_select,
         month == month_select,
         country_rel_import > 0) %>%
  arrange(desc(country_rel_import)) %>%
  rename(country_destination = country_iso3c) %>%
  left_join(select(admin_centers, country_destination = country_iso3c, destination = geometry)) %>%
  left_join(select(admin_centers, country_origin = country_iso3c, origin = geometry)) %>%
  st_as_sf()

import_pal <- colorNumeric(palette = "inferno", domain =  na.omit(arc_data$country_rel_import), na.color = "#000000")
arc_data <- arc_data %>%
  mutate(arc_col = import_pal(country_rel_import))

basemap_probability <- basemap_probability %>%
  left_join(as_tibble(basemap_status) %>% select(country_iso3c, cat_status)) %>%
  mutate(prob_col = probability_pal(sqrt(predicted_outbreak_probability)),
         status_col = status_pal(cat_status),
         fill_col = if_else(cat_status %in% "Current Outbreak", status_col, prob_col))

import_pal <- colorNumeric(palette = "inferno", domain =  na.omit(arc_data$country_rel_import), na.color = "#000000")
arc_col = viridis::inferno(5)[4]
md <- mapdeck(
  style = mapdeck_style("dark"),
  pitch = 30
) %>%
  add_polygon(data = basemap_probability,
              id = "outbreak_prob",
              stroke_colour = "#FFFFFF",
              stroke_opacity = 0.2,
              stroke_width = 10000,
              fill_colour = "fill_col",
              legend = mapdeck_legend(
                legend_element(
                  title = "Outbreak Probability",
                  variables = rev(0:5/5),
                  colours = rev(probability_pal(sqrt(0:5/5))),
                  colour_type = "fill",
                  variable_type = "category"
                )
              )) %>%
  add_arc(data = arc_data, origin = "origin", destination = "destination", stroke_from = arc_col, stroke_to = arc_col, layer_id ="arcs", stroke_width = 10,
          height = 0.1)
md
