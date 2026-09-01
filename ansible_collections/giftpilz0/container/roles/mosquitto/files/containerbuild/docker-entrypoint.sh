#!/bin/sh
set -e

if [ "$(id -u)" = "0" ]; then
  chown -R "${PUID:-1883}:${PGID:-1883}" /mosquitto/data /mosquitto/log
fi

exec "$@"
