export PGUSER=$POSTGRES_USER
export PGPASSWORD=$POSTGRES_PASSWORD
export PGPORT=$POSTGRES_PORT
export PGHOST=$POSTGRES_HOST
export PGDATABASE=$POSTGRES_DB

# pulls current AWS backup and replaces local repel database with it.

aws s3 cp s3://${AWS_BUCKET}/dumps/${PGDUMP_FILENAME}.xz repel_backup.dmp.xz
unxz repel_backup.dmp.xz
dropdb repel || { echo "Warning: failed to drop repel database!"; }
createdb repel || { echo "Error: failed to create repel database!" && exit 1; }
psql repel < repel_backup.dmp || { echo "Error: failed to restore repel database from backup!" && exit 1; }
rm repel_backup.dmp*
