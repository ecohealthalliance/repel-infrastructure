FROM rocker/tidyverse:3.6.2
MAINTAINER noam.ross@gmail.com

RUN apt-get update && apt-get install -y --no-install-recommends \
  postgresql-client \
  awscli \
  xz-utils \
  curl

ENV SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/v0.1.9/supercronic-linux-amd64 \
    SUPERCRONIC=supercronic-linux-amd64 \
    SUPERCRONIC_SHA1SUM=5ddf8ea26b56d4a7ff6faecdd8966610d5cb9d85

RUN curl -fsSLO "$SUPERCRONIC_URL" \
 && echo "${SUPERCRONIC_SHA1SUM}  ${SUPERCRONIC}" | sha1sum -c - \
 && chmod +x "$SUPERCRONIC" \
 && mv "$SUPERCRONIC" "/usr/local/bin/${SUPERCRONIC}" \
 && ln -s "/usr/local/bin/${SUPERCRONIC}" /usr/local/bin/supercronic

RUN install2.r -s curl rvest xml2 stringi RPostgres DBI arkdb DT here env connections furrr future

ARG GITHUB_PAT
ENV GITHUB_PAT=${GITHUB_PAT}

RUN installGithub.r -u FALSE ecsohealthalliance/wahis@ffa491d435de87119b0d812b88b07356322b1a9b noamross/scrapetools

COPY . /home/rstudio/repel-infrastructure/scraper/

ENTRYPOINT []
CMD ["/home/rstudio/repel-infrastructure/scraper/start.sh"]
