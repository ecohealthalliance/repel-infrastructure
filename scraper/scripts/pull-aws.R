library(aws.s3)
library(fs)

aws.signature::use_credentials()
Sys.setenv("AWS_DEFAULT_REGION" = "us-east-1")

setwd("/Users/emmamendelsohn/r_projects/repel-infrastructure/scraper")

dir <- "data-raw"
if(dir != "." && !dir_exists(dir)){
  dir_create(here::here(dir))
}

bucket <- "wahis-data"
objects <- c("wahis-raw-annual-reports.tar.xz", "wahis-raw-outbreak-reports.tar.xz")

purrr::walk(objects, function(object){

  # Download the file
  save_object(object = object,
              bucket = bucket,
              file = object,
              overwrite = TRUE)

  # Uncompress the file
  untar(object, tar = "internal", exdir = dir)
  file.remove(object)

})
