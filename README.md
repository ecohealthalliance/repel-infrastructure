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

1. Run script push_db_local_to_aws_and_dev_outside.sh _from within the scraper directory_ to push your local database to the staging server and to the staging S3 bucket. You will need to specify arguments for host, port, and temporary directory (an existing folder in your home directory). For example: `./push_local_db_to_S3_and_stage_outside.sh prospero.ecohealthalliance.org 22053 ~/tmp`

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
* staging-deploy-containers

## PostGIS database setup

From http://fuzzytolerance.info/blog/2018/12/04/Postgres-PostGIS-in-Docker-for-production/

## Load backup database
To delete your local database and pull the backup from AWS, run script pull_db_aws.sh _from within the scraper directory_

## Scrapers
There are multiple scripts running on cron schedules to pull in and process data.  

- __scrape-outbreak-reports.R__ processes outbreak reports from the OIE API and produces network (travelcast) model predictions. It produces and updates all `outbreak_reports_*` and `network_lme_*` tables in the database (see the `repeldata` package for table descriptions). Runs daily. 

   The network model depends on the assumption that diseases are ongoing if they haven't been reported as resolved within the previous year; therefore, we update model predictions each month to carry assumptions to current month. __monthly-network-prediction-updates.R__ runs on a monthly basis to provide these updates.

- __scrape-connect-static-data.R__ downloads and processes non-oie connect (bilateral country) data that is not time-dependent. It produces all `connect_static_*` tables (bird migration, wildlife migration, shared country borders, country distance). Runs yearly.

- __scrape-connect-yearly-data.R__ downloads and processes non-oie connect (bilateral country) data that is time-variable. It produces all `connect_yearly_*` tables (human migration, tourism, livestock trade, agricultural product trade). Runs monthly.

- __scrape-country-yearly-data.R__ downloads and processes country-specific data (non-connect) data that is time-variable. It produces all `country_yearly_*` tables (GDP, human population, taxa population, veterinarian counts). Runs monthly. 

- __scrape-six-month-reports.R__ processes six-month reports from the OIE API. [NEEDS TO BE UPDATED TO PRODUCE NOWCAST PREDICTIONS, FOLLOWING GENERAL APPROACH OF SCRAPE-OUTBREAK]. It produces and updates all `six_month_reports_*` tables in the database (see the `repeldata` package for table descriptions). Runs weekly. 

- __scrape-annual-reports.R__ [NEEDS TO BE UPDATED TO USE OIE API IF/WHEN AVAILABLE]

