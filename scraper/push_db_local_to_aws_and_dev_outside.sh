#!/bin/bash
# copy local repel database to dev and AWS

if [[ "$#" -ne 2 ]]
then
  echo "Usage: $0 <host> <port>"
fi
args=("$@")

set -e
# functions to test environment variables to local or dev server

set_local_env () {
  export PGUSER=$POSTGRES_USER
  export PGPASSWORD=$POSTGRES_PASSWORD
  export PGPORT=${args[1]}
  export PGHOST=${args[0]}
  export PGDATABASE=$POSTGRES_DB
}

set_dev_env () {
  export PGUSER=$POSTGRES_USER
  export PGPASSWORD=$POSTGRES_PASSWORD
  export PGPORT=$DEPLOYMENT_SERVER_PSQL_PORT
  export PGHOST=$DEPLOYMENT_SERVER_URL
  export PGDATABASE=$POSTGRES_DB
}

# verify with user that this should be run
echo "Running this script will push your local repel database to the development server and to AWS."
read -p "Are you sure you want to proceed? (Y/N) " -r
if [[ ! $REPLY == "Y" ]]
then
  echo "Exiting without running as requested."
  exit 0
fi

# set env to local and dump database
if [ -z "$POSTGRES_USER" ]
then
 source .env
fi

set_local_env
pg_dump repel > /tmp/repel_backup_local.dmp
pg_dumpall > /tmp/all_pg_local.dmp

filesize_repel=$(stat -c%s "/tmp/repel_backup_local.dmp")
if (( filesize_repel < 100000)); then
  echo "Error: repel backup file size is too small!"
  exit 1
fi

# set env to dev server and update database

set_dev_env
dropdb --if-exists repeltmp
createdb repeltmp || { echo "Error: failed to create repel database!" && exit 1; }
psql repeltmp < /tmp/repel_backup_local.dmp || { echo "Error: failed to restore repel database from backup!" && exit 1; }
psql <<EOF
\connect postgres;
drop database repel;
alter database repeltmp rename to repel;
EOF
# make sure last commands succeeded
if [[ $? -ne 0 ]]
then
  echo "Error: failed to rename database to repel";
  exit 1;
fi

# archive dump and push to AWS

xz /tmp/all_pg_local.dmp
aws s3 cp /tmp/all_pg_local.dmp.xz s3://${AWS_BUCKET}/dumps/${PGDUMP_FILENAME}.xz

# remove existing csv files from AWS then copy local ones

aws s3 rm s3://${AWS_BUCKET}/csv --recursive

# The `sem` command allows up to `j` jobs to be run in the background,
# Then `sem --wait` pauses execution until they are all done.  Doing this to
# allow parallel, but limited, connections to the database.

# set env back to local to copy CSVs to AWS

set_local_env

psql -Atc "select tablename from pg_tables where schemaname='public'" |\
  while read TBL; do
    sem -j 10 "psql -c \"COPY $TBL TO STDOUT WITH NULL AS 'NA' CSV HEADER\" | xz -9 -c | aws s3 cp - s3://${AWS_BUCKET}/csv/${TBL}.csv.xz"
  done
sem --wait

# clean up

rm /tmp/repel_backup_local.dmp*
rm /tmp/all_pg_local.dmp*
