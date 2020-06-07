FROM linuxserver/letsencrypt

COPY . /config

RUN cat /config/site-confs/default >> /etc/nginx/nginx.conf
