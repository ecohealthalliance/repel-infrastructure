`%||%` <- function(a, b) if (is.null(a)) return(b) else return(a)

any2 <- function(x) ifelse(all(is.na(x)), NA, any(x, na.rm = TRUE))
sum2 <- function(x) ifelse(all(is.na(x)), NA, sum(x, na.rm = TRUE))

grant_table_permissions <- function(conn){
  DBI::dbExecute(conn, "grant select on all tables in schema public to repel_reader")
  DBI::dbExecute(conn, "grant select on all tables in schema public to repeluser")
}

# Adds more NA handling functionality to imputeTS::na_interpolation
na_interp <- function(df, var, to_current = TRUE){

  # if all NA, impute NA
  if(sum(!is.na(df[,var])) == 0){
    out <- mutate(df, !!paste0(var, "_imputed") := NA_integer_)
  }
  # if single value exists, apply to all imputed values
  if(sum(!is.na(df[,var])) == 1){
    out <- mutate(df,  !!paste0(var, "_imputed") := get(var)[!is.na(get(var))])
  }
  # if more than one value exists, use imputeTS::na_interpolation logic
  if(sum(!is.na(df[,var])) > 1){
    out <- mutate(df,  !!paste0(var, "_imputed") := imputeTS::na_interpolation(get(var)))
  }
  # if specified to carry imputation to current year, assume last value
  if(to_current){
    current_year <- lubridate::year(Sys.Date())
    years_to_add <- seq(from = as.integer(max(out$year))+1, to = current_year)
    impute_latest <- out %>%
      filter(year == max(year)) %>%
      select(-year) %>%
      bind_cols(tibble(year = years_to_add)) %>%
      mutate(!!var := NA)

    out <- out %>%
      mutate(year = as.integer(year)) %>%
      bind_rows(impute_latest)

  }

  out <-  out %>%
    mutate(imputed_value = get(var) != get(paste0(var, "_imputed"))) %>%
    mutate(imputed_value = ifelse(is.na(imputed_value), TRUE, imputed_value)) %>%
    select(-!!var) %>%
    rename(!!var := paste0(var, "_imputed"))

  return(out)
}
