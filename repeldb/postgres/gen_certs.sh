#!/bin/bash

# This directory is optional, but will use it to keep the CA root key safe
mkdir keys certs
chmod og-rwx /keys /certs

mkdir -p pgkeys
# Create a key-pair that will serve both as the root CA and the server key-pair
# the "ca.crt" name is used to match what it expects later
openssl req -new -x509 -days 365 -nodes -out certs/ca.crt \
  -keyout keys/ca.key -subj "/CN=root-ca"
cp certs/ca.crt pgkeys/ca.crt

# Create the server key and CSR and sign with root key
openssl req -new -nodes -out server.csr \
  -keyout pgkeys/server.key -subj "/CN=localhost"

openssl x509 -req -in server.csr -days 365 \
    -CA certs/ca.crt -CAkey keys/ca.key -CAcreateserial \
    -out pgkeys/server.crt

# remove the CSR as it is no longer needed
rm server.csr


# give the postgres user control of keys and certs
chown postgres pgkeys/*
chmod 600 pgkeys/server.crt pgkeys/server.key
