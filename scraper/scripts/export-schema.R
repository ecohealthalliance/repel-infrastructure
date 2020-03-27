# This pulls the schema for database tables
#TODO match against field descriptions, provide warning for new or missing fields

source(here::here("packages.R"))
source(here::here("functions.R"))

# Connect to database ----------------------------
conn <- wahis_db_connect()

res <- dbSendQuery(conn, "SELECT * FROM information_schema.columns WHERE table_schema = 'public'")
schema <- dbFetch(res)

