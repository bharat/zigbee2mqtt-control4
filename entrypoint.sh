#!/bin/sh
# Control4 fork-image entrypoint.
#
# The Control4 definition now ships in-tree (zigbee-herdsman-converters
# fork), so the legacy external converter must NOT load: external
# converters override in-tree definitions, and the legacy copy calls a
# private herdsman API this stack no longer needs. Disable it reversibly
# by renaming (z2m only auto-loads *.mjs), then hand off to the stock
# entrypoint.

DATA="${ZIGBEE2MQTT_DATA:-/app/data}"
LEGACY="$DATA/external_converters/control4.mjs"

if [ -f "$LEGACY" ]; then
    mv "$LEGACY" "$LEGACY.disabled"
    echo "[C4] Disabled legacy external converter (in-tree definition active): control4.mjs -> control4.mjs.disabled"
fi

exec docker-entrypoint.sh "$@"
