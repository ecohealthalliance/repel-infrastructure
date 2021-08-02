echo #!/bin/bash

set -e

if [[ "$#" -ne 2 ]]
then
  echo "Error: two input parameters are required"
  echo "Usage: $0 <host> <port>"
  exit 1
fi
args=("$@")

source ../.env

export PGUSER=$POSTGRES_USER
export PGPASSWORD=$POSTGRES_PASSWORD
export PGPORT=${args[1]}
export PGHOST=${args[0]}
export PGDATABASE=$POSTGRES_DB

# pulls current AWS backup and replaces local repel database with it.

aws s3 cp s3://${AWS_BUCKET}/dumps/${PGDUMP_FILENAME}.xz repel_backup.dmp.xz
unxz --force repel_backup.dmp.xz
dropdb repel || { echo "Warning: failed to drop repel database!"; }
createdb repel || { echo "Error: failed to create repel database!" && exit 1; }
psql repel < repel_backup.dmp || { echo "Error: failed to restore repel database from backup!" && exit 1; }
rm repel_backup.dmp*
