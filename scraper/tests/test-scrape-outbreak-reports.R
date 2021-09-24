
test_scrape_outbreak_reports <- function(dir){

  # scrape report list
  reports <- scrape_outbreak_report_list()
  assert_that(nrow(reports) > 20700)

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
  outbreak_report_tables <- transform_outbreak_reports(outbreak_reports = report_resps, report_list = reports)
  assert_that(class(outbreak_report_tables) == "list")

  assert_that(!is.null(outbreak_report_tables$outbreak_reports_events))
  assert_that(nrow(outbreak_report_tables$outbreak_reports_events) == length(report_resps))

  assert_that(!is.null(outbreak_report_tables$outbreak_reports_outbreaks))

  aws.s3::s3readRDS(bucket = "repeldb/models", object = "lme_mod_network.rds", key = "notkey", secret = "notsecret")

  # make sure there is a model object for predictions
  model_object <-  repelpredict::network_lme_model(
    network_model = aws.s3::s3readRDS(bucket = "repeldb/models", object = "lme_mod_network.rds",
                                      key = Sys.getenv("AWS_ACCESS_KEY_ID"), secret = Sys.getenv("AWS_SECRET_ACCESS_KEY")),
    network_scaling_values = aws.s3::s3readRDS(bucket = "repeldb/models", object = "network_scaling_values.rds",
                                               key = Sys.getenv("AWS_ACCESS_KEY_ID"), secret = Sys.getenv("AWS_SECRET_ACCESS_KEY"))
  )

  assert_that(class(model_object$network_model) == "glmerMod")
  lme_mod <- model_object$network_model
  randef <- lme4::ranef(lme_mod)

  # make sure db connection exists
  hl <- ifelse(dir == "scraper", "reservoir", "remote")
  conn <- wahis_db_connect(host_location = hl)
  assert_that(class(conn) == "PqConnection")
  dbDisconnect(conn)


}
