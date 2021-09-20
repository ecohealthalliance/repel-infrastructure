# This script downloads and processes country-specific data (non-connect)

dir <- ifelse(basename(getwd())=="repel-infrastructure", "scraper", "")
source(here::here(dir, "packages.R"))
purrr::walk(list.files(here::here(dir, "R"), full.names = TRUE), source)
dir_downloads <- paste(dir, "data-raw", sep = "/")

# Connect to database ----------------------------
message("Connect to database")
hl <- ifelse(dir == "scraper", "reservoir", "remote")
conn <- wahis_db_connect(host_location = hl)

# Get full table of all country and year combinations -------------------------------------------------------------------------
all_countries <- ggplot2::map_data("world") %>%
  as_tibble() %>%
  mutate(iso3c = countrycode::countrycode(sourcevar = region,
                                          origin = "country.name",
                                          destination = "iso3c"))  %>%
  distinct(iso3c) %>%
  drop_na(iso3c) %>%
  bind_rows(tibble(iso3c = "HKG"))

current_year <- lubridate::year(Sys.Date())
all_years <- tibble(year = seq(from = 2000, to = current_year)) # 2005 is when outbreak record keeping began, but go back farther to get imputation trends
all_countries_years <- all_countries %>%
  crossing(all_years) %>%
  rename(country_iso3c = iso3c)

# Get country indicators --------------------------------------------------
message("Get World Bank indicators")
wb <- wahis::get_wb_indicators(indicators_list =
                                 list(gdp_dollars = "NY.GDP.MKTP.CD",
                                      human_population = "SP.POP.TOTL"))

# expand for all country + year combos, run impute
gdp <- wb %>%
  select(country_iso3c, year, gdp_dollars) %>%
  right_join(all_countries_years, by = c("country_iso3c", "year")) %>%
  arrange(country_iso3c, year) %>%
  group_split(country_iso3c) %>%
  map_dfr(~na_interp(., "gdp_dollars")) %>%
  mutate(source = "WB")
write_csv(gdp, here(dir, "data-intermediate/wb-country-gdp.csv"))
dbWriteTable(conn,  name = "country_yearly_wb_gdp", value = gdp, overwrite = TRUE)

human_pop <- wb %>%
  select(country_iso3c, year, human_population) %>%
  right_join(all_countries_years, by = c("country_iso3c", "year")) %>%
  arrange(country_iso3c, year) %>%
  group_split(country_iso3c) %>%
  map_dfr(~na_interp(., "human_population")) %>%
  mutate(source = "WB")
write_csv(human_pop, here(dir, "data-intermediate/wb-country-human-population.csv"))
dbWriteTable(conn,  name = "country_yearly_wb_human_population", value = human_pop, overwrite = TRUE)

message("Get taxa population")
# expand for all country + year combos, run impute
download_taxa_population(directory = dir_downloads)
taxa <- transform_taxa_population(directory = dir_downloads) %>%
  mutate(taxa = ifelse(taxa %in% c("goats", "sheep"), "sheep/goats", taxa)) %>%
  group_by(country_iso3c, year, taxa) %>%
  summarize(population = sum(population, na.rm = TRUE)) %>%  # adds up all goats and sheep - should be done before imputation
  ungroup()

all_countries_years_taxa <- all_countries_years %>%
  crossing(tibble(taxa = unique(taxa$taxa)))

taxa <- taxa %>%
  right_join(all_countries_years_taxa, by = c("country_iso3c", "year", "taxa")) %>%
  arrange(country_iso3c, taxa, year) %>%
  group_split(country_iso3c, taxa) %>%
  map_dfr(~na_interp(., "population")) %>%
  mutate(source = "FAO")
write_csv(taxa, here(dir, "data-intermediate/fao-country-taxa-population.csv"))
dbWriteTable(conn,  name = "country_yearly_fao_taxa_population", value = taxa, overwrite = TRUE)

# grant permissions
grant_table_permissions(conn)

dbDisconnect(conn)
conn <- wahis_db_connect(host_location = hl)
