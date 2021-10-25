#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]:-$PWD}")" 2>/dev/null 1>&2 && pwd)"
readonly root
# shellcheck source=/dev/null
source "$root/helpers.sh"
# shellcheck source=/dev/null
source "$root/mdns.sh"

#### Server
if [ "$MODE" == "server" ]; then
  [ ! "${MDNS_HOST:-}" ] || {
    [ ! "${MDNS_STATION:-}" ] || mdns::records::add "_workstation._tcp" "$MDNS_HOST" "${MDNS_NAME:-}" "1704"
    mdns::records::add "$MDNS_TYPE" "$MDNS_HOST" "${MDNS_NAME:-}" "1704"
    mdns::records::add "_snapcast-stream._tcp" "$MDNS_HOST" "${MDNS_NAME:-}" "1704"
#    mdns::records::add "_snapcast-tcp._tcp" "$MDNS_HOST" "${MDNS_NAME:-}" "1705"
#    mdns::records::add "_snapcast-jsonrpc._tcp" "$MDNS_HOST" "${MDNS_NAME:-}" "1705"
    mdns::records::add "_snapcast-http._tcp" "$MDNS_HOST" "${MDNS_NAME:-}" "443"
    mdns::records::broadcast &
  }
  start::sidecar &

  XDG_CONFIG_HOME=/tmp/config

  # https://github.com/badaix/snapcast/issues/231
  # https://github.com/badaix/snapcast/blob/master/server/etc/snapserver.conf
  args=( \
    --logging.sink=stdout \
    --logging.filter="*:$(printf "%s" "${LOG_LEVEL:-error}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^(warn)$/warning/')" \
    --server.datadir="$XDG_CONFIG_HOME" \
    --http.bind_to_address="127.0.0.1" \
    --http.port=10042 \
    --tcp.enabled=false \
  )
  while read -r line; do
    [ ! "$line" ] || args+=(--stream.source="$line")
  done <<<"$SOURCES"

  exec snapserver "${args[@]}" "$@"
fi

#### Client
_uuid="$(cat /data/host_UUID 2>/dev/null || head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64 | tee /data/host_UUID)"

[ "${MDNS_NSS_ENABLED:-}" != true ] || mdns::resolver::start

args=(--logsink stdout --mstderr --hostID "$_uuid" --host "$SNAPCAST_SERVER" --port "1704" --player alsa)
[ ! "${DEVICE:-}" ] || args+=(--soundcard "$DEVICE")
[ ! "${MIXER:-}" ] && args+=(--mixer none) || args+=(--mixer "hardware:$MIXER")

# Log levels [trace,debug,info,notice,warning,error,fatal]
exec snapclient "${args[@]}" \
  --logfilter "*:$(printf "%s" "${LOG_LEVEL:-error}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^(warn)$/warning/')" \
  "$@"
