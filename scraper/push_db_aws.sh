set -e
set -x

export PGUSER=$POSTGRES_USER
export PGPASSWORD=$POSTGRES_PASSWORD
export PGPORT=$POSTGRES_PORT
export PGHOST=$POSTGRES_HOST
export PGDATABASE=$POSTGRES_DB

pg_dumpall | xz -9 -c | aws s3 cp - s3://${AWS_BUCKET}/dumps/${PGDUMP_FILENAME}.xz

psql -Atc "select tablename from pg_tables where schemaname='public'" |\
  while read TBL; do
    sem -j 10 "psql -c \"COPY $TBL TO STDOUT WITH NULL AS 'NA' CSV HEADER\" | xz -9 -c | aws s3 cp - s3://${AWS_BUCKET}/csv/${TBL}.csv.xz"
  done
sem --wait
