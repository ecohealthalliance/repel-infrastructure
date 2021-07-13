
test_scrape_outbreak_reports <- function(){

  # scrape report list
  reports <- scrape_outbreak_report_list()
  assert_that(nrow(reports) > 20700)
  assert_that(ncol(reports) == 17)

  # API response
  reports_to_test <- reports %>%
    tail(5) %>%
    pull(report_info_id)

  reports_to_get <- tibble(report_info_id = reports_to_test) %>%
    mutate(url =  paste0("https://wahis.oie.int/pi/getReport/", report_info_id))

  report_resps <-  map_curl(
    urls = reports_to_get$url,
    .f = function(x) wahis::safe_ingest(x),
    .host_con = 8L, # can turn up
    .delay = 0.5,
    .handle_opts = list(low_speed_limit = 100, low_speed_time = 300), # bytes/sec
    .retry = 2
  )

  assert_that(class(report_resps) == "map_curl")

  # transform
  outbreak_tables <- transform_outbreak_reports(outbreak_reports = report_resps, report_list = reports)
  assert_that(class(outbreak_tables) == "list")

  assert_that(!is.null(outbreak_tables$outbreak_reports_events))
  assert_that(nrow(outbreak_tables$outbreak_reports_events) == length(report_resps))

  assert_that(!is.null(outbreak_tables$outbreak_reports_outbreaks))

}
