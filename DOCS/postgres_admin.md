# Postgres Admin - common admin tasks

## ERROR:  database "repel" is being accessed by other users

There may be idle queries causing this error.

Here are the step to clear idle jobs:

1. log into staging server
1. go onto repel-postgres container: `docker exec -it repel-postgres_container_id /bin/bash` where repel-postgres_container_id is the ID from the value from the first column of running `docker ps`
1. become user postgres: `su postgres`
1. start psql session: `psql`
1. check running queries: `SELECT pid, now() - pg_stat_activity.query_start AS duration, query, state FROM pg_stat_activity WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes';`
1. You can try to cancel idle jobs with: `SELECT pg_cancel_backend(pid);` where pid is replaced with the pid from the first column of the table created from your select command.
  1. Cancel is often not sufficient to kill an idle task, so if that happens you'll need to run: `SELECT pg_terminate_backend(pid);`  **WARNING**: this is equivalent to 'kill -9', so make sure you've got the correct pid. 
