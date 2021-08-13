#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

NAME=${NAME:-no name}


helpers::dbus(){
  # On container restart, cleanup the crap
  rm -f /run/dbus/pid

  # https://linux.die.net/man/1/dbus-daemon-1
  dbus-daemon --system

  until [ -e /run/dbus/system_bus_socket ]; do
    sleep 1s
  done
}

helpers::avahi(){
  # On container restart, cleanup the crap
  rm -f /run/avahi-daemon/pid

  # Set the hostname, if we have it
  sed -i'' -e "s,%AVAHI_NAME%,$AVAHI_NAME,g" /data/avahi-daemon.conf

  # https://linux.die.net/man/8/avahi-daemon
  avahi-daemon -f /data/avahi-daemon.conf --daemonize --no-chroot
}

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

#  helpers::dbus
#  helpers::avahi

# XXX probably the config should be generated on the fly and be editable
if [ "$MODE" == "server" ]; then
  raw="$(printf '{"Type": "%s", "Name": "%s", "Host": "%s", "Port": %s, "Text": {}}' "_snapcast._tcp" "$MDNS_NAME" "$MDNS_HOST" "1704")"
  stream="$(printf '{"Type": "%s", "Name": "%s", "Host": "%s", "Port": %s, "Text": {}}' "_snapcast-stream._tcp" "$MDNS_NAME" "$MDNS_HOST" "1704")"
  tcp="$(printf '{"Type": "%s", "Name": "%s", "Host": "%s", "Port": %s, "Text": {}}' "_snapcast-tcp._tcp" "$MDNS_NAME" "$MDNS_HOST" "1705")"
  http="$(printf '{"Type": "%s", "Name": "%s", "Host": "%s", "Port": %s, "Text": {}}' "_snapcast-http._tcp" "$MDNS_NAME" "$MDNS_HOST" "1780")"
  jsonrpc="$(printf '{"Type": "%s", "Name": "%s", "Host": "%s", "Port": %s, "Text": {}}' "_snapcast-jsonrpc._tcp" "$MDNS_NAME" "$MDNS_HOST" "1705")"
  goello-server -json "$(printf '[%s, %s, %s, %s, %s]' "$raw" "$stream" "$tcp" "$http" "$jsonrpc")" &
  HOME=/tmp exec snapserver --config /config/snapserver/main.conf
fi

#    if [ "${MDNS_ENABLED:-}" == true ]; then
#    fi

# HOST=$(goello-client  $MDNS_HOST.local)

[ -e "/data/host_UUID" ] || head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64 > /data/host_UUID
UUID="$(cat /data/host_UUID)"

server="$(goello-client -t "_snapcast-tcp._tcp" -n "$MDNS_HOST")"
server="$(print "%s" "$server" | jq -rc .IPs[])"
port="$(print "%s" "$server" | jq -rc .Port)"

# Log levels [trace,debug,info,notice,warning,error,fatal]
# Mixers: software|hardware|script|none
# Player could be file (not sure how to use the Sonos yet...)
exec snapclient \
  --logsink stdout \
  --player alsa \
  --mixer none \
  --mstderr \
  --hostID "$UUID" \
  --host "$server" \
  --port "$port" \
  --logfilter *:"$(printf "%s" "${LOG_LEVEL:-error}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^(warn)$/warning/')"

# --soundcard default:CARD=Qutest
#  --instance "$NB"
#  -l, --list                      list PCM devices
#  --soundcard arg (=default)  index or name of the pcm device
