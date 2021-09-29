# This script downloads and processes connect (non-oie) yearly data

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
  bind_rows(tibble(iso3c = "HKG")) %>%
  bind_cols(., .) %>%
  set_names("country_origin", "country_destination") %>%
  expand(country_origin, country_destination) %>%
  filter(country_origin != country_destination)

current_year <- lubridate::year(Sys.Date())
all_years <- tibble(year = seq(from = 2000, to = current_year)) # 2005 is when outbreak record keeping began, but go back farther to get imputation trends
all_countries_years <- all_countries %>%
  crossing(all_years)

# Download and transform yearly variables ----------------------------------------------

## human migration
# expand for all country + year combos, run impute
message("Downloading UN human migration")
download_human_migration(directory = dir_downloads)
human <- transform_human_migration(directory = dir_downloads)
human <- human %>%
  mutate(year = as.integer(year)) %>%
  right_join(all_countries_years,  by = c("country_destination", "country_origin", "year")) %>%
  arrange(country_origin, country_destination, year) %>%
  group_split(country_origin, country_destination) %>%
  map_dfr(~na_interp(., "n_human_migrants")) %>%
  mutate(source = "UN")
write_csv(human, here(dir, "data-intermediate/un-human-migration.csv"))
dbWriteTable(conn,  name = "connect_yearly_un_human_migration", value = human, overwrite = TRUE)

## human tourism
# expand for all country + year combos, run impute
message("Downloading WTO tourism")
download_tourism(username = Sys.getenv("UNWTO_USERNAME"), password = Sys.getenv("UNWTO_PASSWORD"), directory = dir_downloads)
tourism <- transform_tourism(directory = dir_downloads)  %>%
  mutate(year = as.integer(year)) %>%
  right_join(all_countries_years,  by = c("country_destination", "country_origin", "year")) %>%
  arrange(country_origin, country_destination, year) %>%
  group_split(country_origin, country_destination) %>%
  map_dfr(~na_interp(., "n_tourists")) %>%
  mutate(source = "WTO")
write_csv(tourism, here(dir, "data-intermediate/wto-tourism.csv"))
dbWriteTable(conn,  name = "connect_yearly_wto_tourism", value = tourism, overwrite = TRUE)

## livestock trade
# assume 0s for NAs, extend last reported values to present, na_interp not needed
message("Downloading FAO livestock trade")
download_livestock(directory = dir_downloads)
livestock <- transform_livestock(directory = dir_downloads)
livestock <- livestock %>%
  pivot_longer(cols = -c("country_origin" , "country_destination",  "year" )) %>%
  mutate(imputed_value = is.na(value)) %>%
  mutate(value = na_replace(value, 0))

# if data is available for last 2 available years, carry forward to present
impute_latest <- livestock %>%
  filter(year %in% c(max(year), max(year)-1)) %>%
  arrange(country_origin, country_destination, name, -year) %>%
  group_by(country_origin, country_destination, name) %>%
  slice(1) %>% # take most recent year available
  mutate(year = list(seq(from = year+1, to = current_year))) %>%
  ungroup() %>%
  unnest(year) %>%
  mutate(imputed_value = TRUE)

all_countries_years_livestock <- crossing(all_countries_years, tibble(name = unique(livestock$name)))

# bring in all combos, again assume 0 for NA
livestock <- bind_rows(livestock, impute_latest)  %>%
  right_join(all_countries_years_livestock,  by = c("year", "country_origin", "country_destination", "name")) %>%
  mutate(imputed_value = is.na(value)) %>%
  mutate(value = na_replace(value, 0)) %>%
  arrange(country_origin, country_destination, name, year)

item_code_lookup <- get_livestock_item_id(directory = dir_downloads)
write_csv(item_code_lookup, here(dir, "data-intermediate/fao-livestock-item-code.csv"))

item_code_lookup <- item_code_lookup %>%
  mutate(name = paste0("livestock_heads_", item_code)) %>%
  select(-item_code)

livestock <- left_join(livestock, item_code_lookup, by = "name") %>%
  mutate(source = "FAO")
write_csv(livestock, here(dir, "data-intermediate/fao-livestock.csv"))
dbWriteTable(conn,  name = "connect_yearly_fao_livestock", value = livestock, overwrite = TRUE)

livestock_summary <- livestock %>%
  group_by(year, country_origin, country_destination) %>%
  summarize(fao_livestock_heads = sum(value)) %>%
  ungroup()
write_csv(livestock_summary, here(dir, "data-intermediate/fao-livestock-summary.csv"))
dbWriteTable(conn,  name = "connect_yearly_fao_livestock_summary", value = livestock_summary, overwrite = TRUE)

## ots trade
# assume 0s for NAs, extend last reported values to present, na_interp not needed
message("Downloading OTS trade")
download_trade(directory = dir_downloads)
trade <- transform_trade(directory = dir_downloads)
trade <- trade %>%
  pivot_longer(cols = -c("country_origin" , "country_destination",  "year" )) %>%
  mutate(imputed_value = is.na(value)) %>%
  mutate(value = na_replace(value, 0))

# if data is available for last 2 available years, carry forward to present
impute_latest <- trade %>%
  filter(year %in% c(max(year), max(year)-1)) %>%
  arrange(country_origin, country_destination, name, -year) %>%
  group_by(country_origin, country_destination, name) %>%
  slice(1) %>% # take most recent year available
  mutate(year = list(seq(from = year+1, to = current_year))) %>%
  ungroup() %>%
  unnest(year) %>%
  mutate(imputed_value = TRUE)

all_countries_years_trade <- crossing(all_countries_years, tibble(name = unique(trade$name)))

# bring in all combos, again assume 0 for NA
trade <- bind_rows(trade, impute_latest)  %>%
  right_join(all_countries_years_trade,  by = c("year", "country_origin", "country_destination", "name")) %>%
  mutate(imputed_value = is.na(value)) %>%
  mutate(value = na_replace(value, 0)) %>%
  arrange(country_origin, country_destination, name, year)

product_code_lookup <- tradestatistics::ots_products
write_csv(product_code_lookup, here(dir, "data-intermediate/ots-trade-product-code.csv"))

product_code_lookup <- product_code_lookup %>%
  as_tibble() %>%
  mutate(name = paste0("trade_dollars_", product_code)) %>%
  select(-product_code)

trade <- left_join(trade, product_code_lookup, by = "name") %>%
  mutate(source = "OTS")
write_csv(trade, here(dir, "data-intermediate/ots-trade.csv"))
dbWriteTable(conn,  name = "connect_yearly_ots_trade", value = trade, overwrite = TRUE)

trade_summary <- trade %>%
  group_by(year, country_origin, country_destination) %>%
  summarize(ots_trade_dollars = sum(value)) %>%
  ungroup()
write_csv(trade_summary, here(dir, "data-intermediate/ots-trade-summary.csv"))
dbWriteTable(conn,  name = "connect_yearly_ots_trade_summary", value = trade_summary, overwrite = TRUE)

# grant permissions
grant_table_permissions(conn)

dbDisconnect(conn)
