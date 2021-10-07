#!/bin/bash

export PGUSER=$POSTGRES_USER
export PGPASSWORD=$POSTGRES_PASSWORD
export PGPORT=$POSTGRES_PORT
export PGHOST=$POSTGRES_HOST
export PGDATABASE=$POSTGRES_DB

# RStudio doesn't read in all environment vars, so this makes them visible to
# R processes
env >> /usr/local/lib/R/etc/Renviron.site

if [[ $WORKFLOW == "local" ]]
then
  chown -R $USERID:$GROUPID /home/rstudio
  echo "session-default-working-dir=~/repel-infrastructure/scraper" >> /etc/rstudio/rsession.conf
  exec /init
else
  chmod +x /home/rstudio/repel-infrastructure/scraper/scrape-outbreak-reports.R
  /home/rstudio/repel-infrastructure/scraper/scrape-outbreak-reports.R >> /var/log/shared/scraper.log 2>&1 || true
  chmod +x /home/rstudio/repel-infrastructure/scraper/scrape-six-month-reports.R
  /home/rstudio/repel-infrastructure/scraper/scrape-six-month-reports.R >> /var/log/shared/scraper.log 2>&1 || true
  exec supercronic /home/rstudio/repel-infrastructure/scraper/scrape-schedule.cron >> /var/log/shared/scraper.log 2>&1
fi
