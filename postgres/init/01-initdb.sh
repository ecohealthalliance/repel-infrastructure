#!/bin/bash

set -e

# Perform all actions as $POSTGRES_USER
export PGUSER="$POSTGRES_USER"
export PGDATABASE="$POSTGRES_DB"

if [ "$RESTORE_PG_FROM_AWS" == "1" ]
then
  dropdb $POSTGRES_DB || true
  if [ "$IS_PROD" == "yes" ]
  then
    echo "Restoring database $PGDATABASE from S3 bucket $AWS_BUCKET_PROD"
    target_bucket=${AWS_BUCKET_PROD}
  else
    echo "Restoring database $PGDATABASE from S3 bucket $AWS_BUCKET"
    target_bucket=${AWS_BUCKET}
  fi
  aws s3 cp s3://${target_bucket}/dumps/${PGDUMP_FILENAME}.xz /tmp/repel_backup.dmp.xz
  unxz /tmp/repel_backup.dmp.xz
  createdb $POSTGRES_DB || { echo "Error: failed to create repel database!" && exit 1; }
  psql -f /tmp/repel_backup.dmp postgres || { echo "Error: failed to restore repel database from backup!" && exit 1; }
  rm /tmp/repel_backup.dmp*
fi
# Configure database, system setting from https://pgtune.leopard.in.ua/
# DB Version: 12
# OS Type: linux
# DB Type: dw
# Total Memory (RAM): 4 GB
# CPUs num: 1
# Connections num: 20
# Data Storage: hdd
psql <<EOF
-- System settings
ALTER SYSTEM SET max_connections = '20';
ALTER SYSTEM SET shared_buffers = '1GB';
ALTER SYSTEM SET effective_cache_size = '3GB';
ALTER SYSTEM SET maintenance_work_mem = '512MB';
ALTER SYSTEM SET checkpoint_completion_target = '0.9';
ALTER SYSTEM SET wal_buffers = '16MB';
ALTER SYSTEM SET default_statistics_target = '500';
ALTER SYSTEM SET random_page_cost = '4';
ALTER SYSTEM SET effective_io_concurrency = '2';
ALTER SYSTEM SET work_mem = '13107kB';
ALTER SYSTEM SET min_wal_size = '4GB';
ALTER SYSTEM SET max_wal_size = '8GB';
-- add extensions to databases
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS plr;
EOF
# pg_cron extension adding must occur AFTER db startup
# (sleep 5; psql -c "CREATE EXTENSION IF NOT EXISTS pg_cron;") &
