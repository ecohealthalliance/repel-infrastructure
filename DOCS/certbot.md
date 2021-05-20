# Certbot details

Installing Certbot and getting SSL certs is currently a manual process:
1. snap is installed by default on Ubuntu 20.04 so we don't need to install
1. `sudo snap install core`
1. `sudo snap refresh core`
1. `sudo snap install --classic certbot`
1. `sudo ln -s /snap/bin/certbot /usr/bin/certbot`
1. `sudo certbot certonly`
   1. select '1' to spin up temp webserver
   1. enter email address
   1. accept agreement
   1. answer EFF mailing list
   1. enter domain name: repel-aws.eha.io
1. test auto renewal: `sudo certbot renew --dry-run`

Certs should now be in /etc/letsencrypt/live/repel-aws.eha.io/
