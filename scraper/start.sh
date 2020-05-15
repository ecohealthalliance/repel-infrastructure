#!/bin/bash

export PGUSER=$POSTGRES_USER
export PGPASSWORD=$POSTGRES_PASSWORD
export PGPORT=$POSTGRES_PORT
export PGHOST=$POSTGRES_HOST
export PGDATABASE=$POSTGRES_DB

# RStudio doesn't read in all environment vars, so this makes them visible to
# R processes
env >> /usr/local/lib/R/etc/Renviron.site

if [[ $REPEL_TEST == "1" ]]
then
  echo "session-default-working-dir=~/repel-infrastructure/scraper" >> /etc/rstudio/rsession.conf
  exec /init
else
  exec supercronic /home/rstudio/repel-infrastructure/scraper/scrape-schedule.cron
fi

if [[ $IS_LOCAL == "yes" ]]
then
  fixuid
