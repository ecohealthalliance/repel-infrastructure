#!/bin/bash

set -e

export PGUSER=$POSTGRES_USER
export PGPASSWORD=$POSTGRES_PASSWORD
export PGPORT=$POSTGRES_PORT
export PGHOST=$POSTGRES_HOST
export PGDATABASE=$POSTGRES_DB

# Backup the whole DB to S3
if [ "$BACKUP_PG" == "1" ]; then
  if []
  echo "Dumping $PGDATABASE and archiving on S3 bucket $AWS_BUCKET"
  pg_dumpall | xz -9 -c > /tmp/tmp.sql.xz
  aws s3 cp /tmp/tmp.sql.xz s3://${AWS_BUCKET}/dumps/${PGDUMP_FILENAME}.xz
  rm /tmp/tmp.sql.xz
fi
