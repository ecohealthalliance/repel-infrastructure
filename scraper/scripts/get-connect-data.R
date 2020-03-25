# This script downloads and processes connect (non-wahis) data

source(here::here("packages.R"))
source(here::here("functions.R"))

download_bird_migration()
bird <- transform_bird_migration()
write_csv(bird, here::here("data-intermediate/bli-bird-migration.csv"))
