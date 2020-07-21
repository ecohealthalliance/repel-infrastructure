# This script downloads and processes country-specifc data

source(here::here("packages.R"))
source(here::here("functions.R"))

wb <- wahis::get_wb_indicators(indicators_list =
                                 list(gdp_dollars = "NY.GDP.MKTP.CD",
                                      human_population = "SP.POP.TOTL"))


download_taxa_population()
taxa <- transform_taxa_population()

# taxa %>%
#   mutate(taxa = paste0(taxa, "_population")) %>%
#   pivot_wider(names_from = taxa, values_from = population)

# Add to db ---------------------------------------------------------------
conn <- wahis_db_connect()

dbWriteTable(conn,  name = "worldbank_indicators", value = wb, overwrite = TRUE)
dbWriteTable(conn,  name = "country_taxa_population", value = taxa, overwrite = TRUE)

dbDisconnect(conn)
