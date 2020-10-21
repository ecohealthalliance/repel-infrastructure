#!/bin/bash

set -e

echo "starting 02-usraccts.sh" >> /tmp/deploy.log

# Perform all actions as $POSTGRES_USER
export PGUSER="$POSTGRES_USER"
export PGDATABASE="$POSTGRES_DB"

#`psql -d repel -c "revoke create on schema public from public"`

RR_EXISTS=`psql -X -A -d postgres -t -c "SELECT 1 FROM pg_roles WHERE rolname='repel_reader'"`
if [ "$RR_EXISTS" != "1" ]
then
  psql -d postgres -c "create role repel_reader with login encrypted password '$REPEL_READER_PASS' nosuperuser inherit nocreatedb nocreaterole noreplication valid until 'infinity'"
  psql -d postgres -c "grant connect on database repel to repel_reader"
  psql -d postgres -c "grant usage on schema public to repel_reader"
  psql -d postgres -c "grant select on all tables in schema public to repel_reader"
fi

RU_EXISTS=`psql -X -A -d postgres -t -c "SELECT 1 FROM pg_roles WHERE rolname='repeluser'"`
if [ "$RU_EXISTS" != "1" ]
then
  psql -d postgres -c "create user repeluser with encrypted password '$REPELUSER_PASS'"
#  psql -d postgres -c "alter database repel owner to repeluser"
  psql -d postgres -c "alter user repeluser createdb"
fi

echo "leaving 02-usraccts.sh" >> /tmp/deploy.log
