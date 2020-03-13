#!/bin/bash

# RStudio doesn't read in all environment vars, so this makes them visible to
# R processes
env >> /usr/local/lib/R/etc/Renviron.site

if [ $REPEL_TEST == "1" ]; then
  exec /init
else
  exec supercronic /home/rstudio/repel-infrastructure/scraper/scrape-schedule.cron
fi
