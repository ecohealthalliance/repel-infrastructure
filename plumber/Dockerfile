FROM rocker/tidyverse:4.0.4

RUN apt-get update -qq && apt-get install -y \
  git-core \
  libssl-dev \
  libcurl4-gnutls-dev \
  libsodium-dev \
  unixodbc-dev \
  libpq-dev \
  postgresql-client


RUN install2.r -s plumber stringr RPostgres DBI arkdb here env memoise
RUN R -e 'install.packages("readr")'
RUN R -e 'install.packages("dplyr")'

EXPOSE 8000

COPY plumber.R /
COPY .env /

ENTRYPOINT ["R", "-e", "pr <- plumber::plumb(commandArgs()[4]); pr$run(host='0.0.0.0', port=8000)"]
CMD ["/plumber.R"]
