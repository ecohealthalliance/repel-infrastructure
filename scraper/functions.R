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
# matching on `id_field`. The replacements are just appended on the end.
# There might be a better way using SQL UPDATE.  It returns the fields that were
# removed.
#TODO: This works with characters, but change so it works with other types

update_sql_table <- function(conn, table, updates, id_field, fill_col_na = FALSE, verbose = TRUE) {
  sql_table <- tbl(conn, table)
  if(!fill_col_na){
    assert_that(identical(sort(colnames(sql_table)), sort(colnames(updates))))
  }else{
    add_cols_to_updates <-setdiff(colnames(sql_table), colnames(updates))
    updates[,add_cols_to_updates] <- NA
    add_cols_to_existing <- setdiff(colnames(updates), colnames(sql_table))
    for(col in add_cols_to_existing){
      dbGetQuery(conn, glue("ALTER TABLE {table} ADD COLUMN {col} TEXT"))
    }
    sql_table <- tbl(conn, table)
    assert_that(identical(sort(colnames(sql_table)), sort(colnames(updates))))
  }

  dbxUpsert(conn,  table, records = updates, where_cols = id_field)
  return()
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


# wrapper for update_sql_table to handle nulls and empty tables. also writes table if it doesn't already exist.
db_update <- function(conn, table_name, table_content, id_field, fill_col_na = FALSE){
  message(paste("Updating", table_name))
  if(!is.null(table_content)){
    if(nrow(table_content)){
      if(!dbExistsTable(conn, table_name)){
        # write fresh table to db
        dbWriteTable(conn,  name = table_name, value = table_content)
        # set postgres primary key
        pk_name <- paste0(table_name, "_pk")
        pkquery <- DBI::dbGetQuery(conn, glue("ALTER TABLE {table_name} ADD CONSTRAINT {pk_name} PRIMARY KEY ({id_field})"))
      }else{
        update_sql_table(conn,  table = table_name, updates = table_content,
                         id_field = id_field, fill_col_na = fill_col_na)
      }
    }
  }
}
