`%||%` <- function(a, b) if (is.null(a)) return(b) else return(a)

any2 <- function(x) ifelse(all(is.na(x)), NA, any(x, na.rm = TRUE))
sum2 <- function(x) ifelse(all(is.na(x)), NA, sum(x, na.rm = TRUE))

grant_table_permissions <- function(conn){
  DBI::dbExecute(conn, "grant select on all tables in schema public to repel_reader")
  DBI::dbExecute(conn, "grant select on all tables in schema public to repeluser")
}

# Adds more NA handling functionality to imputeTS::na_interpolation
na_interp <- function(df, var){

  # if all NA, impute NA
  if(sum(!is.na(df[,var])) == 0){
    out <- df %>%
      mutate(!!paste0(var, "_imputed") := NA_integer_) %>%
      mutate(imputed_value = FALSE)
  }
  # if single value exists, apply to all imputed values
  if(sum(!is.na(df[,var])) == 1){
    out <- df %>%
      mutate(imputed_value = is.na(get(var))) %>%
      mutate(!!paste0(var, "_imputed") := get(var)[!is.na(get(var))])
  }
  # if more than one value exists, use imputeTS::na_interpolation logic
  if(sum(!is.na(df[,var])) > 1){
    out <- df %>%
      mutate(imputed_value = is.na(get(var))) %>%
      mutate(!!paste0(var, "_imputed") := imputeTS::na_interpolation(get(var)))
  }

  out <-  out %>%
    select(-!!var) %>%
    rename(!!var := paste0(var, "_imputed")) %>%
    relocate(imputed_value, .after = last_col())

  return(out)
}
