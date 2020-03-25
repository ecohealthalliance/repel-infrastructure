# This script pulls downloaded outbreak and annual reports from AWS
# These are used to initiate the wahis database without having to redownload all files

library(aws.s3)
library(fs)

# Specify files and directory ---------------------------------------------
dir <- "data-raw"
if(dir != "." && !dir_exists(dir)){
  dir_create(here::here(dir))
}
bucket <- "wahis-data"
objects <- c("wahis-raw-annual-reports.tar.xz", "wahis-raw-outbreak-reports.tar.xz")

# Download  ---------------------------------------------
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
