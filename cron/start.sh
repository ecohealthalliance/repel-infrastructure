#!/bin/bash

export PGUSER=$POSTGRES_USER
export PGPASSWORD=$POSTGRES_PASSWORD
export PGPORT=$POSTGRES_PORT
export PGHOST=$POSTGRES_HOST
export PGDATABASE=$POSTGRES_DB

if [ "$BACKUP_FLAG" == "yes" ]
then
    supercronic backup-schedule.cron >> /var/log/shared/backups.log 2>&1
fi
