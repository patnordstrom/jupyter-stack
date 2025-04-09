#!/usr/bin/env bash

echo "Waiting for HTTP 200 Response from ${ENDPOINT}"
until [ "$(curl -s -o /dev/null -w "%{http_code}" "${ENDPOINT}")" == "200" ]; do
    sleep 10
done

echo "Jupyter Lab is ready."
echo "Login URL:  ${ENDPOINT}"
echo "Password:  $(terraform output -raw jupyter_lab_password)"