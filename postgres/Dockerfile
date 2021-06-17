FROM postgres:11

ENV POSTGISV 2.5
ENV TZ America/New_York

RUN apt-get update && apt-get install -y --no-install-recommends \
      postgresql-$PG_MAJOR-postgis-$POSTGISV \
      postgresql-$PG_MAJOR-postgis-$POSTGISV-scripts \
      postgresql-$PG_MAJOR-plr \
      postgresql-server-dev-$PG_MAJOR \
#      postgresql-$PG_MAJOR-cron \
      unzip \
      xz-utils \
      make \
      sudo \
      awscli \
      curl \
      parallel \
 && rm -rf /var/lib/apt/lists/*

# set time zone
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

COPY gen_certs.sh gen_certs.sh
RUN ./gen_certs.sh

ENV SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/v0.1.9/supercronic-linux-amd64 \
   SUPERCRONIC=supercronic-linux-amd64 \
   SUPERCRONIC_SHA1SUM=5ddf8ea26b56d4a7ff6faecdd8966610d5cb9d85

RUN curl -fsSLO "$SUPERCRONIC_URL" \
  && echo "${SUPERCRONIC_SHA1SUM}  ${SUPERCRONIC}" | sha1sum -c - \
  && chmod +x "$SUPERCRONIC" \
  && mv "$SUPERCRONIC" "/usr/local/bin/${SUPERCRONIC}" \
  && ln -s "/usr/local/bin/${SUPERCRONIC}" /usr/local/bin/supercronic

COPY . /

RUN mkdir /var/log/shared

CMD ["/usr/local/bin/supercronic", "/backup-schedule.cron", ">>", "/var/log/shared/backups.log", "2>&1"]
