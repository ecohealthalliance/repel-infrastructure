library(DBI)
library(dplyr)
library(dbplyr)
library(rpostgis)
library(RPostgreSQL)
library(raster)



conn <- dbConnect(c::PostgreSQL(),dbname = '',
                 host = 'localhost', # i.e. 'ec2-54-83-201-96.compute-1.amazonaws.com'
                 port = 5432, # or any other port specified by your DBA
                 user = 'postgres',
                 password = 'supersecretpassword')

r <- raster::raster(nrows=180, ncols=360, xmn=-180, xmx=180,
                    ymn=-90, ymx=90, vals=rnorm(180*360))

pgWriteRast(conn, c(NULL, "newrast"), r,, overwrite = TRUE)

pgGetRast(conn, name = c("public", "newrast"), "rast", bands = TRUE)
View(pgWriteRast)
dbSchema(conn, "public")
dbVacuum(conn, "newrast")
pgListRast(conn)
pgListRast
