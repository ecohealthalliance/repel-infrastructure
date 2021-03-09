library(DBI)
library(RPostgreSQL)
library(stringr)
library(jsonlite)
library(memoise)

conn <- dbConnect(
  RPostgres::Postgres(),
  host = Sys.getenv("POSTGRES_HOST"),
  port = Sys.getenv("POSTGRES_PORT"),
  user = Sys.getenv("POSTGRES_USER"),
  password = Sys.getenv("POSTGRES_PASSWORD"),
  dbname = Sys.getenv("POSTGRES_DB")
)

#* @get /mean
normalMean <- function(samples=10){
  data <- rnorm(samples)
  mean(data)
}

#* @get /listTables
tableList <- function() {
  dbListTables(conn)
}

# TODO: Establish connection in top-level environment so it starts with API
# If any stability issues (maybe TODO at future date), consider connection pool:
#   https://db.rstudio.com/pool/

# Generic database fetch function
serialize_repel_data <- function(data, format = c("csv", "json", "rds"), cache = TRUE) {
  if (format == "json") {
    # data = serializeJSON(data)
    data = serializer_json(data, type="application/json")
  } else if (format == "csv") {
    data
  } else if (format == "rds") {
    data
  }
}

get_db_results <- function(conn, query) {
  nowcast_query <- dbSendQuery(conn, query)
  result <-dbFetch(nowcast_query)
}
cache_dir <- cachem::cache_disk("/plumber_cache")
get_db_results_memo <- memoize(get_db_results, cache = cache_dir)

#* @get /clearcache
clear_cache <- function() {
  cache_dir$reset()
}

#* @get /nowcast_predictions
get_nowcast_predictions <- function(columns = NULL, years, countries, format=c("csv","json","rds"), cache = TRUE) {

  #nowcast_predictions_table <- tbl(conn, "nowcast_boost_augment_predict")
  #dat <- collect(nowcast_predictions_table)

  columns
  if (is.null(columns)) {
    columns = "*"
  }
  if (years == "all") {
    years = ""
  }
  if (countries == "all"){
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

  query = paste("SELECT", columns, "FROM nowcast_boost_augment_predict", where_clause, "LIMIT 1000", sep=" ")

  #nowcast_query <- dbSendQuery(conn, query)
  #result <-dbFetch(nowcast_query)

  if (cache) {
    result <- get_db_results_memo(conn, query)
  } else {
    result <- get_db_results(conn, query)
  }
  # serialize_repel_data(result, format, cache)
}
#get_nowcast_predictions <- memoise_function(function(columns = NULL, years, countries, format, cache = TRUE) {
#  nowcast_predictions_table <- tbl(conn, "nowcast_boost_augment_predict")
#  if (!is.null(columns)) {
#    nowcast_predictions_table <- select(nowcast_predictions_table, columns)
#  }
#  nowcast_predictions_table <- filter(nowcast_predictions_table, report_year %in% years)
#  dat <- collect(nowcast_predictions_table)
#  serialize_repel_data(dat, format, cache)
#})

#memoise_function <- function(fn) {
#  #use cachem::cache_disk (like connection, set up at top so it exists on startup)
#  # disk-mount the cache directory so it survives restart
#  memoise::memoise(fn, cache = my_cache)
#}
