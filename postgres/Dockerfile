FROM postgres:12

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
      awscli \
 && rm -rf /var/lib/apt/lists/*

# set time zone
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

COPY gen_certs.sh gen_certs.sh
RUN ./gen_certs.sh

