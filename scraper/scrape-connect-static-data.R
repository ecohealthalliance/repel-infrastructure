# This script downloads and processes connect (non-oie) yearly data

dir <- ifelse(basename(getwd())=="repel-infrastructure", "scraper", "")
source(here::here(dir, "packages.R"))
purrr::walk(list.files(here::here(dir, "R"), full.names = TRUE), source)
library(repelpredict)
dir_downloads <- paste(dir, "data-raw", sep = "/")

# Connect to database ----------------------------
message("Connect to database")
hl <- ifelse(dir == "scraper", "reservoir", "remote")
conn <- wahis_db_connect(host_location = hl)

# Get full table of all country combinations -------------------------------------------------------------------------
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

# Download and transform static variables ----------------------------------------------

# bird migration - do not assume 0s for NAs
message("Downloading BLI bird migration")
download_bird_migration(directory = dir_downloads)
bird <- transform_bird_migration(directory = dir_downloads) %>%
  right_join(all_countries)
write_csv(bird, here(dir, "data-intermediate/bli-bird-migration.csv"))
dbWriteTable(conn,  name = "connect_static_bli_bird_migration", value = bird, overwrite = TRUE)

# wildlife migration - do not assume 0s for NAs
message("Downloading IUCN wildlife migration")
download_wildlife(token = Sys.getenv("IUCN_REDLIST_KEY"), directory = dir_downloads)
# transform_wildlife_migration() not working as of 9/14/21 https://github.com/ecohealthalliance/wahis/issues/27
# wildlife_migration <- transform_wildlife_migration(directory = dir_downloads)
# wildlife_migration <- left_join(all_countries, wildlife_migration)
# write_csv(wildlife_migration, here(dir, "data-intermediate/iucn-wildlife_migration.csv"))
wildlife_migration <- read_csv(here(dir, "data-intermediate/iucn-wildlife_migration.csv")) %>%
  right_join(all_countries)
dbWriteTable(conn,  name = "connect_static_iucn_wildlife_migration", value = wildlife_migration, overwrite = TRUE)

# shared borders - assume FALSE for NAs
message("Get shared borders")
# this is down - need to refactor function for new CIA web page
# borders <- get_country_borders()
# write_csv(borders, here(dir, "data-intermediate/shared-borders.csv"))
borders <- read_csv(here(dir, "data-intermediate/shared-borders.csv")) %>%
  right_join(all_countries) %>%
  mutate(shared_border = replace_na(shared_border, FALSE))
dbWriteTable(conn,  name = "connect_static_shared_borders", value = borders, overwrite = TRUE)

# country distance
message("Get country distance")
country_distance <- get_country_distance() %>%
  ungroup() %>%
  mutate(gc_dist = as.numeric(gc_dist)) %>%
  rename(gc_dist_meters = gc_dist) # geosphere::distGeo
write_csv(country_distance, here(dir, "data-intermediate/country-distance.csv"))
dbWriteTable(conn,  name = "connect_static_country_distance", value = country_distance, overwrite = TRUE)


# grant permissions
grant_table_permissions(conn)

dbDisconnect(conn)

