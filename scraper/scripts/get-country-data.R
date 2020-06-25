# This script downloads and processes country-specifc data

source(here::here("packages.R"))
source(here::here("functions.R"))

gdp <- wahis::get_country_gdp()

download_taxa_population()
taxa <- transform_taxa_population()

# taxa %>%
#   mutate(taxa = paste0(taxa, "_population")) %>%
#   pivot_wider(names_from = taxa, values_from = population)

# Add to db ---------------------------------------------------------------
conn <- wahis_db_connect()

dbWriteTable(conn,  name = "country_gdp", value = gdp, overwrite = TRUE)
dbWriteTable(conn,  name = "country_taxa_population", value = taxa, overwrite = TRUE)

dbDisconnect(conn)
