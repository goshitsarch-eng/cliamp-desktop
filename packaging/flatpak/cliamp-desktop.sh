#!/bin/sh
# Launch the Flutter bundle. The Go engine is the cliamp binary beside it.
export ALSA_CONFIG_PATH="${ALSA_CONFIG_PATH:-/app/etc/asound.conf}"
exec /app/cliamp/cliamp_desktop "$@"
