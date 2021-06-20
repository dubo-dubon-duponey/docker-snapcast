#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

NAME=${NAME:-no name}

# XXX fix me with something useful
exec "$@"

# https://github.com/badaix/snapcast
# https://github.com/badaix/snapcast/blob/master/doc/build.md
# https://github.com/badaix/snapcast/blob/master/doc/build.md#linux-native
