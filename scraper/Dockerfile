FROM ghcr.io/ecohealthalliance/repel-base
MAINTAINER noam.ross@gmail.com

ARG GITHUB_PAT
ENV GITHUB_PAT=$GITHUB_PAT
ARG AWS_ACCESS_KEY_ID
ENV AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
ARG AWS_SECRET_ACCESS_KEY
ENV AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY

ENV SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/v0.1.9/supercronic-linux-amd64 \
    SUPERCRONIC=supercronic-linux-amd64 \
    SUPERCRONIC_SHA1SUM=5ddf8ea26b56d4a7ff6faecdd8966610d5cb9d85

RUN curl -fsSLO "$SUPERCRONIC_URL" \
 && echo "${SUPERCRONIC_SHA1SUM}  ${SUPERCRONIC}" | sha1sum -c - \
 && chmod +x "$SUPERCRONIC" \
 && mv "$SUPERCRONIC" "/usr/local/bin/${SUPERCRONIC}" \
 && ln -s "/usr/local/bin/${SUPERCRONIC}" /usr/local/bin/supercronic

COPY . /home/rstudio/repel-infrastructure/scraper/

RUN mkdir -p /var/www/html/logs && chgrp -R staff /var/www/  && chmod -R g+w /var/www

COPY index.html /var/www/html

RUN mkdir /var/log/shared

RUN mkdir /var/www/reports

RUN chgrp staff /var/www/reports

RUN chmod g+w /var/www/reports

RUN chmod +x /home/rstudio/repel-infrastructure/scraper/scrape-outbreak-reports.R
RUN chmod +x /home/rstudio/repel-infrastructure/scraper/scrape-six-month-reports.R
RUN chmod +x /home/rstudio/repel-infrastructure/scraper/scrape-annual-reports.R
RUN chmod +x /home/rstudio/repel-infrastructure/scraper/scrape-connect-static-data.R
RUN chmod +x /home/rstudio/repel-infrastructure/scraper/scrape-connect-yearly-data.R
RUN chmod +x /home/rstudio/repel-infrastructure/scraper/scrape-country-yearly-data.R
RUN chmod +x /home/rstudio/repel-infrastructure/scraper/monthly-network-prediction-updates.R
RUN chmod +x /home/rstudio/repel-infrastructure/scraper/push_local_db_to_S3_and_stage_outside.sh

RUN chmod +x /home/rstudio/repel-infrastructure/scraper/test-scraper.R \
  && cd /home/rstudio/repel-infrastructure/scraper \
  && ./test-scraper.R

CMD ["/home/rstudio/repel-infrastructure/scraper/start.sh"]

# USER rstudio:rstudio
