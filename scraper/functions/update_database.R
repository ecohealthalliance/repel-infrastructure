
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
