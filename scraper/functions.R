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

# this is an adaptation of repel_init.network_model from repelpredict
# to be combined with the original function in repelpredict
repel_init_events <- function(#model_object,
  conn,
  outbreak_reports_events,
  remove_single_country_disease = TRUE){

  current_month <- floor_date(Sys.Date(), unit = "month")
  current_year <- year(current_month)
  current_semester <- ifelse(current_month < "2021-07-01", 1, 2)
  current_period <- as.numeric(paste(current_year, recode(current_semester, '1' = '0', '2' = '5'), sep = "."))

  prev_year <- floor_date(current_month - 365,  unit = "month")
  next_century <- floor_date(current_month + 36500, unit = "month")

  #dat <- tbl(conn, "outbreak_reports_events")
  dat <- outbreak_reports_events

  events <- dat %>%
    collect() %>%
    filter(!is.na(country_iso3c), country_iso3c != "NA") %>%
    mutate_at(vars(contains("date")), as.Date)

  # Remove disease that have have reports in only one country_iso3c
  if(remove_single_country_disease){
    diseases_keep <- events %>%
      group_by(disease) %>%
      summarize(n_countries = length(unique(country_iso3c))) %>%
      arrange(desc(n_countries)) %>%
      filter(n_countries > 1 ) %>%
      pull(disease)

    events <- events %>%
      filter(disease %in% diseases_keep)
  }

  # dates handling
  events <- events %>%
    arrange(country, disease, report_date) %>%
    mutate(report_month = floor_date(report_date, unit = "months")) %>%
    mutate(date_of_start_of_the_event = floor_date(date_of_start_of_the_event, "month")) %>%
    mutate(date_event_resolved = floor_date(date_event_resolved, "month")) %>%
    select(country_iso3c, disease, outbreak_thread_id, report_type, report_month, date_of_start_of_the_event, date_event_resolved)  %>%
    group_by(outbreak_thread_id) %>%
    mutate(outbreak_start_month = min(c(report_month, date_of_start_of_the_event))) %>%
    mutate(outbreak_end_month = max(coalesce(date_event_resolved, report_month))) %>%  # outbreak end is date event resolved, if avail, or report month. the max accounts for instances where the resolved date is farther in the past than more recent reports in the same thread. see outbreak_thread_id == 10954
    # ^ this assumes that if thread is not marked as resolved, use the last report date as the end month
    # if it's been less than a year, however, keep the event as ongoing (use an end date in the future)
    mutate(outbreak_end_month = if_else(
      outbreak_end_month >= prev_year & all(is.na(date_event_resolved)),
      as.Date(next_century),
      as.Date(outbreak_end_month)
    )) %>%
    ungroup()

  # add in all combos of disease-country-month
  events <- events %>%
    full_join(
      events %>%
        tidyr::expand(
          country_iso3c,
          disease,
          month = seq.Date(
            from =  ymd("2005-01-01"), # start of record keeping
            to = current_month,
            by = "months")), by = c("country_iso3c", "disease"))

  # identify subsequent continuous outbreaks
  events <- events %>%
    mutate(outbreak_subsequent_month = month > outbreak_start_month & month <= outbreak_end_month) %>% # within bounds
    mutate(outbreak_start = month == outbreak_start_month)  %>%
    mutate(disease_country_combo_unreported = is.na(outbreak_thread_id)) %>%
    mutate_at(.vars = c("outbreak_subsequent_month", "outbreak_start"), ~replace_na(., FALSE))

  # identify endemic events
    endemic_status_present <- tbl(conn, "nowcast_boost_augment_predict")  %>% # this should have even coverage by country/disease up to latest reporting period
      inner_join(distinct(events, country_iso3c, disease), copy = TRUE,  by = c("disease", "country_iso3c")) %>%
      mutate(cases = coalesce(cases, predicted_cases)) %>%
      filter(cases > 0) %>%
      select(country_iso3c, report_year, report_semester, disease) %>%
      collect() %>%
      mutate(report_year = as.integer(report_year)) %>%
      mutate(report_semester = as.integer(report_semester))

    #assume last conditions are present conditions
    endemic_status_present_latest <- endemic_status_present %>%
      mutate(report_period = report_year + (report_semester - 1)/2) %>%
      filter(report_period == max(report_period)) %>%
      tidyr::expand(.,
                    country_iso3c,
                    disease,
                    report_period = as.character(format(seq(from = max(.$report_period), to = current_period, by = 0.5), nsmall = 1))) %>%
      mutate(report_year = as.integer(str_sub(report_period, start = 1, end = 4))) %>%
      mutate(report_semester = as.integer(str_sub(report_period, -1)) * 2 + 1 ) %>%
      filter(report_period != min(report_period)) %>%
      select(-report_period)

    endemic_status_present <- bind_rows(endemic_status_present, endemic_status_present_latest)

    year_lookup <- endemic_status_present %>%
      distinct(report_semester, report_year) %>%
      mutate(month = case_when(
        report_semester == 1 ~ list(seq(1, 6)),
        report_semester == 2 ~ list(seq(7, 12))))
    year_lookup <- unnest(year_lookup, month) %>%
      mutate(month = ymd(paste(report_year, month, "01")))

    endemic_status_present <- endemic_status_present %>%
      left_join(year_lookup,  by = c("report_year", "report_semester")) %>%
      select(country_iso3c, month, disease) %>%
      mutate(endemic = TRUE) %>%
      distinct()

    events <- events %>%
      left_join(endemic_status_present, by = c("country_iso3c", "disease", "month")) %>%
      mutate(endemic = replace_na(endemic, FALSE))

  # summarize to id subsequent and endemic
  events <- events %>%
    group_by(country_iso3c, disease, month) %>%
    summarize(outbreak_start = any(outbreak_start),
              outbreak_subsequent_month = any(outbreak_subsequent_month),
              endemic = any(endemic),
              disease_country_combo_unreported = all(disease_country_combo_unreported)) %>%
    ungroup() %>%
    mutate(outbreak_ongoing = outbreak_start|outbreak_subsequent_month)

  #mutate(endemic = ifelse(outbreak_start, FALSE, endemic))
  # ^ this last mutate covers cases where the outbreak makes it into the semester report. the first month of the outbreak should still count.
  # on the other hand, there are outbreaks that are reported when it really is already endemic, eg rabies, so commenting out for now
  # events %>% filter(outbreak_start, endemic) %>% View

  # remove diseases that do not affect primary taxa
  disease_taxa_lookup <- vroom::vroom(system.file("lookup", "disease_taxa_lookup.csv", package = "repelpredict"))
  events <- events %>%
    filter(disease %in% unique(disease_taxa_lookup$disease_pre_clean))

    # from inst/network_generate_disease_lookup.R
    diseases_recode <- vroom::vroom(system.file("lookup", "nowcast_diseases_recode.csv",  package = "repelpredict"), col_types = cols(
      disease = col_character(),
      disease_recode = col_character()
    ))
    events <- events %>%
      left_join(diseases_recode, by = "disease") %>%
      select(-disease) %>%
      rename(disease = disease_recode)
    assertthat::assert_that(!any(is.na(unique(events$disease)))) # if this fails, rerun inst/nowcast_generate_disease_lookup.R

  return(events)
}

