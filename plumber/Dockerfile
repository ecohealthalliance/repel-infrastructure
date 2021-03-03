FROM rocker/r-base
MAINTAINER Jeff Allen <docker@trestletech.com>

RUN apt-get update -qq && apt-get install -y \
  git-core \
  libssl-dev \
  libcurl4-gnutls-dev \
  libsodium-dev \
  unixodbc-dev \
  libpq-dev

## RUN R -e 'install.packages(c("devtools"))'
## RUN R -e 'devtools::install_github("trestletech/plumber")'
RUN install2.r plumber

EXPOSE 8000

COPY plumber.R /
COPY .env /

ENTRYPOINT ["R", "-e", "pr <- plumber::plumb(commandArgs()[4]); pr$run(host='0.0.0.0', port=8000)"]
# CMD ["/usr/local/lib/R/site-library/plumber/plumber/04-mean-sum/plumber.R"]
CMD ["/plumber.R"]
