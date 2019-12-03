`%||%` <- function(a, b) if (is.null(a)) return(b) else return(a)

# Connect to WAHIS Database
wahis_db_connect <- function(){

  if ((Sys.getenv("REPEL_TEST") == "1") || (interactive() && Sys.getenv("RSTUDIO") == "1")) {
    base::readRenviron(here::here("repeldb", ".env"))
    conn <- dbConnect(
      RPostgres::Postgres(),
      host = Sys.getenv("DEPLOYMENT_SERVER_URL"),
      port = Sys.getenv("POSTGRES_EXTERNAL_PORT"),
      user = Sys.getenv("POSTGRES_USER"),
      password = Sys.getenv("POSTGRES_PASSWORD"),
      dbname = Sys.getenv("POSTGRES_DB")
    )
    if (require("connections")) {
      connections::connection_view(conn, name = "repel", connection_code = "repel")
    }
  } else {
    conn <- dbConnect(
      RPostgres::Postgres(),
      host = Sys.getenv("POSTGRES_HOST"),
      port = Sys.getenv("POSTGRES_PORT"),
      user = Sys.getenv("POSTGRES_USER"),
      password = Sys.getenv("POSTGRES_PASSWORD"),
      dbname = Sys.getenv("POSTGRES_DB")
    )
  }
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
  criteria <- distinct(select(updates, id_fields))
  selector <- paste0("(", do.call(paste, c(imap(criteria, ~paste0("", .y, " = \'", .x, "\'")), sep = " AND ")), ")", collapse = " OR ")
  removed <- DBI::dbGetQuery(conn, glue("DELETE FROM {table} WHERE {selector} RETURNING * ;"))
  dbAppendTable(conn, table, updates)
  if (verbose) message("Replacing ", nrow(removed), " old records with ", nrow(updates), " new records")
  return(removed)
}
