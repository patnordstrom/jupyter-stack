#!/usr/bin/env bash

echo "Waiting for $DOMAIN -> $IP"
until [ "$(dig +short @ns1.linode.com ${DOMAIN})" == "${IP}" ]; do
    sleep 10
done