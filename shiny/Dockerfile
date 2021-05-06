FROM rocker/geospatial:4.0.4

ENV S6_VERSION=v1.21.7.0
ENV SHINY_SERVER_VERSION=latest
ENV PANDOC_VERSION=default

RUN /rocker_scripts/install_shiny_server.sh
RUN install2.r ggiraph rnaturalearth RColorBrewer patchwork

ARG GITHUB_PAT
ENV GITHUB_PAT=${GITHUB_PAT}

RUN installGithub.r ecohealthalliance/repeldata ecohealthalliance/repelpredict@nowcast
RUN installGithub.r ropenscilabs/rnaturalearthdata

RUN mkdir -p /srv/repel-shiny-server/reports /srv/repel-shiny-server/logs

COPY ./shiny-server.conf /etc/shiny-server/shiny-server.conf

COPY ./index.html /srv/repel-shiny-server/

EXPOSE 3838

CMD ["/init"]
