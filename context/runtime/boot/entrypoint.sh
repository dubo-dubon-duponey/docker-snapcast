#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

NAME=${NAME:-no name}

# https://github.com/badaix/snapcast
# https://github.com/badaix/snapcast/blob/master/doc/build.md
# https://github.com/badaix/snapcast/blob/master/doc/build.md#linux-native


# For the client: --player <name>:? for options
# Serve has webapp included at http://<snapserver host>:1780

# Disable AVAHI_FOUND and BONJOUR_FOUND to remove announce

# Working hypotheses (is this per-person?):
# 1 librespot on nuc
# 1 airplay on nuc
# 1 roon bridge on nuc?
# ----> 1 snapcast server

# ----> n snapcast clients, per speaker

# Better separate the client and server in two different images?

[ -e "/data/host_UUID" ] || head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64 > /data/host_UUID
UUID="$(cat /data/host_UUID)"

exec snapserver --config /config/snapserver/main.conf

# Log levels [trace,debug,info,notice,warning,error,fatal]
# Mixers: software|hardware|script|none
# Player could be file (not sure how to use the Sonos yet...)
exec snapclient \
  --logsink stdout \
  --player alsa \
  --mixer none \
  --mstderr \
  --hostID "$UUID" \
  --host "$DOMAIN" \
  --port "$PORT" \
  --logfilter *:"$(printf "$LOG_LEVEL" | tr '[:upper:]' '[:lower:]' | sed -i 's/^(warn)$/warning/')"

#  --instance "$NB"
#  -l, --list                      list PCM devices
#  --soundcard arg (=default)  index or name of the pcm device
