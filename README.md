# PostGIS database setup

From http://fuzzytolerance.info/blog/2018/12/04/Postgres-PostGIS-in-Docker-for-production/

# Container mechanics

**build**:  
`docker-compose build`

**bring up local workflow**:  
`./start-local.sh`

OR

`USERID=$(id -u) GROUPID=$(id -g) docker-compose -f docker-compose.yml -f docker-compose-minlocal.yml up`

**bring up production workflow**:  
`docker-compose -f docker-compose.yml -f docker-compose-production.yml up`

**bring up staging workflow**:  
`docker-compose -f docker-compose.yml -f docker-compose-staging.yml up`

**bring down containers**:  
`docker-compose down`

# Manually updating database

First launch local postgres (**bring up local workflow** above)

**OIE tables**:  
`scraper/scrape-annual-reports.R` and `scraper/scrape-outbreak-reports.R` ingest, transform, and save new OIE reports to your local database. These scripts can also be used to initiate database tables from scratch. To do so, first manually delete all relevant tables from your local database, for example:

```
db_tables <- DBI::dbListTables(conn)
db_tables_annual <- db_tables[grepl("annual_reports_", db_tables)]
purrr::walk(db_tables_annual, ~DBI::dbRemoveTable(conn, .))
```
**Connect tables**:  
`scraper/scrape-connect-reports.R` will scrape, transform, and save non-OIE tables into your local database.

**Push local to remote**:  
To copy your local database to AWS (backup) and the development server (kirby), run `./scraper/push_db_local_to_aws_and_dev_outside.sh `. You will need to specify args host and port, for example:


```
./scraper/push_db_local_to_aws_and_dev_outside.sh prospero.ecohealthalliance.org 22053
```
