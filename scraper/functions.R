`%||%` <- function(a, b) if (is.null(a)) return(b) else return(a)

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

# This replaces the rows in the database table with the ones in `updates`,
# matching on `id_fields`. The replacements are just appended on the end.
# There might be a better way using SQL UPDATE.  It returns the fields that were
# removed.
#TODO: This works with characters, but change so it works with other types

update_sql_table <- function(conn, table, updates, id_fields, fill_col_na = FALSE, verbose = TRUE) {
  sql_table <- tbl(conn, table)
  if(!fill_col_na){
    assert_that(identical(sort(colnames(sql_table)), sort(colnames(updates))))
  }else{
    add_cols <- setdiff(colnames(sql_table), colnames(updates))
    updates[,add_cols] <- NA
    assert_that(identical(sort(colnames(sql_table)), sort(colnames(updates))))
  }
  criteria <- distinct(select(updates, all_of(id_fields)))
  selector <- paste0("(", do.call(paste, c(imap(criteria, ~paste0("", .y, " = \'", .x, "\'")), sep = " AND ")), ")", collapse = " OR ")
  removed <- DBI::dbGetQuery(conn, glue("DELETE FROM {table} WHERE {selector} RETURNING * ;"))
  dbAppendTable(conn, table, updates)
  if (verbose) message("Replacing ", nrow(removed), " old records with ", nrow(updates), " new records")
  return(removed)
}

# Function to check field names against schema
field_check <- function(conn, table_regex){

  # get all table names with regex
  all_tables <- dbListTables(conn)[str_detect(dbListTables(conn), table_regex)]

  # pull schema from current db
  res <- dbSendQuery(conn, "SELECT * FROM information_schema.columns WHERE table_schema = 'public'")
  current_schema <- dbFetch(res) %>%
    filter(table_name %in% all_tables) %>%
    select(table_name, column_name)

  # pull schema to check against from wahis
  lookup_schema <- suppressMessages(wahis::repel_schema()) %>%
    filter(table_name %in% all_tables)  %>%
    select(table_name, column_name)

  # anti joins for disrepencies
  missing_fields <- anti_join(lookup_schema, current_schema, by = c("table_name", "column_name"))
  new_fields <-  anti_join(current_schema, lookup_schema, by = c("table_name", "column_name"))

  if(!nrow(missing_fields) && !nrow(new_fields)) {
    return("All fields match schema")
  }else{
    warning("Fields do not match schema")
    out <- list("Fields in schema & not in database" = missing_fields,
                "Fields in database & not in schema" = new_fields
    )
    return(out)
  }
}

any2 <- function(x) ifelse(all(is.na(x)), NA, any(x, na.rm = TRUE))
sum2 <- function(x) ifelse(all(is.na(x)), NA, sum(x, na.rm = TRUE))

grant_table_permissions <- function(conn){
  DBI::dbExecute(conn, "grant select on all tables in schema public to repel_reader")
  DBI::dbExecute(conn, "grant select on all tables in schema public to repeluser")
}

