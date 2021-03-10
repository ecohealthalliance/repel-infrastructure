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

serialize_repel_data <- function(data, format = c("csv", "json", "rds")) {
  if (format == "json") {
    jsonlite::toJSON(data)
  } else if (format == "csv") {
    readr::format_csv(data)
  } else if (format == "rds") {
    base::serialize(data, connection = NULL)
  }
}

cache_dir <- cachem::cache_disk("/plumber_cache")

serialize_repel_data_memo <- memoize(serialize_repel_data, cache = cache_dir)

get_db_results <- function(conn, query) {
  nowcast_query <- dbSendQuery(conn, query)
  result <-dbFetch(nowcast_query, n = -1)
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
###     limit: limit the number of rows output.  Allowed options are an integer or NULL for all (default = NULL)
#' @serializer contentType list(type="application/octet-stream")
#* @get /nowcast_predictions
get_nowcast_predictions <- function(columns = NULL, years = NULL, countries = NULL, format=c("csv","json","rds"), cache = TRUE, limit = NULL) {

  if (is.null(columns)) {
    columns = "*"
  }

  if (is.null(years)) {
    years = ""
  }

  if (is.null(countries)) {
    countries = ""
  } else {
    countries_list = strsplit(countries, split=",")[[1]]
    countries = paste("'",countries_list,"'", sep='', collapse=",")
  }

  if (years == "" & countries == ""){
    where_clause = ""
  } else if (years == "") {
    where_clause = paste("WHERE country_iso3c IN (", countries, ")")
  } else if (countries == "") {
    where_clause = paste("WHERE report_year IN (", years, ")")
  } else {
    where_clause = paste("WHERE country_iso3c IN (", countries, ") AND report_year in (", years, ")")
  }

  limit_str = ""
  if (!is.null(limit)) {
    limit_str = paste("LIMIT ", limit)
  }

  query = paste("SELECT", columns, "FROM nowcast_boost_augment_predict", where_clause, limit_str, sep=" ")

  if (cache) {
    result <- get_db_results_memo(conn, query)
  } else {
    result <- get_db_results(conn, query)
  }

  if (cache) {
    serialize_repel_data_memo(result, format)
  } else {
    serialize_repel_data(result, format)
  }
}
