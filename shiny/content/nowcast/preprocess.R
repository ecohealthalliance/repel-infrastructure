library(tidyverse)
library(furrr)
library(rnaturalearth)
library(sf)
library(RColorBrewer)
library(glue)

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

#TODO put into db
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
                              ":<br>",
                              if_else(unreported, paste0(" ", cases_coalesced, " predicted cases"), paste0(" ", cases_coalesced, " reported cases"))
  ))

write_csv(nowcast_predicted_sum, here::here("shiny", "content", "nowcast", "data", "nowcast_predicted_sum.csv"))

# pre generate plots

pred_list <- nowcast_predicted_sum %>%
  mutate(yr = report_year + (report_semester - 1)/2) %>%
  select(disease, country_iso3c, yr, cases_coalesced, status_coalesced) %>%
  mutate(label = cases_coalesced) %>% #glue("Reported: ", if_else(missing[type == "Reported"] == "Missing", "Unknown", as.character(cases[type == "Reported"])), "<br/>Predicted: ", cases[type == "Predicted"])) %>%
  arrange(disease, country_iso3c) %>%
  group_split(disease, country_iso3c)


breaks_by <- function(k) {
  step <- k
  function(y) seq(floor(min(y)), ceiling(max(y)), by = step)
}


plots <- map(pred_list, function(z){

 cases_plot <- ggplot(z, aes(x = yr, y = cases_coalesced, color = status_coalesced)) +
    geom_line() +
    geom_point_interactive(mapping = aes(tooltip = label, fill = status_coalesced), pch = 21) +
    labs(title = paste(unique(z$disease), unique(z$country_iso3c), sep = "_")) + # tmp
    theme_minimal() +
    theme(axis.text.x = element_blank(), axis.title.x = element_blank())

  # presence_plot <- ggplot(z, aes(x = yr, y = type, fill = missing)) +
  #   geom_tile(color = "white") +
  #   scale_x_continuous(breaks = breaks_by(1)) +
  #   scale_fill_manual(values = c(Present = "#E31A1C", Absent = "#1F78B4", Missing = "#FFFFFF")) +
  #   theme_minimal() +
  #   theme(axis.title.x = element_blank(), panel.grid = element_blank(), axis.title.y = element_blank())

 girafe(ggobj = cases_plot, #+ presence_plot + plot_layout(ncol = 1, heights = c(0.9, 0.1)),
        width_svg = 10, height_svg = 4)
})


labs <- nowcast_predicted_sum %>%
  arrange(disease, country_iso3c) %>%
  distinct(disease, country_iso3c) %>%
  mutate(lab = paste(disease, country_iso3c, sep = "_")) %>%
  pull(lab)

names(plots) <- labs

write_rds(plots,  here::here("shiny", "content", "nowcast", "data", "plots.rds"))




# girafe(ggobj = cases_plot + presence_plot + plot_layout(ncol = 1, heights = c(0.9, 0.1)),
#        width_svg = 10, height_svg = 4)








repeldata::repel_remote_disconnect()

 -
