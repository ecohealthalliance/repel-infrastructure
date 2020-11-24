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

**bring down containers**:  
`docker-compose down`

# Manually updating database

First launch local postgres (**bring up local workflow** above)

`scraper/scripts/init-annual-reports.R` and `scraper/scripts/init-outbreak-reports.R` will delete existing annual and outbreak report tables in your local database and will run the ingest and transform routines from scratch on locally saved downloads in `scraper/data-raw/wahis-raw-annual-reports/` and  `scraper/data-raw/wahis-raw-outbreak-reports/`.

`scraper/scrape-annual-reports.R` and `scraper/scrape-outbreak-reports.R` can be run to ingest and transform OIE reports that were not processed in the init scripts (above). These reports are either more recent than the files saved locally, or failed during the initial scrape.

To copy your local database to AWS (backup) and the development server (kirby), run `./scraper/push_db_local_to_aws_and_dev_outside.sh`.
