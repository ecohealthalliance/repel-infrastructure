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
