#!/bin/bash

set -e
set -x

export PGUSER=$DEPLOYMENT_SERVER_USER
export PGPASSWORD=$DEPLOYMENT_SERVER_DB_PASS
export PGPORT=$DEPLOYMENT_SERVER_PSQL_PORT
export PGHOST=$DEPLOYMENT_SERVER_URL
export PGDATABASE=$POSTGRES_DB

# pulls current AWS backup and replaces dev repel database with it

aws s3 cp s3://${AWS_BUCKET}/dumps/${PGDUMP_FILENAME}.xz /tmp/repel_backup.dmp.xz
unxz /tmp/repel_backup.dmp.xz

dropdb repel || { echo "Warning: failed to drop repel database!"; }
createdb repel || { echo "Error: failed to create repel database!" && exit 1; }
psql repel < /tmp/repel_backup.dmp || { echo "Error: failed to restore repel database from backup!" && exit 1; }

rm /tmp/repel_backup.dmp*
