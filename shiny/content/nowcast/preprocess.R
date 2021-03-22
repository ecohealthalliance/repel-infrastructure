library(tidyverse)
library(furrr)
library(RColorBrewer)
library(ggiraph)
library(stringi)
library(patchwork)
library(DBI)


# repeldata::repel_local_download()
conn <- repeldata::repel_remote_conn()

nowcast_predicted_sum <- dbReadTable(conn, name = "nowcast_boost_predict_oie_diseases") %>%
  mutate(status_coalesced = factor(status_coalesced, levels = c("reported present", "unreported, predicted present",  "reported absent", "unreported, predicted absent")))

pred_list <- nowcast_predicted_sum %>%
  mutate(yr = report_year + (report_semester - 1)/2) %>%
  mutate(country_name = countrycode::countrycode(country_iso3c, origin = "iso3c", destination = "country.name")) %>%
  mutate(disease_clean = stri_trans_totitle(stri_replace_all_fixed(disease, "_", " "))) %>%
  mutate(cases_coalesced = coalesce(actual_cases, predicted_cases)) %>%
  mutate(label = paste0("Reported cases = ", replace_na(actual_cases, "missing"), "<br/>Predicted cases = ", predicted_cases)) %>%
  arrange(disease, country_iso3c) %>%
  group_split(disease, country_iso3c)


breaks_by <- function(k) {
  step <- k
  function(y) seq(floor(min(y)), ceiling(max(y)), by = step)
}


plots <- map(pred_list, function(z){

  cases_plot <- ggplot(z, aes(x = yr, y = cases_coalesced, fill = status_coalesced, color = status_coalesced)) +
  #  geom_line() +
    geom_point_interactive(mapping = aes(tooltip = label, fill = status_coalesced, color = status_coalesced), pch = 21, size = 4) +
    scale_color_manual(values = c("reported present" = "#E31A1C", "unreported, predicted present" = "#FB9A99",
                                  "reported absent" = "#1F78B4", "unreported, predicted absent" = "#A6CEE3")) +
    scale_fill_manual(values = c("reported present" = "#E31A1C", "unreported, predicted present" = "#FB9A99",
                                  "reported absent" = "#1F78B4", "unreported, predicted absent" = "#A6CEE3")) +
    labs(title = paste(unique(z$country_name), unique(z$disease_clean), sep = ": "),
         y = "Cases", fill = "", color = "") +
    theme_minimal() +
    theme(axis.text.x = element_blank(), axis.title.x = element_blank())

  zp <- z %>%
    select(yr, Predicted = predicted_status, Reported = actual_status) %>%
    pivot_longer(cols = c("Predicted", "Reported"), names_to = "type") %>%
    mutate(missing = factor(if_else(value, "Present", "Absent", "Missing"), levels = c("Missing", "Present", "Absent")))


  presence_plot <- ggplot(zp, aes(x = yr, y = type, fill = missing)) +
    geom_tile(color = "white") +
    scale_x_continuous(breaks = breaks_by(1)) +
    scale_fill_manual(values = c(Present = "#E31A1C", Absent = "#1F78B4", Missing = "#FFFFFF")) +
    labs(fill = "", color = "") +
    theme_minimal() +
    theme(axis.title.x = element_blank(), panel.grid = element_blank(), axis.title.y = element_blank())

  girafe(ggobj = cases_plot + presence_plot + plot_layout(ncol = 1, heights = c(0.9, 0.1)),
         width_svg = 10, height_svg = 4)
})


labs <- nowcast_predicted_sum %>%
  arrange(disease, country_iso3c) %>%
  distinct(disease, country_iso3c) %>%
  mutate(lab = paste(disease, country_iso3c, sep = "_")) %>%
  pull(lab)

names(plots) <- labs

write_rds(plots,  here::here("shiny", "content", "nowcast", "data", "plots.rds"))

repeldata::repel_remote_disconnect()
