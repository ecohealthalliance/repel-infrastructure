library(DBI)

#* @get /mean
normalMean <- function(samples=10){
  data <- rnorm(samples)
  mean(data)
}


# Host is just "postgres" within the docker network, with port 5432
# Connect to WAHIS Database
wahis_db_connect <- function(){
  # read env file
  #env_file <- stringr::str_remove(here::here(".env"), "plumber/")
  env_file <- ".env"
  base:: readRenviron(env_file)

  # set host and port depending on if running dev or production
  dev_host <- stringr::str_extract( Sys.info()["nodename"], "aegypti|prospero")
  if(is.na(dev_host)){
    host <- Sys.getenv("POSTGRES_HOST")
    port <- Sys.getenv("POSTGRES_PORT")
  }else{
    host <- paste0(dev_host, ".ecohealthalliance.org")
    port <- "22053"
  }

  # connect
  conn <- dbConnect(
    RPostgres::Postgres(),
    host = host,
    port = port,
    user = Sys.getenv("POSTGRES_USER"),
    password = Sys.getenv("POSTGRES_PASSWORD"),
    dbname = Sys.getenv("POSTGRES_DB")
    )

  return(conn)
}

conn <- wahis_db_connect()
my_cache <- cachem::cache_disk()
# TODO: Establish connection in top-level environment so it starts with API
# If any stability issues (maybe TODO at future date), consider connection pool:
#   https://db.rstudio.com/pool/
#* @get /dbtest
dbvals <- function(){
  conn <- wahis_db_connect()
}

#* @post /sum
addTwo <- function(a, b){
  as.numeric(a) + as.numeric(b)
}

# Generic database fetch function
serialize_repel_data <- function(data, format = c("csv", "json", "rds"), cache = TRUE) {
  # TODO: use serializers to return the right data format

}


#* @get /nowcast_predictions
get_nowcast_predictions <- memoise_function(function(columns = NULL, years, countries, format, cache = TRUE) {
  nowcast_predictions_table <- tbl(conn, "nowcast_boost_augment_predict")
  if (!is.null(columns)) {
    nowcast_predictions_table <- select(nowcast_predictions_table, columns)
  }
  nowcast_predictions_table <- filter(nowcast_predictions_table, report_year %in% years)
  dat <- collect(nowcast_predictions_table)
  serialize_repel_data(dat, format, cache)
})

memoise_function <- function(fn) {
  #use cachem::cache_disk (like connection, set up at top so it exists on startup)
  # disk-mount the cache directory so it survives restart
  memoise::memoise(fn, cache = my_cache)


}

