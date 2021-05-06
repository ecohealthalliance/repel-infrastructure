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


nowcast_plot_html_string <- function (graphs, width = 300, height = 300,
                                      popTemplate = "popup-graph-mod.brew", ...)
{
  lapply(1:length(graphs), function(i) {
    inch_wdth = width/72
    inch_hght = height/72
    lns <- svglite::svgstring(width = inch_wdth, height = inch_hght,
                              standalone = FALSE)
    print(graphs[[i]])
    dev.off()
    svg_str <- lns()
    svg_id <- paste0("x", uuid::UUIDgenerate())
    svg_str <- gsub(x = svg_str, pattern = "<svg ", replacement = sprintf("<svg id='%s'",
                                                                          svg_id))
    svg_css_rule <- sprintf("#%1$s line, #%1$s polyline, #%1$s polygon, #%1$s path, #%1$s rect, #%1$s circle {",
                            svg_id)
    svg_str <- gsub(x = svg_str, pattern = "line, polyline, polygon, path, rect, circle \\{",
                    replacement = svg_css_rule)
    pop = sprintf("<div style='width: %dpx; height: %dpx;'>%s</div>",
                  width, height, svg_str)
    # popTemplate = system.file("templates/popup-graph.brew",
    #                           package = "leafpop")
    myCon = textConnection("outputObj", open = "w")
    brew::brew(popTemplate, output = myCon)
    outputObj = outputObj
    close(myCon)
    return(paste(outputObj, collapse = " "))
  })
}




# from https://stackoverflow.com/questions/40276569/reverse-order-in-r-leaflet-continuous-legend
addLegend_decreasing <- function (map, position = c("topright", "bottomright", "bottomleft","topleft"),
                                  pal, values, na.label = "NA", bins = 7, colors,
                                  opacity = 0.5, labels = NULL, labFormat = labelFormat(),
                                  title = NULL, className = "info legend", layerId = NULL,
                                  group = NULL, data = getMapData(map), decreasing = FALSE) {

  position <- match.arg(position)
  type <- "unknown"
  na.color <- NULL
  extra <- NULL
  if (!missing(pal)) {
    if (!missing(colors))
      stop("You must provide either 'pal' or 'colors' (not both)")
    if (missing(title) && inherits(values, "formula"))
      title <- deparse(values[[2]])
    values <- evalFormula(values, data)
    type <- attr(pal, "colorType", exact = TRUE)
    args <- attr(pal, "colorArgs", exact = TRUE)
    na.color <- args$na.color
    if (!is.null(na.color) && col2rgb(na.color, alpha = TRUE)[[4]] ==
        0) {
      na.color <- NULL
    }
    if (type != "numeric" && !missing(bins))
      warning("'bins' is ignored because the palette type is not numeric")
    if (type == "numeric") {
      cuts <- if (length(bins) == 1)
        pretty(values, bins)
      else bins
      if (length(bins) > 2)
        if (!all(abs(diff(bins, differences = 2)) <=
                 sqrt(.Machine$double.eps)))
          stop("The vector of breaks 'bins' must be equally spaced")
      n <- length(cuts)
      r <- range(values, na.rm = TRUE)
      cuts <- cuts[cuts >= r[1] & cuts <= r[2]]
      n <- length(cuts)
      p <- (cuts - r[1])/(r[2] - r[1])
      extra <- list(p_1 = p[1], p_n = p[n])
      p <- c("", paste0(100 * p, "%"), "")
      if (decreasing == TRUE){
        colors <- pal(rev(c(r[1], cuts, r[2])))
        labels <- rev(labFormat(type = "numeric", cuts))
      }else{
        colors <- pal(c(r[1], cuts, r[2]))
        labels <- rev(labFormat(type = "numeric", cuts))
      }
      colors <- paste(colors, p, sep = " ", collapse = ", ")
    }
    else if (type == "bin") {
      cuts <- args$bins
      n <- length(cuts)
      mids <- (cuts[-1] + cuts[-n])/2
      if (decreasing == TRUE){
        colors <- pal(rev(mids))
        labels <- rev(labFormat(type = "bin", cuts))
      }else{
        colors <- pal(mids)
        labels <- labFormat(type = "bin", cuts)
      }
    }
    else if (type == "quantile") {
      p <- args$probs
      n <- length(p)
      cuts <- quantile(values, probs = p, na.rm = TRUE)
      mids <- quantile(values, probs = (p[-1] + p[-n])/2, na.rm = TRUE)
      if (decreasing == TRUE){
        colors <- pal(rev(mids))
        labels <- rev(labFormat(type = "quantile", cuts, p))
      }else{
        colors <- pal(mids)
        labels <- labFormat(type = "quantile", cuts, p)
      }
    }
    else if (type == "factor") {
      v <- sort(unique(na.omit(values)))
      colors <- pal(v)
      labels <- labFormat(type = "factor", v)
      if (decreasing == TRUE){
        colors <- pal(rev(v))
        labels <- rev(labFormat(type = "factor", v))
      }else{
        colors <- pal(v)
        labels <- labFormat(type = "factor", v)
      }
    }
    else stop("Palette function not supported")
    if (!any(is.na(values)))
      na.color <- NULL
  }
  else {
    if (length(colors) != length(labels))
      stop("'colors' and 'labels' must be of the same length")
  }
  legend <- list(colors = I(unname(colors)), labels = I(unname(labels)),
                 na_color = na.color, na_label = na.label, opacity = opacity,
                 position = position, type = type, title = title, extra = extra,
                 layerId = layerId, className = className, group = group)
  invokeMethod(map, data, "addLegend", legend)
}

