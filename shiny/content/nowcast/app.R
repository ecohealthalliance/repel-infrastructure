#
# This is a Shiny web application. You can run the application by clicking
# the 'Run App' button above.
#
# Find out more about building applications with Shiny here:
#
#    http://shiny.rstudio.com/
#

library(shiny)
library(shinyWidgets)
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

# Database connect
# conn <- repeldata::repel_remote_conn(
#     host = "localhost",
#     port = 22053,
#     user = "repel_reader",
#     password = "yellow555zephyr222camera"
# )
conn <- repeldata::repel_remote_conn()

# OIE diseases
oie_diseases <- repelpredict:::get_oie_high_importance_diseases()
names(oie_diseases) <- stri_trans_totitle(stri_replace_all_fixed(oie_diseases, "_", " "))

# World map borders
admin <- ne_countries(type='countries', scale = 'medium', returnclass = "sf") %>%
    filter(name != "Antarctica") %>%
    select(country_iso3c = iso_a3, geometry)

# Load Nowcast and set map colors
nowcast_predicted_sum <- read_csv(here::here("shiny", "content", "nowcast", "data", "nowcast_predicted_sum.csv")) %>%
    mutate(status_coalesced = factor(status_coalesced, levels = c("reported present", "unreported, predicted present",  "reported absent", "unreported, predicted absent", "never reported or predicted"))) %>%
    mutate(popup_html = if_else(status_coalesced != "never reported or predicted",
                                glue('
        <div class="scrollableContainer">
            <table class="popup scrollable" id="popup">
            <iframe src="girafes/{disease}_{country_iso3c}.html" width="1000px" height="600px" frameborder="0"></iframe>
            </table>
            </div>
            '),
                                ""))

nowcast_pal <- colorFactor(palette = c("#E31A1C", "#FB9A99", "#1F78B4", "#A6CEE3", "#B8C2CF"), domain = levels(nowcast_predicted_sum$status_coalesced))

# Load Travelcast
network_lme_augment_predict <- DBI::dbReadTable(conn, name = "network_lme_augment_predict")
travelcast_pal <- colorNumeric(palette = "viridis", domain = network_lme_augment_predict$predicted_outbreak_probability)

# UI ----------------------------------------------------------------------
ui <- navbarPage("REPEL", id="nav",

                 tabPanel("Nowcast",
                          div(class="outer",

                              tags$head(
                                  # Include custom CSS from https://github.com/rstudio/shiny-examples/tree/master/063-superzip-example
                                  includeCSS("styles.css"),
                                  includeCSS("leaflet-popup.css"),
                                  includeScript("gomap.js")
                              ),

                              # If not using custom CSS, set height of leafletOutput to a number instead of percent
                              leafletOutput("nowcast_map", width="100%", height="100%"),

                              # Shiny versions prior to 0.11 should use class = "modal" instead.
                              absolutePanel(id = "nowcast_controls", class = "panel panel-default", fixed = TRUE,
                                            draggable = TRUE, top = 60, left = "auto", right = "20", bottom = "auto",
                                            width = 330, height = "auto",

                                            h2("Nowcast explorer"),

                                            selectInput(inputId = "nowcast_select_disease", label = "Select OIE disease", choices = oie_diseases),
                                            sliderInput(inputId = "nowcast_select_year", label = "Select year", min = min(nowcast_predicted_sum$report_year), max = max(nowcast_predicted_sum$report_year), value = 2019, sep = ""),
                                            radioButtons(inputId = "nowcast_select_semester", label = "Select semester", choices = c("Jan - June", "July - Dec"), inline = TRUE)
                              )
                          )
                 ),

                 tabPanel("Travelcast",
                          div(class="outer",

                              tags$head(
                                  # Include custom CSS from https://github.com/rstudio/shiny-examples/tree/master/063-superzip-example
                                  includeCSS("styles.css"),
                                  includeCSS("leaflet-popup.css"),
                                  includeScript("gomap.js")
                              ),

                              # If not using custom CSS, set height of leafletOutput to a number instead of percent
                              leafletOutput("travelcast_map", width="100%", height="100%"),

                              # Shiny versions prior to 0.11 should use class = "modal" instead.
                              absolutePanel(id = "travelcast_controls", class = "panel panel-default", fixed = TRUE,
                                            draggable = TRUE, top = 60, left = "auto", right = 20, bottom = "auto",
                                            width = 330, height = "auto",

                                            h2("Travelcast explorer"),

                                            selectInput(inputId = "travelcast_select_disease", label = "Select OIE disease", choices = oie_diseases),
                                            airDatepickerInput("travelcast_select_month",
                                                               label = "Select Month",
                                                               value = "2019-01-01",
                                                               maxDate = max(network_lme_augment_predict$month),
                                                               minDate = min(network_lme_augment_predict$month),
                                                               view = "months", #editing what the popup calendar shows when it opens
                                                               minView = "months", #making it not possible to go down to a "days" view and pick the wrong date
                                                               dateFormat = "yyyy-mm"
                                            )
                                            # sliderInput(inputId = "travelcast_select_year", label = "Select year", min = min(network_lme_augment_predict$year), max = max(network_lme_augment_predict$year), value = 2019, sep = ""),
                                            # sliderInput(inputId = "travelcast_select_month", label = "Select month", min = 1, max = 12, value = 1)
                              )
                          )
                 ),

                 tabPanel("About")

)

# Server ----------------------------------------------------------------------
server <- function(input, output) {

    output$nowcast_map <- renderLeaflet({
        nowcast_select_semester <- switch(input$nowcast_select_semester, "Jan - June" = 1, "July - Dec" = 2)

        mapdat <- nowcast_predicted_sum %>%
            #    filter(disease == input$nowcast_select_disease, report_year == input$nowcast_select_year, report_semester == nowcast_select_semester)
            filter(disease == oie_diseases[[1]], report_year == 2019, report_semester == 1)

        admin_mapdat <- admin %>%
            right_join(mapdat) %>%
            left_join(tibble(fill_color = c("#E31A1C", "#FB9A99", "#1F78B4", "#A6CEE3", "#B8C2CF"), status_coalesced =  levels(nowcast_predicted_sum$status_coalesced)))

        leaflet() %>%
            addProviderTiles("CartoDB.DarkMatter") %>%
            setView(lng = 30, lat = 30, zoom = 2) %>%
            addPolygons(data = admin_mapdat, weight = 0.5, smoothFactor = 0.5,
                        opacity = 0.5,  color = ~fill_color,
                        fillOpacity = 0.75, fillColor = ~fill_color,
                        label = ~label,
                        layerId = ~country_iso3c,
                        popup = ~popup_html,
            ) %>%
            addLegend(pal = nowcast_pal, values = levels(nowcast_predicted_sum$status_coalesced), position = "bottomright",
                      labFormat = labelFormat(transform = function(x) levels(nowcast_predicted_sum$status_coalesced)))
    })

    output$travelcast_map <- renderLeaflet({

        mapdat <- network_lme_augment_predict %>%
            #   filter(disease == input$travelcast_select_disease, month == input$travelcast_select_month)
            filter(disease == oie_diseases[[1]], month == "2018-02-01")

        admin_mapdat <- admin %>%
            right_join(mapdat)

        leaflet() %>%
            addProviderTiles("CartoDB.DarkMatter") %>%
            setView(lng = 30, lat = 30, zoom = 2) %>%
            addPolygons(data = admin_mapdat, weight = 0.5, smoothFactor = 0.5,
                        opacity = 0.5,  color = ~travelcast_pal(predicted_outbreak_probability),
                        fillOpacity = 0.75, fillColor = ~travelcast_pal(predicted_outbreak_probability),
                        # label = ~tooltip_lab,
                        layerId = ~country_iso3c
            ) %>%
            addLegend_decreasing(pal = travelcast_pal, values = network_lme_augment_predict$predicted_outbreak_probability,
                                 position = "bottomright", decreasing = TRUE, title = "Predicted outbreak probability")
    })

}

shinyApp(ui = ui, server = server)
