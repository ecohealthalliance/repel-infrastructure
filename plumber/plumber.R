library(dplyr)
library(plumber)
library(DBI)
library(RPostgreSQL)
library(stringr)
library(jsonlite)
library(memoise)

## util functions ################################

conn <- dbConnect(
  RPostgres::Postgres(),
  host = Sys.getenv("POSTGRES_HOST"),
  port = Sys.getenv("POSTGRES_PORT"),
  user = Sys.getenv("POSTGRES_USER"),
  password = Sys.getenv("POSTGRES_PASSWORD"),
  dbname = Sys.getenv("POSTGRES_DB")
)

serializers <- list(
  "json" = serializer_json(),
  "csv" = serializer_csv(),
  "rds" = serializer_rds()
)

cache_dir <- cachem::cache_disk("/plumber_cache")


get_db_results <- function(conn, columns, years, countries, limit) {

  columns_vec = unlist(str_split(columns, ","))
  years_vec = unlist(str_split(years, ","))
  country_vec = unlist(str_split(countries, ","))

  nowcast_predictions <- tbl(conn, "nowcast_boost_augment_predict") %>%
                         select(columns_vec) %>%
                         filter(report_year %in% years_vec) %>%
                         filter(country_iso3c %in% country_vec)

  if (!is.null(limit)) {
    nowcast_predictions <- nowcast_predictions %>% head(strtoi(limit))
  }

  dat <- collect(nowcast_predictions)
}
get_db_results_memo <- memoize(get_db_results, cache = cache_dir)

## API endpoints #######################################

### /clearcache  - clears any existing cache files
#* @get /clearcache
clear_cache <- function() {
  cache_dir$reset()
}


### /nowcast_predictions  - returns rows from db query of nowcast_boost_augment_predict table
### parameters:
###     columns: comma separated list of columns desired or NULL for all (default = NULL)
###     years: comma separated list of years desired or NULL for all (default = NULL)
###     countries: comma separated list of countries desired or NULL for all (default = NULL)
###     format: output format.  Allowed options are csv, json or rds.
###     cache: use cached results if available.  Allowed options are TRUE or FALSE (default = TRUE)
###     limit: limit the number of rows output or NULL for all (default = NULL)
#* @get /nowcast_predictions
get_nowcast_predictions <- function(columns = NULL, years = NULL, countries = NULL, format=c("csv","json","rds"), cache = TRUE, limit = NULL, res) {

  res$serializer <- serializers[[format]]

  if (cache) {
    result <- get_db_results_memo(conn, columns, years, countries, limit)
  } else {
    result <- get_db_results(conn, columns, years, countries, limit)
  }
}
