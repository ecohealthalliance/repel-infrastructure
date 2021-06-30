#!/bin/bash

set -e

export PGUSER=$POSTGRES_USER
export PGPASSWORD=$POSTGRES_PASSWORD
export PGPORT=$POSTGRES_PORT
export PGHOST=$POSTGRES_HOST
export PGDATABASE=$POSTGRES_DB

if [ "$WORKFLOW" == "production" ]
then
  target_bucket=${AWS_BUCKET_PROD}
  n_cores=1
else
  target_bucket=${AWS_BUCKET}
  n_cores=10
fi

# Backup the whole DB to S3
if [ "$BACKUP_CSV" == "1" ]; then
  echo "Exporting CSVs from $PGDATABASE and archiving on S3 bucket $target_bucket"

# remove existing csv files before copying new ones
aws s3 rm s3://${target_bucket}/csv --recursive

# The `sem` command allows up to `j` jobs to be run in the background,
# Then `sem --wait` pauses execution until they are all done.  Doing this to
# allow parallel, but limited, connections to the database.
psql -Atc "select tablename from pg_tables where schemaname='public'" |\
  while read TBL; do
    sem -j ${n_cores} "psql -c \"COPY $TBL TO STDOUT WITH NULL AS 'NA' CSV HEADER\" | xz -9 -c | aws s3 cp - s3://${target_bucket}/csv/${TBL}.csv.xz --acl public-read"
  done
fi
sem --wait
