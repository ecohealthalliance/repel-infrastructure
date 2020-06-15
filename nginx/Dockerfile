FROM linuxserver/letsencrypt

RUN yum install vim -y

RUN mkdir -p /config/nginx/site-confs/
COPY ./site-confs/ /config/nginx/site-confs/

RUN mkdir -p /config/www
COPY ./www/ /config/www/
