# script for the deploy section of the gitlab-ci.yml file

set -a
source .env
set +a

restore_pg () {
  echo ${DEPLOYMENT_SERVER_PASS} | sudo -S ls \
    && cd ${DEPLOYMENT_SERVER_DIR}; sudo docker-compose down --volumes;
}

compose_up () {
  echo ${DEPLOYMENT_SERVER_PASS} | sudo -S ls \
    && echo ${CI_REGISTRY_PASSWORD} \
      | sudo docker login -u ${CI_REGISTRY_USER} --password-stdin ${CI_REGISTRY}; \
        cd ${DEPLOYMENT_SERVER_DIR}; sudo docker-compose pull; sudo docker-compose up -d;
}

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
          "$(typeset -f restore_pg); restore_pg"
fi

sshpass -p "${DEPLOYMENT_SERVER_PASS}" \
    ssh -p "${DEPLOYMENT_SERVER_SSH_PORT}" \
        -o StrictHostKeyChecking=no \
        -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no \
        ${DEPLOYMENT_SERVER_USER}@${DEPLOYMENT_SERVER_URL} \
        "echo ${DEPLOYMENT_SERVER_PASS} | sudo -S ls && echo ${CI_REGISTRY_PASSWORD} | sudo docker login -u ${CI_REGISTRY_USER} --password-stdin ${CI_REGISTRY}; cd ${DEPLOYMENT_SERVER_DIR}; sudo docker-compose pull; sudo docker-compose up -d;"

#        "$(typeset -f compose_up); compose_up"
