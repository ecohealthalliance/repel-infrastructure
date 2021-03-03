library(DBI)
library(connections)

#* @get /mean
normalMean <- function(samples=10){
  data <- rnorm(samples)
  mean(data)
}

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
  if (require("connections")) {
    connections::connection_view(conn, name = "repel", connection_code = "repel")
  }

  return(conn)
}

#* @get /dbtest
dbvals <- function(){
  conn <- wahis_db_connect()
}

#* @post /sum
addTwo <- function(a, b){
  as.numeric(a) + as.numeric(b)
}
