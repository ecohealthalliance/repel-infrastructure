# REPEL Infrastructure

## Services

REPEL infrastructure is made up of the following services:
* base - core shared packages.  Included to speed up build time. Not intended to run.
* cron - runs cron backup scripts
* nginx - gets and updates SSL certs
* plumber - APIs
* postgres - core database
* rshinyauth0 - authentication
* scraper - web scraping and analysis
* shinyserver - static document and shiny application serving.

## Workflows

There are four workflows for running this code:
* local - This allows one to run the code for development.  It does not run the cron, rshinyauth0 or nginx services.
* minlocal - This allows one to run the code with a minimum of services running.  It only runs the postgres, shinyserver and plumber services.
* staging - This is intended for running the code on our staging server.  All services are run, but backups are stored to our staging bucket.
* production - This is intended for running the code on our production server.  Backups are stored in our production bucket.

## Workflow mechanics

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

## Deployment - Staging Server

1. Use script push_db_local_to_aws_and_dev_outside.sh to push your local database to the staging server and to the staging S3 bucket.
1. Update staging branch with changes in your development branch:
   1. Commit all changes to your dev branch
   1. Change to staging branch: `git checkout staging`
   1. Merge your dev branch into staging branch: `git merge your-dev-branch-name`
   1. Commit changes to staging branch: `git commit -a -m 'updated with changes from your-dev-branch-name'`
   1. Push staging update to remote: `git push origin`

A GitHub Action will then automatically deploy the updated staging branch to the staging server.

## Deployment - Production Server

Only 'staged' code should be pushed to the production server.
1. Follow the steps above to deploy code to the staging server
1. Merge staging branch into the production branch:
   1. Change to production branch: `git checkout production`
   1. Merge staging into production: `git merge staging`
   1. Commit changes to production branch: `git commit -a -m 'production updated from staging'`
   1. Push production update to remote: `git push origin`

A GitHub Action will then automatically deploy the updated production branch to the production server.
Before deploying it will also pull the contents of the staging S3 bucket into the production S3 bucket.

## Manual GitHub Actions

If there are any issues with the automatic deploy to either the staging or production server, there are manual GitHub Actions available to bring down and deploy to each server:
* production-remove-containers
* production-deploy-containers
* staging-shutdown-containers
* staging_deploy_containers


## PostGIS database setup

From http://fuzzytolerance.info/blog/2018/12/04/Postgres-PostGIS-in-Docker-for-production/

## Manually updating database

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
