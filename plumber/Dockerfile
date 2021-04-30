FROM rocker/tidyverse:4.0.4

RUN apt-get update -qq && apt-get install -y \
  git-core \
  libssl-dev \
  libcurl4-gnutls-dev \
  libsodium-dev \
  unixodbc-dev \
  libpq-dev \
  postgresql-client

RUN install2.r -s plumber RPostgreSQL DBI arkdb here env memoise

EXPOSE 8000

COPY plumber.R /
COPY .env /

ENTRYPOINT ["R", "-e", "pr <- plumber::plumb('plumber.R'); pr$run(host='0.0.0.0', port=8000)"]
