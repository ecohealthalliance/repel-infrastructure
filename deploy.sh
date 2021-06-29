# script for the deploy section of the gitlab-ci.yml file

set -a
source .env
set +a

sshpass -p "${STAGING_SERVER_PASS}" \
    ssh -p "${STAGING_SERVER_SSH_PORT}" \
        -o StrictHostKeyChecking=no \
        -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no \
        ${STAGING_SERVER_USER}@${STAGING_SERVER_URL} \
        "mkdir -p ~/${STAGING_SERVER_DIR}"

sshpass -p "${STAGING_SERVER_PASS}" \
    scp -r -P "${STAGING_SERVER_SSH_PORT}" \
        -o StrictHostKeyChecking=no \
        -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no \
        $(pwd) ${STAGING_SERVER_USER}@${STAGING_SERVER_URL}:~/

if [[ "$RESTORE_PG_FROM_AWS" == "1" ]]
then
  sshpass -p "${STAGING_SERVER_PASS}" \
      ssh -p "${STAGING_SERVER_SSH_PORT}" \
          -o StrictHostKeyChecking=no \
          -o PreferredAuthentications=password \
          -o PubkeyAuthentication=no \
          ${STAGING_SERVER_USER}@${STAGING_SERVER_URL} \
          "echo ${STAGING_SERVER_PASS} | sudo -S ls \
            && cd ${STAGING_SERVER_DIR}; \
               sudo docker-compose down --volumes;"
fi

sshpass -p "${STAGING_SERVER_PASS}" \
    ssh -p "${STAGING_SERVER_SSH_PORT}" \
        -o StrictHostKeyChecking=no \
        -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no \
        ${STAGING_SERVER_USER}@${STAGING_SERVER_URL} \
        "echo ${STAGING_SERVER_PASS} | sudo -S ls \
          && echo ${DOCKER_REGISTRY_PASSWORD} \
            | sudo docker login ${DOCKER_REGISTRY} -u ${DOCKER_REGISTRY_USER} --password-stdin; \
              cd ${STAGING_SERVER_DIR}; \
              sudo docker-compose pull; \
              sudo docker-compose -f docker-compose.yml -f docker-compose-staging.yml up -d;"
