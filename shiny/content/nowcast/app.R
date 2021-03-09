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
library(rnaturalearthdata)
library(leaflet)

admin <- ne_countries(type='countries', scale = 'medium', returnclass = "sf") %>%
    filter(name != "Antarctica") %>%
    select(country_iso3c = iso_a3, geometry)

nowcast_predicted_sum <- read_csv(here::here("shiny", "content", "nowcast", "data", "nowcast_predicted_sum.csv"))

oie_diseases <- repelpredict:::get_oie_high_importance_diseases()

# bring in render map

ui <- fluidPage(
    navbarPage("REPEL Nowcast", id="main",
                 tabPanel("Map",
                          # dropdown
                          selectInput(inputId = "select_disease", label = "Select OIE disease", choices = oie_diseases),
                          sliderInput(inputId = "select_year", label = "Select year", min = min(nowcast_predicted_sum$report_year), max = max(nowcast_predicted_sum$report_year), value = 2019, sep = ""),
                          radioButtons(inputId = "select_semester", label = "Select semester", choices = c("Jan - June", "July - Dec"), inline = TRUE),
                          leafletOutput(outputId = "diseasemap", height=1000)),
                 tabPanel("Time series", plotOutput("data")))
)

server <- function(input, output) {

    output$diseasemap <- renderLeaflet({
        mapdat <- nowcast_predicted_sum %>%
            filter(disease == input$select_disease, report_year == input$select_year, report_semester == input$select_semester) %>%
            left_join(admin)
        pal <- colorFactor(palette = c("#E31A1C", "#FB9A99", "#1F78B4", "#A6CEE3"), domain = levels(mapdat$status_coalesced))

        leaflet() %>%
            addProviderTiles("CartoDB.DarkMatter") %>%
            addPolygons(data = mapdat, weight = 0.5, smoothFactor = 0.5,
                        opacity = 0.5,  color = ~fill,
                        fillOpacity = 0.75, fillColor = ~fill,
                        label = ~tooltip_lab) %>%
            addLegend(pal = pal, values = levels(mapdat$status_coalesced), position = "bottomright",
                      labFormat = labelFormat(transform = function(x) levels(mapdat$status_coalesced)))
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
shinyApp(ui = ui, server = server)
