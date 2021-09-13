# Connect to WAHIS Database
wahis_db_connect <- function(host_location = c("reservoir", "local", "remote")){

  # read env file
  env_file <- stringr::str_remove(here::here(".env"), "scraper/")
  base::readRenviron(env_file)

  # assign host name and port
  host_location <- match.arg(host_location)
  host <- switch(host_location,
                 "local" = "0.0.0.0",
                 "reservoir" =  paste0( stringr::str_extract( Sys.info()["nodename"], "aegypti|prospero"), ".ecohealthalliance.org"),
                 "remote" = Sys.getenv("POSTGRES_HOST"))
  port <- switch(host_location,
                 "local" = "22053",
                 "reservoir" =  "22053",
                 "remote" = Sys.getenv("POSTGRES_PORT"))

  message(glue::glue('Attempting to connect to REPEL db at {host}:{port}'))
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

  info <- dbGetInfo(conn)
  message(glue::glue("Connected to database \"{info$dbname}\" at {info$host}:{info$port}"))
  return(conn)
}
