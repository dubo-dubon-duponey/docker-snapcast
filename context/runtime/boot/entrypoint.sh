#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]:-$PWD}")" 2>/dev/null 1>&2 && pwd)"
readonly root
# shellcheck source=/dev/null
source "$root/helpers.sh"
# shellcheck source=/dev/null
source "$root/mdns.sh"

# mDNS blast if asked to
if [ "$MODE" == "server" ]; then
  [ ! "${MDNS_HOST:-}" ] || {
    [ ! "${MDNS_STATION:-}" ] || mdns::add "_workstation._tcp" "$MDNS_HOST" "${MDNS_NAME:-}" "$PORT"
    mdns::add "$MDNS_TYPE" "$MDNS_HOST" "${MDNS_NAME:-}" "1704"
    mdns::add "_snapcast-stream._tcp" "$MDNS_HOST" "${MDNS_NAME:-}" "1704"
    mdns::add "_snapcast-tcp._tcp" "$MDNS_HOST" "${MDNS_NAME:-}" "1705"
    mdns::add "_snapcast-http._tcp" "$MDNS_HOST" "${MDNS_NAME:-}" "1780"
    mdns::add "_snapcast-jsonrpc._tcp" "$MDNS_HOST" "${MDNS_NAME:-}" "1705"
    mdns::start &
  }
fi

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

# HOST=$(goello-client  $MDNS_HOST.local)


if [ "$MODE" == "server" ]; then
  HOME=/tmp exec snapserver --config /config/snapserver/main.conf
fi

if [ "$NOU" ]; then
  [ -e "/data/host_UUID" ] || head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64 > /data/host_UUID
  UUID="$(cat /data/host_UUID)"

  server="$(goello-client -t "_snapcast._tcp" -n "$MDNS_HOST")"
  port="$(printf "%s" "$server" | jq -rc .Port)"
  server="$(printf "%s" "$server" | jq -rc .IPs[])"
else
  helpers::dir::writable "/run/avahi-daemon" create
  rm -f /run/avahi-daemon/pid
  avahi-daemon --daemonize --no-drop-root --no-chroot
  server="$MDNS_HOST"
  port=1704
fi

# Log levels [trace,debug,info,notice,warning,error,fatal]

args=(--logsink stdout --mstderr --hostID "$UUID" --host "$server" --port "$port" --player alsa)
[ ! "${DEVICE:-}" ] || args+=(--soundcard "$DEVICE")
[ ! "${MIXER:-}" ] && args+=(--mixer none) || args+=(--mixer "hardware:$MIXER")

exec snapclient "${args[@]}" \
  --logfilter "*:$(printf "%s" "${LOG_LEVEL:-error}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^(warn)$/warning/')" \
  "$@"
