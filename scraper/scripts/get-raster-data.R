# This script downloads and processes country-specifc data

source(here::here("scraper", "packages.R"))
source(here::here("scraper", "functions.R"))
library(rpostgis)
library(furrr)
library(fs)
library(raster)
library(future)
library(future.callr)

plan(callr)

env_file <- stringr::str_remove(here::here(".env"), "scraper/")
base:: readRenviron(env_file)

conn <- wahis_db_connect()

connections::connection_view(conn)

# Check PostGIS is installed in the database
pgPostGIS(conn)

#wahis::download_rasters()
rasters <- wahis::transform_rasters()
names(rasters) <- paste0("raster_", names(rasters))

iwalk(rasters, function(rast, name) pgWriteRast(conn, name, rast, overwrite = TRUE))


# Test extractions
pts <- sf::st_coordinates(sf::st_as_sfc(randgeo::wkt_point(1000, bbox = c(-180, -90, 180, 90))))
repeldata::get_raster_vals(conn, raster_name = c("raster_bioclim_1", "raster_glw_goats", "raster_bioclim_2", "raster_worldpop"), lon = pts[,1], lat = pts[, 2])

DBI::dbExecute(conn, "grant select on all tables in schema public to repel_reader")
DBI::dbExecute(conn, "grant select on all tables in schema public to repeluser")

dbDisconnect(conn)
