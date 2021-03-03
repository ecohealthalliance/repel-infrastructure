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

conn <- repeldata::repel_remote_conn(
    host = "postgres",
    port = 5432,
    user = "repel_reader",
    password = Sys.getenv("REPEL_READER_PASS")
)


#conn <- repeldata::repel_remote_conn()

nowcast_predict <- tbl(conn, "nowcast_boost_augment_predict")  %>%
    collect()

# Define UI for application that draws a histogram
ui <- fluidPage(

    # Application title
    titlePanel("REPEL Nowcast"),

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
    sidebarLayout(
        sidebarPanel(
            sliderInput("bins",
                        "Number of bins:",
                        min = 1,
                        max = 50,
                        value = 30)
        ),

        # Show a plot of the generated distribution
        mainPanel(
           plotOutput("distPlot")
        )
    )
)

# Define server logic required to draw a histogram
server <- function(input, output) {

    output$distPlot <- renderPlot({
        # generate bins based on input$bins from ui.R
        x    <- nowcast_predict$predicted_cases
        #x <- rnorm(100)
        bins <- seq(min(x), max(x), length.out = input$bins + 1)

        # draw the histogram with the specified number of bins
        hist(x, breaks = bins, col = 'darkgray', border = 'white')
    })
}

# Run the application
shinyApp(ui = ui, server = server)
