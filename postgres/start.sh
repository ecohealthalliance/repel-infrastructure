#!/bin/bash

set -e

/docker-entrypoint-initdb.d/01-initdb.sh

/docker-entrypoint-initdb.d/02-usraccts.sh
