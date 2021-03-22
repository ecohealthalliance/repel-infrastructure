#
# This is a Shiny web application. You can run the application by clicking
# the 'Run App' button above.
#
# Find out more about building applications with Shiny here:
#
#    http://shiny.rstudio.com/
#

library(shiny)
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

admin <- ne_countries(type='countries', scale = 'medium', returnclass = "sf") %>%
    filter(name != "Antarctica") %>%
    select(country_iso3c = iso_a3, geometry)

# conn <- repeldata::repel_remote_conn(
#     host = "localhost",
#     port = 22053,
#     user = "repel_reader",
#     password = "yellow555zephyr222camera"
# )

nowcast_predicted_sum <- read_csv(here::here("shiny", "content", "nowcast", "data", "nowcast_predicted_sum.csv")) %>%
    mutate(status_coalesced = factor(status_coalesced, levels = c("reported present", "unreported, predicted present",  "reported absent", "unreported, predicted absent")))

pal <- colorFactor(palette = c("#E31A1C", "#FB9A99", "#1F78B4", "#A6CEE3"), domain = levels(nowcast_predicted_sum$status_coalesced))

oie_diseases <- repelpredict:::get_oie_high_importance_diseases()
names(oie_diseases) <- stri_trans_totitle(stri_replace_all_fixed(oie_diseases, "_", " "))

plots <- read_rds(here::here("shiny", "content", "nowcast", "data", "plots.rds"))

ui <- navbarPage("REPEL Nowcast", id="nav",

                 tabPanel("Interactive map",
                          div(class="outer",

                              tags$head(
                                  # Include custom CSS from https://github.com/rstudio/shiny-examples/tree/master/063-superzip-example
                                  includeCSS("styles.css"),
                                  includeScript("gomap.js")
                              ),

                              # If not using custom CSS, set height of leafletOutput to a number instead of percent
                              leafletOutput("map", width="100%", height="100%"),

                              # Shiny versions prior to 0.11 should use class = "modal" instead.
                              absolutePanel(id = "controls", class = "panel panel-default", fixed = TRUE,
                                            draggable = TRUE, top = 60, left = "auto", right = 20, bottom = "auto",
                                            width = 330, height = "auto",

                                            h2("Nowcast explorer"),

                                            selectInput(inputId = "select_disease", label = "Select OIE disease", choices = oie_diseases),
                                            sliderInput(inputId = "select_year", label = "Select year", min = min(nowcast_predicted_sum$report_year), max = max(nowcast_predicted_sum$report_year), value = 2019, sep = ""),
                                            radioButtons(inputId = "select_semester", label = "Select semester", choices = c("Jan - June", "July - Dec"), inline = TRUE)
                              )
                          )
                 ),

                 tabPanel("Time series", girafeOutput("timeseries_plot"))

)


server <- function(input, output) {

    # try with interactive graphs now
    # maybe observe events and renedering on fly is faster?


    output$map <- renderLeaflet({
        select_semester <- switch(input$select_semester, "Jan - June" = 1, "July - Dec" = 2)

        mapdat <- nowcast_predicted_sum %>%
        filter(disease == input$select_disease, report_year == input$select_year, report_semester == select_semester) #%>%
    #   filter(disease == oie_diseases[[1]], report_year == 2019, report_semester == 1)

        admin_mapdat <- admin %>%
            right_join(mapdat) %>%
            left_join(tibble(fill_color = c("#E31A1C", "#FB9A99", "#1F78B4", "#A6CEE3"), status_coalesced =  levels(nowcast_predicted_sum$status_coalesced)))

        plot_labs <-   mapdat %>%
            select(disease, country_iso3c) %>%
            mutate(lab = paste(disease, country_iso3c, sep = "_")) %>%
            pull(lab)
        p_all <- plots[plot_labs]

        leaflet() %>%
            addProviderTiles("CartoDB.DarkMatter") %>%
            setView(lng = 30, lat = 30, zoom = 2) %>%
            addPolygons(data = admin_mapdat, weight = 0.5, smoothFactor = 0.5,
                        opacity = 0.5,  color = ~fill_color,
                        fillOpacity = 0.75, fillColor = ~fill_color,
                        label = ~tooltip_lab,
                        layerId = ~country_iso3c,
                      popup = popupGraph(p_all, type = "svg")# prerender popup? - as svg files, save to static path, popup html per ny leaflet
               #        group = "polygons"
                        ) %>%
           # addPopupGraphs(p_all, group = 'polygons') %>%
            addLegend(pal = pal, values = levels(nowcast_predicted_sum$status_coalesced), position = "bottomright",
                      labFormat = labelFormat(transform = function(x) levels(nowcast_predicted_sum$status_coalesced)))
    })

    observeEvent(input$map_shape_click, {
        cat("Country: ", input$map_shape_click$id, "\n")
    })

    timeseries_country <- eventReactive(input$map_shape_click, {
        filter(nowcast_predicted_sum, disease == input$select_disease, country_iso3c == input$map_shape_click$id)
    })

    output$timeseries_plot <- renderGirafe({
        nowcast_timeline_plot(timeseries_country())
    })





}
# User options: Select Disease
# Map: showing currently reported, not currently reported/predicted
#  - 4 color, or maybe color + hatched in future iteration
#  - Slider to change time point?
# Map: Predicted in six months
#  Use leaflet with no base to start
# Shiny: Click on a country, get a time series
# Time series plot(s):
#  - Show presence, cases reported and predicted (emphasize gaps!)
#  - Hover to show values
#  -

#                        popup = popupGraph(p, type = "svg")) %>%

shinyApp(ui = ui, server = server)
