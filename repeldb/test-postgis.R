
library(RPostgres)
library(raster)
library(aws.s3)
library(readr)
library(arkdb)

aws.signature::use_credentials()


#s3sync(files =  paste0("data-processed/db/", dir("data-processed/db", include.dirs = TRUE)),
#       bucket = "wahis-data",
#       direction = "download")

conn <- dbConnect(RPostgres::Postgres(),
                 host = 'aegypti.ecohealthalliance.org', # i.e. 'ec2-54-83-201-96.compute-1.amazonaws.com'
                 port = 22023, # or any other port specified by your DBA
                 user = 'postgres',
                 password = 'supersecretpassword',
                 dbname = 'repel')

arkdb::unark(fs::dir_ls("data-processed/db"), db_con = conn, overwrite = TRUE,
             streamable_table = streamable_readr_csv(), lines = 50000L, col_types = cols(.default = col_character()))

