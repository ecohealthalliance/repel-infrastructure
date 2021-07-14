
test_scrape_six_month_reports <- function(){

  # scrape report list
  reports <- scrape_six_month_report_list()
  assert_that(nrow(reports) > 10200)
  assert_that(ncol(reports) == 12)

  # API response
  reports_to_test <- reports %>%
    tail(20) %>% # higher number to test to increase chance not just aquatic results
    pull(report_id)

  reports_to_get <- tibble(report_id = reports_to_test) %>%
    mutate(url =  paste0("https://wahis.oie.int/smr/pi/report/", report_id, "?format=preview"))

  report_resps <-  map_curl(
    urls = reports_to_get$url,
    .f = function(x) wahis::safe_ingest(x),
    .host_con = 8L,
    .delay = 0.5,
    .handle_opts = list(low_speed_limit = 100, low_speed_time = 300), # bytes/sec
    .retry = 2,
    .handle_headers = list(`Accept-Language` = "en")
  )

  assert_that(class(report_resps) == "map_curl")

  # transform - note that aquatic tables will be removed
  six_month_tables <- transform_six_month_reports(six_month_reports = report_resps)

  assert_that(class(six_month_tables) == "list")

}
