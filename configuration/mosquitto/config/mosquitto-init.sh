#!/bin/sh
# Builds the Mosquitto password file from environment variables on every
# start, then hands over to the image's normal entrypoint.
set -e

: "${MQTT_CHIRPSTACK_PASSWORD:?MQTT_CHIRPSTACK_PASSWORD is required}"
: "${MQTT_GATEWAY_BRIDGE_PASSWORD:?MQTT_GATEWAY_BRIDGE_PASSWORD is required}"
: "${MQTT_ORION_PASSWORD:?MQTT_ORION_PASSWORD is required}"

PW=/mosquitto/config/passwd
rm -f "$PW"
touch "$PW"
chmod 0700 "$PW"
mosquitto_passwd -b "$PW" chirpstack "$MQTT_CHIRPSTACK_PASSWORD"
mosquitto_passwd -b "$PW" gateway-bridge "$MQTT_GATEWAY_BRIDGE_PASSWORD"
mosquitto_passwd -b "$PW" orion "$MQTT_ORION_PASSWORD"
chown mosquitto:mosquitto "$PW"

exec /docker-entrypoint.sh /usr/sbin/mosquitto -c /mosquitto/config/mosquitto.conf
