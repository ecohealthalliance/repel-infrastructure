# This script downloads and processes connect (non-oie) data

source(here::here("scraper/packages.R"))
source(here::here("scraper/functions.R"))

# Download and transform all ----------------------------------------------

download_bird_migration()
bird <- transform_bird_migration()
write_csv(bird, here("data-intermediate/bli-bird-migration.csv"))

download_trade() # ~ 2.5 hrs
trade <- transform_trade()
product_code_lookup <- tradestatistics::ots_products
write_csv(trade, here("data-intermediate/ots-trade.csv"))
write_csv(product_code_lookup, here("scraperdata-intermediate/ots-trade-product-code.csv"))

download_livestock()
livestock <- transform_livestock()
item_code_lookup <- get_livestock_item_id()
write_csv(livestock, here("data-intermediate/fao-livestock.csv"))
write_csv(item_code_lookup, here("data-intermediate/fao-livestock-item-code.csv"))

download_human_migration()
human <- transform_human_migration()
write_csv(human, here("data-intermediate/un-human-migration.csv"))

download_tourism(username = Sys.getenv("UNWTO_USERNAME"), password = Sys.getenv("UNWTO_PASSWORD"))
tourism <- transform_tourism()
write_csv(tourism, here("data-intermediate/wto-tourism.csv"))

download_wildlife(token = Sys.getenv("IUCN_REDLIST_KEY"))
wildlife_migration <- transform_wildlife_migration()
write_csv(wildlife_migration, here("data-intermediate/iucn-wildlife_migration.csv"))

borders <- get_country_borders()
write_csv(borders, here("data-intermediate/shared-borders.csv"))

country_distance <- get_country_distance()
write_csv(country_distance, here("data-intermediate/country-distance.csv"))

# Join all ----------------------------------------------------------------

# master list of country pairs
all_countries <- ggplot2::map_data("world") %>%
  as_tibble() %>%
  mutate(iso3c = countrycode::countrycode(sourcevar = region,
                                          origin = "country.name",
                                          destination = "iso3c"))  %>%
  dplyr::select(iso3c) %>%
  drop_na(iso3c) %>%
  unique() %>%
  bind_cols(., .) %>%
  set_names("country_origin", "country_destination") %>%
  expand(country_origin, country_destination) %>%
  filter(country_origin != country_destination)

# read in connect data
files <- list.files(here::here("data-intermediate"), full.names = TRUE, pattern = "*.csv")
dat <- map(files, ~read_csv(., col_type = cols(.default = "c"))) %>%
  set_names(basename(files))

static_tables <- c("bli-bird-migration.csv", "country-distance.csv", "iucn-wildlife_migration.csv", "shared-borders.csv")
yearly_tables <- c("fao-livestock.csv", "ots-trade.csv", "un-human-migration.csv", "wto-tourism.csv")
lookup_tables <- c("fao-livestock-item-code.csv",  "ots-trade-product-code.csv")

# handling time independent vars
static_dat <- dat[static_tables] %>%
  reduce(full_join)

static_dat <- left_join(all_countries, static_dat)

assertthat::are_equal(nrow(janitor::get_dupes(static_dat, country_origin, country_destination)), 0)

static_dat <- static_dat %>%
  select(country_origin, country_destination, shared_border, gc_dist, n_migratory_birds, n_migratrory_wildlife) %>%
  mutate(shared_border = replace_na(shared_border, FALSE)) #%>%
# mutate_at(.vars = c("shared_border"), ~as.logical(.)) %>%
# mutate_at(.vars = c("gc_dist"), ~as.double(.)) %>%
# mutate_at(.vars = c("n_migratory_birds", "n_migratrory_wildlife"), ~as.integer(.))

write_csv(static_dat, here("data-intermediate/connect/static-connect.csv.gz"))

# handling time dependent vars
yearly_dat <- dat[yearly_tables] %>%
  reduce(full_join)

all_years <- unique(yearly_dat$year) %>%
  sort() %>%
  tibble::enframe(value = "year") %>%
  select(year)
all_countries_years <- all_countries %>%
  crossing(all_years)

yearly_dat <- left_join(all_countries_years, yearly_dat)
assertthat::are_equal(nrow(janitor::get_dupes(yearly_dat, country_origin, country_destination, year)), 0)

yearly_dat <- yearly_dat %>%
  select(country_origin, country_destination,  year, starts_with("n_"), everything()) #%>%
# mutate_at(vars(year, starts_with("n_"), starts_with("livestock_")), ~as.integer(.)) %>%
# mutate_at(vars(starts_with("trade_")), ~as.double(.))

write_csv(yearly_dat, here("data-intermediate/connect/yearly-connect.csv.gz"))

# Add to db ---------------------------------------------------------------
conn <- wahis_db_connect()
static_dat <- read_csv(here("data-intermediate/connect/static-connect.csv.gz"))
yearly_dat <- read_csv(here("data-intermediate/connect/yearly-connect.csv.gz"))
fao_lookup <- read_csv(here("data-intermediate/fao-livestock-item-code.csv"))
ots_lookup <- read_csv(here("data-intermediate/ots-trade-product-code.csv"))

dbWriteTable(conn,  name = "connect_static_vars", value = static_dat, overwrite = TRUE)
dbWriteTable(conn,  name = "connect_yearly_vars", value = yearly_dat, overwrite = TRUE)
dbWriteTable(conn,  name = "connect_fao_lookup", value = fao_lookup, overwrite = TRUE)
dbWriteTable(conn,  name = "connect_ots_lookup", value = ots_lookup, overwrite = TRUE)

dbDisconnect(conn)
