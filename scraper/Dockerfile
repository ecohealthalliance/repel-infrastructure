FROM rocker/tidyverse:3.6.2
MAINTAINER noam.ross@gmail.com

RUN apt-get update && apt-get install -y --no-install-recommends \
  postgresql-client \
  awscli \
  curl

ENV SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/v0.1.9/supercronic-linux-amd64 \
    SUPERCRONIC=supercronic-linux-amd64 \
    SUPERCRONIC_SHA1SUM=5ddf8ea26b56d4a7ff6faecdd8966610d5cb9d85

RUN curl -fsSLO "$SUPERCRONIC_URL" \
 && echo "${SUPERCRONIC_SHA1SUM}  ${SUPERCRONIC}" | sha1sum -c - \
 && chmod +x "$SUPERCRONIC" \
 && mv "$SUPERCRONIC" "/usr/local/bin/${SUPERCRONIC}" \
 && ln -s "/usr/local/bin/${SUPERCRONIC}" /usr/local/bin/supercronic

RUN install2.r -s curl rvest xml2 stringi RPostgres DBI arkdb DT here env connections

ARG GITHUB_PAT
ENV GITHUB_PAT=${GITHUB_PAT}
RUN installGithub.r ecohealthalliance/wahis@0a1287af715f57913a07562a91eae4e65ef14589 noamross/scrapetools

COPY . /home/rstudio/repel-infrastructure/scraper/

ENTRYPOINT []
CMD ["/home/rstudio/repel-infrastructure/scraper/start.sh"]
