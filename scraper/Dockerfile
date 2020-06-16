FROM rocker/tidyverse:3.6.2
MAINTAINER noam.ross@gmail.com

RUN apt-get update && apt-get install -y --no-install-recommends \
  postgresql-client \
  awscli \
  xz-utils \
  curl \
  parallel

# install fixuid
#RUN USER=rstudio && \
#    GROUP=rstudio && \
#    curl -SsL https://github.com/boxboat/fixuid/releases/download/v0.1/fixuid-0.1-linux-amd64.tar.gz | tar -C /usr/local/bin -xzf - && \
#    chown root:root /usr/local/bin/fixuid && \
#    chmod 4755 /usr/local/bin/fixuid && \
#    mkdir -p /etc/fixuid && \
#    printf "user: $USER\ngroup: $GROUP\n" > /etc/fixuid/config.yml
# ENTRYPOINT ["fixuid"]

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

RUN installGithub.r -u FALSE ecohealthalliance/wahis noamross/scrapetools

COPY . /home/rstudio/repel-infrastructure/scraper/

RUN mkdir -p /var/log/html/shiny /var/www/html/static /var/www/html/logs /var/www/html/apps && chgrp -R staff /var/www/  && chmod -R g+w /var/www

COPY index.html /var/www/html/

RUN ln -s /var/log/rstudio /var/www/html/logs/rstudio

RUN ln -s /var/log/html/shiny /var/www/html/logs/shiny

CMD ["/home/rstudio/repel-infrastructure/scraper/start.sh"]

# USER rstudio:rstudio
