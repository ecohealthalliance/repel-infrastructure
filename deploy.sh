# script for the deploy section of the gitlab-ci.yml file

set -a
source .env
set +a

sshpass -p "${DEPLOYMENT_SERVER_PASS}" \
    ssh -p "${DEPLOYMENT_SERVER_SSH_PORT}" \
        -o StrictHostKeyChecking=no \
        -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no \
        ${DEPLOYMENT_SERVER_USER}@${DEPLOYMENT_SERVER_URL} \
        "mkdir -p ~/${DEPLOYMENT_SERVER_DIR}"

sshpass -p "${DEPLOYMENT_SERVER_PASS}" \
    scp -r -P "${DEPLOYMENT_SERVER_SSH_PORT}" \
        -o StrictHostKeyChecking=no \
        -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no \
        $(pwd) ${DEPLOYMENT_SERVER_USER}@${DEPLOYMENT_SERVER_URL}:~/

if [[ "$RESTORE_PG_FROM_AWS" == "1" ]]
then
  sshpass -p "${DEPLOYMENT_SERVER_PASS}" \
      ssh -p "${DEPLOYMENT_SERVER_SSH_PORT}" \
          -o StrictHostKeyChecking=no \
          -o PreferredAuthentications=password \
          -o PubkeyAuthentication=no \
          ${DEPLOYMENT_SERVER_USER}@${DEPLOYMENT_SERVER_URL} \
          "echo ${DEPLOYMENT_SERVER_PASS} | sudo -S ls \
            && cd ${DEPLOYMENT_SERVER_DIR}; \
               sudo docker-compose down --volumes;"
fi

sshpass -p "${DEPLOYMENT_SERVER_PASS}" \
    ssh -p "${DEPLOYMENT_SERVER_SSH_PORT}" \
        -o StrictHostKeyChecking=no \
        -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no \
        ${DEPLOYMENT_SERVER_USER}@${DEPLOYMENT_SERVER_URL} \
        "echo ${DEPLOYMENT_SERVER_PASS} | sudo -S ls \
          && echo ${DOCKER_REGISTRY_PASSWORD} \
            | sudo docker login ${DOCKER_REGISTRY} -u ${DOCKER_REGISTRY_USER} --password-stdin; \
              cd ${DEPLOYMENT_SERVER_DIR}; \
              sudo docker-compose pull; \
              sudo docker-compose -f docker-compose.yml -f docker-compose-production.yml up -d;"
