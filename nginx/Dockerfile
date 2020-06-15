FROM linuxserver/letsencrypt

RUN apt-get update && apt-get install -y vim

RUN mkdir -p /config/nginx/site-confs/
COPY ./site-confs/ /config/nginx/site-confs/

RUN mkdir -p /config/www
COPY ./www/ /config/www/
