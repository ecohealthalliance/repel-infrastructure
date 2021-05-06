FROM ecohealthalliance/repel-base

ENV S6_VERSION=v1.21.7.0
ENV SHINY_SERVER_VERSION=latest
ENV PANDOC_VERSION=default

RUN /rocker_scripts/install_shiny_server.sh

RUN mkdir -p /srv/repel-shiny-server/reports /srv/repel-shiny-server/logs

COPY ./shiny-server.conf /etc/shiny-server/shiny-server.conf

COPY ./index.html /srv/repel-shiny-server/

EXPOSE 3838

CMD ["/init"]
