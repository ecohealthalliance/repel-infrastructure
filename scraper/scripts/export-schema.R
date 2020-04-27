# This pulls the schema for database tables

source(here::here("packages.R"))
source(here::here("functions.R"))

# Connect to database ----------------------------
conn <- wahis_db_connect()

res <- dbSendQuery(conn, "SELECT * FROM information_schema.columns WHERE table_schema = 'public'")
schema <- dbFetch(res) %>%
  janitor::remove_empty("cols")

# One time lookup of FAO and OTS codes for schema ------------------------------------------------
# fao <- dbReadTable(conn, "connect_fao_lookup") %>%
#   mutate(code = paste0("livestock_heads_", item_code)) %>%
#   mutate(description = paste("count of traded", tolower(item))) %>%
#   select(-item, -item_code)
#
# ots <- dbReadTable(conn, "connect_ots_lookup") %>%
#   mutate(code = paste0("trade_dollars_", product_code)) %>%
#   mutate(description = paste("count of dollar:", tolower(product_fullname_english))) %>%
#   select(code, description)
#
# fao_ots <- bind_rows(fao, ots)
#
# lookup <- tibble(code = dbListFields(conn, "connect_yearly_vars")) %>%
#   filter(str_detect(code, "livestock|trade")) %>%
#   left_join(fao_ots)
#
# write_csv(lookup, "lookup_fao_ots.csv")
