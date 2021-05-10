#!/usr/bin/bash

cd /root/docker
set -a
source .env
set +a
#envsubst < "docker-compose-minlocal.yml" > "docker-compose-minlocal-new.yml"
