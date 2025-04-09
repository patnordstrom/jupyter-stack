#!/usr/bin/env bash

### load variables and set configs ###

set -Eeuo pipefail
_script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

source "${_script_dir}/vars.sh"


### declare functions ###

function create_volumes {

  docker volume create --name "${NOTEBOOK_DATA_VOLUME_NAME}"
  docker volume create --name "${CERT_VOLUME_NAME}"

}


function provision_cert {

  docker run --rm \
    -p 8080:80 \
    -v "${CERT_VOLUME_NAME}":/etc/letsencrypt \
    certbot/certbot certonly \
    --non-interactive \
    --keep-until-expiring \
    --standalone \
    --agree-tos \
    --domain "${SSL_CERT_FQDN}" \
    --email "${SSL_CERT_EMAIL}"

  docker run --rm \
    -v "${CERT_VOLUME_NAME}":/etc/letsencrypt \
    bash \
    -c \
    "chmod -R 755 /etc/letsencrypt"

}

function create_password_hash {

  export JUPYTER_LAB_WEB_PWD_HASH=$( \
    docker run --rm \
    quay.io/jupyter/base-notebook ipython -c \
    "from jupyter_server.auth import passwd; passwd('"${JUPYTER_LAB_WEB_PWD}"')" | \
    grep -Po "argon[^']+"
  )

}

function start_docker_services {

  docker compose -f "${_script_dir}/docker-compose.yaml" -p "${PROJECT_NAME}" up -d

}

### main script ###

create_volumes

provision_cert

create_password_hash

start_docker_services