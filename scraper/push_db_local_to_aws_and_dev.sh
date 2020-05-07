# copy local repel database to dev and AWS

# verify with user that this should be run
echo "Running this script will push your local repel database to the development server and to AWS."
read -p "Are you sure you want to proceed? (Y/N) " -r
if [[ ! $REPLY == "Y" ]]
then
  echo "Exiting without running as requested."
  exit 0
fi

# set env to local and dump database

export PGUSER=$POSTGRES_USER
export PGPASSWORD=$POSTGRES_PASSWORD
export PGPORT=$POSTGRES_PORT
export PGHOST=$POSTGRES_HOST
export PGDATABASE=$POSTGRES_DB

pg_dump repel > /tmp/repel_backup_local.dmp

# set env to dev server and update database

export PGUSER=$DEPLOYMENT_SERVER_USER
export PGPASSWORD=$DEPLOYMENT_SERVER_DB_PASS
export PGPORT=$DEPLOYMENT_SERVER_PSQL_PORT
export PGHOST=$DEPLOYMENT_SERVER_URL
export PGDATABASE=$POSTGRES_DB

dropdb repel || { echo "Error: failed to drop repel database!" && exit 1; }
createdb repel || { echo "Error: failed to create repel database!" && exit 1; }
psql repel < /tmp/repel_backup_local.dmp || { echo "Error: failed to restore repel database from backup!" && exit 1; }

# archive dump and push to AWS

xz /tmp/repel_backup_local.dmp
aws s3 cp /tmp/repel_backup_local.dmp.xz s3://${AWS_BUCKET}/dumps/${PGDUMP_FILENAME}.xz

# remove existing csv files from AWS then copy local ones

aws s3 rm s3://${AWS_BUCKET}/csv --recursive

# The `sem` command allows up to `j` jobs to be run in the background,
# Then `sem --wait` pauses execution until they are all done.  Doing this to
# allow parallel, but limited, connections to the database.

# set env back to local to copy CSVs to AWS

export PGUSER=$POSTGRES_USER
export PGPASSWORD=$POSTGRES_PASSWORD
export PGPORT=$POSTGRES_PORT
export PGHOST=$POSTGRES_HOST
export PGDATABASE=$POSTGRES_DB

psql -Atc "select tablename from pg_tables where schemaname='public'" |\
  while read TBL; do
    sem -j 10 "psql -c \"COPY $TBL TO STDOUT WITH NULL AS 'NA' CSV HEADER\" | xz -9 -c | aws s3 cp - s3://${AWS_BUCKET}/csv/${TBL}.csv.xz"
  done
sem --wait

# clean up

rm /tmp/repel_backup_local.dmp*
