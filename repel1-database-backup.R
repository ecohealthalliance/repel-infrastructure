source(here::here("scraper", "packages.R"))
conn <- repeldata::repel_remote_conn()

tbls_to_backup <- dbListTables(conn)
tbls_to_backup <- tbls_to_backup[!str_starts(tbls_to_backup, "raster_")]

for(tb in tbls_to_backup){
  tmp <- dbReadTable(conn, tb)
  arrow::write_parquet(tmp, glue::glue("repel1_database_backup/{tb}.gz.parquet"))
}

containerTemplateUtils::aws_s3_upload(path = "repel1_database_backup",
              bucket =  "project-dtra-ml-main" ,
              key = "repel2/",
              prefix = "repel2/",
              check = TRUE)
