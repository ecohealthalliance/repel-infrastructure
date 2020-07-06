FROM rocker/shiny:4.0.2

RUN mkdir -p /srv/repel-shiny-server/reports /srv/repel-shiny-server/logs

COPY ./shiny-server.conf /etc/shiny-server/shiny-server.conf

COPY ./index.html /srv/repel-shiny-server/
