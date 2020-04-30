#!/bin/bash

set -e

# Backup the whole DB to S3
if [ "$BACKUP_CSV" == "1" ]; then
  echo "Exporting CSVs from $PGDATABASE and archiving on S3 bucket $AWS_BUCKET"

# remove existing csv files before copying new ones
aws s3 rm s3://${AWS_BUCKET}/csv --recursive

# The `sem` command allows up to `j` jobs to be run in the background,
# Then `sem --wait` pauses execution until they are all done.  Doing this to
# allow parallel, but limited, connections to the database.
psql -Atc "select tablename from pg_tables where schemaname='public'" |\
  while read TBL; do
    sem -j 10 "psql -c \"COPY $TBL TO STDOUT WITH NULL AS 'NA' CSV HEADER\" | xz -9 -c | aws s3 cp - s3://${AWS_BUCKET}/csv/${TBL}.csv.xz"
  done
fi
sem --wait
