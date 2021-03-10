nowcast_timeline_plot <- function(dis = "classical_swine_fever", iso3c = "CHN" , nowcast_predict_df) {

  pred_df <- filter(nowcast_predict_df, .data$disease == dis, .data$country_iso3c == iso3c) %>%
    mutate(yr = report_year + (report_semester - 1)/2) %>%
    select(yr, cases, predicted_cases) %>%
    rename(observed = cases, predicted = predicted_cases) %>%
    pivot_longer(-yr, names_to = "type", values_to = "cases") %>%
    mutate(presence = cases > 0 | is.na(cases)) %>%
    mutate(missing = case_when(is.na(cases) ~ "missing", cases > 0 ~ "positive", cases == 0 ~ "zero")) %>%
    mutate(cases = coalesce(cases, 0)) %>%
    group_by(yr) %>%
    mutate(label = glue("Observed: ", if_else(missing[type == "observed"] == "missing", "Unknown", as.character(cases[type == "observed"])), "<br/>Predicted: ", cases[type == "predicted"])) %>%
    ungroup()

  breaks_by <- function(k) {
    step <- k
    function(y) seq(floor(min(y)), ceiling(max(y)), by = step)
  }

  cases_plot <- ggplot(pred_df, aes(x = yr, y = cases, color = type)) +
    geom_line() +
    geom_point_interactive(mapping = aes(tooltip = label, fill = missing), pch = 21) +
    theme_minimal() +
    theme(axis.text.x = element_blank(), axis.title.x = element_blank())

  presence_plot <- ggplot(pred_df, aes(x = yr, y = type, fill = missing)) +
    geom_tile(color = "white") +
    scale_x_continuous(breaks = breaks_by(1)) +
    theme_minimal() +
    theme(axis.title.x = element_blank())
  girafe(ggobj = cases_plot + presence_plot + plot_layout(ncol = 1, heights = c(0.9, 0.1)),
         width_svg = 10, height_svg = 4)

}
