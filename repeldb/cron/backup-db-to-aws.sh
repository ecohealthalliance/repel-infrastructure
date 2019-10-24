#!/bin/bash

set -e

# Backup the whole DB to S3
if [ "$BACKUP_PG" == "1" ]; then
  echo "Dumping $PGDATABASE and archiving on S3 bucket $AWS_BUCKET"
  pg_dumpall | xz -9 -c |\
    aws s3 cp - s3://${AWS_BUCKET}/dumps/${PGDUMP_FILENAME}.xz
fi
