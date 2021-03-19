nowcast_timeline_plot <- function(nowcast_predict_df) {

  pred_df <- nowcast_predict_df %>%
    mutate(yr = report_year + (report_semester - 1)/2) %>%
    select(yr, actual_cases, predicted_cases) %>%
    rename(Reported = actual_cases, Predicted = predicted_cases) %>%
    pivot_longer(-yr, names_to = "type", values_to = "cases") %>%
    mutate(presence = cases > 0 | is.na(cases)) %>%
    mutate(missing = factor(case_when(is.na(cases) ~ "Missing", cases > 0 ~ "Present", cases == 0 ~ "Absent"), levels = c("Missing", "Present", "Absent"))) %>%
    mutate(cases = coalesce(cases, 0)) %>%
    group_by(yr) %>%
    mutate(label = glue("Reported: ", if_else(missing[type == "Reported"] == "Missing", "Unknown", as.character(cases[type == "Reported"])), "<br/>Predicted: ", cases[type == "Predicted"])) %>%
    ungroup()

  breaks_by <- function(k) {
    step <- k
    function(y) seq(floor(min(y)), ceiling(max(y)), by = step)
  }

  cases_plot <- ggplot(pred_df, aes(x = yr, y = cases, color = paste0(type, presence))) +
    geom_line() +
    geom_point_interactive(mapping = aes(tooltip = label, fill = missing), pch = 21) +
  #  scale_color_manual(values = c(PredictedFALSE = "#FB9A99", ))
    theme_minimal() +
    theme(axis.text.x = element_blank(), axis.title.x = element_blank())

  presence_plot <- ggplot(pred_df, aes(x = yr, y = type, fill = missing)) +
    geom_tile(color = "white") +
    scale_x_continuous(breaks = breaks_by(1)) +
    scale_fill_manual(values = c(Present = "#E31A1C", Absent = "#1F78B4", Missing = "#FFFFFF")) +
    theme_minimal() +
    theme(axis.title.x = element_blank(), panel.grid = element_blank(), axis.title.y = element_blank())
  girafe(ggobj = cases_plot + presence_plot + plot_layout(ncol = 1, heights = c(0.9, 0.1)),
         width_svg = 10, height_svg = 4)

}
