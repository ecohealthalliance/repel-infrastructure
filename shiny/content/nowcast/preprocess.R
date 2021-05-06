#!/usr/bin/env Rscript

library(tidyverse)
library(furrr)
library(RColorBrewer)
library(ggiraph)
library(stringi)
library(patchwork)
library(DBI)
library(glue)
library(ggiraph)
library(brew)
library(countrycode)

# repeldata::repel_local_download()
conn <- repeldata::repel_remote_conn()

nowcast_predicted_sum <- dbReadTable(conn, name = "nowcast_boost_predict_oie_diseases") %>%
  mutate(status_coalesced = factor(status_coalesced, levels = c("reported present", "unreported, predicted present",  "reported absent", "unreported, predicted absent")))

repeldata::repel_remote_disconnect()

# get other countries on map
admin <- rnaturalearth::ne_countries(type='countries', scale = 'small', returnclass = "sf") %>%
  filter(name != "Antarctica") %>%
  pull(iso_a3) %>%
  unique()

countries_to_add <- setdiff(na.omit(admin), unique(nowcast_predicted_sum$country_iso3c))

pred_df <- nowcast_predicted_sum %>%
  bind_rows(
    expand_grid(country_iso3c = countries_to_add,
                report_year = unique(nowcast_predicted_sum$report_year),
                report_semester = unique(nowcast_predicted_sum$report_semester),
                disease = unique(nowcast_predicted_sum$disease),
                predicted_cases = 0,
                predicted_status = FALSE,
                unreported = TRUE,
                status_coalesced = "unreported, predicted absent")
  ) %>%
  mutate(yr = report_year + (report_semester - 1)/2) %>%
  mutate(country_name = countrycode::countrycode(country_iso3c, origin = "iso3c", destination = "country.name")) %>%
  mutate(disease_clean = stri_trans_totitle(stri_replace_all_fixed(disease, "_", " "))) %>%
  mutate(cases_coalesced = coalesce(actual_cases, predicted_cases)) %>%
  mutate(label = paste0("Reported cases = ", replace_na(actual_cases, "missing"), "<br/>Predicted cases = ", predicted_cases)) %>%
  arrange(disease, country_iso3c) %>%
  group_by(country_iso3c, disease) %>%
  mutate(status_coalesced = if_else(rep(all(predicted_cases == 0) & all(cases_coalesced == 0), n()), rep("never reported or predicted", n()), status_coalesced)) %>%
  ungroup()

write_csv(pred_df, here::here("shiny", "content", "nowcast", "data", "nowcast_predicted_sum.csv"))

cases_df_split <- pred_df  %>%
  group_split(disease, country_iso3c)

presence_df_split <- pred_df  %>%
  select(disease, country_iso3c, yr, Predicted = predicted_status, Reported = actual_status) %>%
  pivot_longer(cols = c("Predicted", "Reported"), names_to = "type") %>%
  mutate(missing = factor(if_else(value, "Present", "Absent", "Missing"), levels = c("Missing", "Present", "Absent"))) %>%
  select(-value) %>%
  group_split(disease, country_iso3c)

breaks_by <- function(k) {
  step <- k
  function(y) seq(floor(min(y)), ceiling(max(y)), by = step)
}

walk2(cases_df_split, presence_df_split, function(cases_df, presence_df){

  if (!all(cases_df$predicted_cases == 0 & cases_df$cases_coalesced == 0)) {
#browser()
  cases_plot <- ggplot(cases_df, aes(x = yr, y = cases_coalesced, fill = status_coalesced, color = status_coalesced)) +
    #geom_line() +
    geom_point_interactive(mapping = aes(tooltip = label, fill = status_coalesced, color = status_coalesced), pch = 21, size = 4) +
    scale_color_manual(values = c("reported present" = "#E31A1C", "unreported, predicted present" = "#FB9A99",
                                  "reported absent" = "#1F78B4", "unreported, predicted absent" = "#A6CEE3")) +
    scale_fill_manual(values = c("reported present" = "#E31A1C", "unreported, predicted present" = "#FB9A99",
                                 "reported absent" = "#1F78B4", "unreported, predicted absent" = "#A6CEE3")) +
    labs(title = paste(unique(cases_df$country_name), unique(cases_df$disease_clean), sep = ": "),
         y = "Cases", fill = "", color = "") +
    theme_minimal() +
    theme(axis.text.x = element_blank(), axis.title.x = element_blank())

  presence_plot <- ggplot(presence_df, aes(x = yr, y = type, fill = missing)) +
    geom_tile(color = "white") +
    scale_x_continuous(breaks = breaks_by(1)) +
    scale_fill_manual(values = c(Present = "#E31A1C", Absent = "#1F78B4", Missing = "#FFFFFF")) +
    labs(fill = "", color = "") +
    theme_minimal() +
    theme(axis.title.x = element_blank(), panel.grid = element_blank(), axis.title.y = element_blank(), axis.text.x = element_text(angle = 45, , vjust = 0.5, hjust=1))

  widget <- girafe(ggobj = cases_plot + presence_plot + plot_layout(ncol = 1, heights = c(0.9, 0.1)),
         width_svg = 9, height_svg = 3.6)

  widget_filename = paste0(unique(cases_df$disease), "_", unique(cases_df$country_iso3c), ".html")
  plotdir = here::here("shiny", "content", "nowcast", "www", "girafes")
  htmlwidgets::saveWidget(widget, file.path(plotdir, widget_filename), selfcontained = FALSE, libdir = plotdir)
  }
})




