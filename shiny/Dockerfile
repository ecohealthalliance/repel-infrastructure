FROM rocker/shiny:4.0.2

RUN /rocker_scripts/install_tidyverse.sh

ARG GITHUB_PAT
ENV GITHUB_PAT=${GITHUB_PAT}

RUN installGithub.r ecohealthalliance/repeldata

RUN mkdir -p /srv/repel-shiny-server/reports /srv/repel-shiny-server/logs

COPY ./shiny-server.conf /etc/shiny-server/shiny-server.conf

COPY ./index.html /srv/repel-shiny-server/
