#!/bin/bash
# copy local repel database to dev and AWS
# to be run from within scraper directory

DB_SAVE_DIR=/tmp

if [ $# -eq 3 ]
then
  DB_SAVE_DIR=$3
elif [ $# -ne 2 ]
then
  echo "Error: input parameters host and port are required"
  echo "  tmp_dir is optional and defaults to /tmp"
  echo "Usage: $0 <host> <port> <tmp_dir>"
  exit 1
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

set_stage_env () {
  export PGUSER=$POSTGRES_USER
  export PGPASSWORD=$POSTGRES_PASSWORD
  export PGPORT=$STAGING_SERVER_PSQL_PORT
  export PGHOST=$STAGING_SERVER_URL
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
 source ../.env
fi

# check that remote db isn't blocked by idle queries before making local db dump
set_stage_env
createdb test_create_db || { echo "Error: failed to create test database!" && exit 1; }
dropdb --if-exists test_create_db

# make local db dumps
set_local_env
pg_dump repel > ${args[2]}/repel_backup_local.dmp
pg_dumpall > ${args[2]}/all_pg_local.dmp

filesize_repel=$(stat -c%s "${args[2]}/repel_backup_local.dmp")
if (( filesize_repel < 100000)); then
  echo "Error: repel backup file size is too small!"
  exit 1
fi

# set env to dev server and update database

set_stage_env
dropdb --if-exists repeltmp
createdb repeltmp || { echo "Error: failed to create repel database!" && exit 1; }
psql repeltmp < ${args[2]}/repel_backup_local.dmp || { echo "Error: failed to restore repel database from backup!" && exit 1; }
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

XZ_DUMP_FILE=${args[2]}/all_pg_local.dmp.xz
if [ -f "$XZ_DUMP_FILE" ]
then
  rm $XZ_DUMP_FILE
fi
xz ${args[2]}/all_pg_local.dmp
aws s3 cp ${args[2]}/all_pg_local.dmp.xz s3://${AWS_BUCKET}/dumps/${PGDUMP_FILENAME}.xz

# remove existing csv files from AWS then copy local ones
aws s3 rm s3://${AWS_BUCKET}/csv --recursive

# set s3 bucket policy
aws s3api put-bucket-policy --bucket ${AWS_BUCKET} --policy file://csv_policy.json

# The `sem` command allows up to `j` jobs to be run in the background,
# Then `sem --wait` pauses execution until they are all done.  Doing this to
# allow parallel, but limited, connections to the database.

# set env back to local to copy CSVs to AWS

set_local_env

psql -Atc "select tablename from pg_tables where schemaname='public'" |\
  while read TBL; do
    sem -j 10 "psql -c \"COPY $TBL TO STDOUT WITH NULL AS 'NA' CSV HEADER\" | xz -9 -c | aws s3 cp - s3://${AWS_BUCKET}/csv/${TBL}.csv.xz --acl public-read"
  done
sem --wait

# clean up

rm ${args[2]}/repel_backup_local.dmp*
rm ${args[2]}/all_pg_local.dmp*
