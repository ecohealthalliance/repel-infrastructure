`%||%` <- function(a, b) if (is.null(a)) return(b) else return(a)

any2 <- function(x) ifelse(all(is.na(x)), NA, any(x, na.rm = TRUE))
sum2 <- function(x) ifelse(all(is.na(x)), NA, sum(x, na.rm = TRUE))

grant_table_permissions <- function(conn){
  DBI::dbExecute(conn, "grant select on all tables in schema public to repel_reader")
  DBI::dbExecute(conn, "grant select on all tables in schema public to repeluser")
}


