ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_FETCHER=base:golang-bullseye-2021-11-01@sha256:27069d776a0cd49bc03119db3b15ff763bf13a54c7f5ebd97dd16a399f06d934
ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2021-11-01@sha256:23e78693390afaf959f940de6d5f9e75554979d84238503448188a7f30f34a7d
ARG           FROM_IMAGE_AUDITOR=base:auditor-bullseye-2021-11-01@sha256:965d2e581c2b824bc03853d7b736c6b8e556e519af2cceb30c39c77ee0178404
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2021-11-01@sha256:8ee6c2243bacfb2ec1a0010a9b1bf41209330ae940c6f88fee9c9e99f9cb705d
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2021-11-01@sha256:c29f582f211999ba573b8010cdf623e695cc0570d2de6c980434269357a3f8ef

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools

# https://github.com/badaix/snapcast
# https://github.com/badaix/snapcast/blob/master/doc/build.md
# https://github.com/badaix/snapcast/blob/master/doc/build.md#linux-native

#######################
# Fetcher
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_FETCHER                                              AS fetcher

ARG           GIT_REPO=github.com/badaix/snapcast
ARG           GIT_VERSION=v0.25.0
ARG           GIT_COMMIT=2af5292f9df9e8f5a54114ed0ef96ca25cd32135

RUN           git clone --recurse-submodules git://"$GIT_REPO" .; git checkout "$GIT_COMMIT"

ARG           BOOST_VERSION=76
WORKDIR       /dependencies

# XXXFIXME hey jfrog, what about upgrading your infrastructure to tls1.3?
RUN           --mount=type=secret,id=CA \
              --mount=type=secret,id=CERTIFICATE \
              --mount=type=secret,id=KEY \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=.curlrc \
              curl --tlsv1.2 -sSfL -o boost.tar.gz "https://boostorg.jfrog.io/artifactory/main/release/1.${BOOST_VERSION}.0/source/boost_1_${BOOST_VERSION}_0.tar.gz"

RUN           tar -xf boost.tar.gz; mv boost_1_${BOOST_VERSION}_0 boost

FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS builder-cross

ARG           TARGETARCH
ARG           TARGETVARIANT

COPY          --from=fetcher /source        /source
COPY          --from=fetcher /dependencies  /dependencies

RUN           --mount=type=secret,uid=100,id=CA \
              --mount=type=secret,uid=100,id=CERTIFICATE \
              --mount=type=secret,uid=100,id=KEY \
              --mount=type=secret,uid=100,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_CONFIG \
              eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/^armv6$/armel/" -e "s/^armv7$/armhf/" -e "s/^ppc64le$/ppc64el/" -e "s/^386$/i386/")")"; \
              apt-get update -qq && \
              apt-get install -qq --no-install-recommends \
                libasound2-dev:"$DEB_TARGET_ARCH"=1.2.4-1.1 \
                libsoxr-dev:"$DEB_TARGET_ARCH"=0.1.3-4 \
                libvorbisidec-dev:"$DEB_TARGET_ARCH"=1.2.1+git20180316-7 \
                libvorbis-dev:"$DEB_TARGET_ARCH"=1.3.7-1 \
                libopus-dev:"$DEB_TARGET_ARCH"=1.3.1-0.1 \
                libflac-dev:"$DEB_TARGET_ARCH"=1.3.3-2 \
                libavahi-client-dev:"$DEB_TARGET_ARCH"=0.8-5 \
                libexpat1-dev:"$DEB_TARGET_ARCH"=2.2.10-2 \
                libboost-dev:"$DEB_TARGET_ARCH"=1.74.0.3

#                libstdc++-10-dev:"$DEB_TARGET_ARCH"=10.2.1-6 \
#              export CMAKE_C_COMPILER="$CC"; \
#              export CMAKE_CXX_COMPILER="$CXX"; \

WORKDIR       /source

RUN           eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/^armv6$/armel/" -e "s/^armv7$/armhf/" -e "s/^ppc64le$/ppc64el/" -e "s/^386$/i386/")")"; \
              export PKG_CONFIG="${DEB_TARGET_GNU_TYPE}-pkg-config"; \
              export AR="${DEB_TARGET_GNU_TYPE}-ar"; \
              export CC="${DEB_TARGET_GNU_TYPE}-gcc"; \
              export CXX="${DEB_TARGET_GNU_TYPE}-g++"; \
              sed -Ei "s/CXX       = g[+][+]/CXX     = $CXX/" client/Makefile; \
              sed -Ei "s/ -DHAS_PULSE//" client/Makefile; \
              sed -Ei "s/ -lpulse//" client/Makefile; \
              sed -Ei "s/ player\/pulse_player.o//" client/Makefile; \
              ADD_CFLAGS="-I/dependencies/boost/ -I/usr/include" make -C client

RUN           eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/^armv6$/armel/" -e "s/^armv7$/armhf/" -e "s/^ppc64le$/ppc64el/" -e "s/^386$/i386/")")"; \
              export PKG_CONFIG="${DEB_TARGET_GNU_TYPE}-pkg-config"; \
              export AR="${DEB_TARGET_GNU_TYPE}-ar"; \
              export CC="${DEB_TARGET_GNU_TYPE}-gcc"; \
              export CXX="${DEB_TARGET_GNU_TYPE}-g++"; \
              sed -Ei "s/CXX       = g[+][+]/CXX     = $CXX/" server/Makefile; \
              sed -Ei "s/ -DHAS_AVAHI//" server/Makefile; \
              sed -Ei "s/ -lavahi-client -lavahi-common//" server/Makefile; \
              sed -Ei "s/ publishZeroConf\/publish_avahi.o//" server/Makefile; \
              ADD_CFLAGS="-I/dependencies/boost/ -I/usr/include" make -C server

RUN           mkdir -p /dist/boot/bin; \
              cp client/snapclient /dist/boot/bin; \
              cp server/snapserver /dist/boot/bin

RUN           mkdir -p /dist/boot/lib; \
              eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/^armv6$/armel/" -e "s/^armv7$/armhf/" -e "s/^ppc64le$/ppc64el/" -e "s/^386$/i386/")")"; \
              cp /usr/lib/"$DEB_TARGET_MULTIARCH"/libogg.so.0           /dist/boot/lib; \
              cp /usr/lib/"$DEB_TARGET_MULTIARCH"/libFLAC.so.8          /dist/boot/lib; \
              cp /usr/lib/"$DEB_TARGET_MULTIARCH"/libopus.so.0          /dist/boot/lib; \
              cp /usr/lib/"$DEB_TARGET_MULTIARCH"/libsoxr.so.0          /dist/boot/lib; \
              cp /usr/lib/"$DEB_TARGET_MULTIARCH"/libasound.so.2        /dist/boot/lib; \
              cp /usr/lib/"$DEB_TARGET_MULTIARCH"/libvorbis.so.0        /dist/boot/lib; \
              cp /usr/lib/"$DEB_TARGET_MULTIARCH"/libvorbisenc.so.2     /dist/boot/lib; \
              cp /usr/lib/"$DEB_TARGET_MULTIARCH"/libavahi-client.so.3  /dist/boot/lib; \
              cp /usr/lib/"$DEB_TARGET_MULTIARCH"/libavahi-common.so.3  /dist/boot/lib; \
              cp /usr/lib/"$DEB_TARGET_MULTIARCH"/libgomp.so.1          /dist/boot/lib; \
              cp /usr/lib/"$DEB_TARGET_MULTIARCH"/libstdc++.so.6        /dist/boot/lib

#######################
# Builder assembly
#######################
FROM          $FROM_REGISTRY/$FROM_IMAGE_AUDITOR                                              AS assembly

RUN           --mount=type=secret,uid=100,id=CA \
              --mount=type=secret,uid=100,id=CERTIFICATE \
              --mount=type=secret,uid=100,id=KEY \
              --mount=type=secret,uid=100,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_CONFIG \
              apt-get update -qq && apt-get install -qq --no-install-recommends \
                libnss-mdns=0.14.1-2 && \
              apt-get -qq autoremove      && \
              apt-get -qq clean           && \
              rm -rf /var/lib/apt/lists/* && \
              rm -rf /tmp/*               && \
              rm -rf /var/tmp/*

COPY          --from=builder-cross  /dist/boot                  /dist/boot
COPY          --from=builder-tools  /boot/bin/goello-server-ng  /dist/boot/bin
# COPY          --from=builder-tools  /boot/bin/goello-client  /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/caddy             /dist/boot/bin

RUN           setcap 'cap_net_bind_service+ep'          /dist/boot/bin/caddy

RUN           cp /usr/sbin/avahi-daemon                 /dist/boot/bin
RUN           setcap 'cap_chown+ei cap_dac_override+ei' /dist/boot/bin/avahi-daemon

# hadolint ignore=SC2016
RUN           patchelf --set-rpath '$ORIGIN/../lib'           /dist/boot/bin/snapclient; \
              patchelf --set-rpath '$ORIGIN/../lib'           /dist/boot/bin/snapserver; \
              patchelf --set-rpath '$ORIGIN/../lib'           /dist/boot/lib/libvorbisenc.so.2; \
              patchelf --set-rpath '$ORIGIN/../lib'           /dist/boot/lib/libvorbis.so.0; \
              patchelf --set-rpath '$ORIGIN/../lib'           /dist/boot/lib/libsoxr.so.0; \
              patchelf --set-rpath '$ORIGIN/../lib'           /dist/boot/lib/libFLAC.so.8

# XXX              NO_SYSTEM_LINK=true \
# RUN           BIND_NOW=true \
#RUN           [ "$TARGETARCH" != "amd64" ] || export STACK_CLASH=true; \
RUN           RUNNING=true \
              BIND_NOW=true \
              PIE=true \
              FORTIFIED=true \
              STACK_PROTECTED=true \
              RO_RELOCATIONS=true \
                dubo-check validate /dist/boot/bin/snapclient

RUN           RUNNING=true \
              PIE=true \
              FORTIFIED=true \
              STACK_PROTECTED=true \
              RO_RELOCATIONS=true \
                dubo-check validate /dist/boot/bin/snapserver

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;


#######################
# Running image
#######################
FROM          $FROM_REGISTRY/$FROM_IMAGE_RUNTIME

USER          root

# nss-mdns is not needed by the server
# jq is only needed if not relying on goello
# libasound is not needed by the server, but the client complains about missing
# /usr/share/alsa/alsa.conf which can maybe be copied over instead
RUN           --mount=type=secret,uid=100,id=CA \
              --mount=type=secret,uid=100,id=CERTIFICATE \
              --mount=type=secret,uid=100,id=KEY \
              --mount=type=secret,uid=100,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_CONFIG \
              apt-get update -qq \
              && apt-get install -qq --no-install-recommends \
                libasound2=1.2.4-1.1 \
                libnss-mdns=0.14.1-2 \
                jq=1.6-2.1 \
              && apt-get -qq autoremove       \
              && apt-get -qq clean            \
              && rm -rf /var/lib/apt/lists/*  \
              && rm -rf /tmp/*                \
              && rm -rf /var/tmp/*

# Deviate avahi shite into /tmp - only matters for client
RUN           ln -s "$XDG_STATE_HOME"/avahi-daemon /run

USER          dubo-dubon-duponey

COPY          --from=assembly --chown=$BUILD_UID:root /dist /

# server or client - XXX maybe split these images
ENV           MODE="server"
ENV           SOURCES=""

####### Server only
ENV           _SERVICE_NICK="snap"
ENV           _SERVICE_TYPE="snapcast"

### Front server configuration
## Advanced settings that usually should not be changed
# Ports for http and https - recent changes in docker make it no longer necessary to have caps, plus we have our NET_BIND_SERVICE cap set anyhow - it's 2021, there is no reason to keep on venerating privileged ports
ENV           ADVANCED_PORT_HTTPS=443
ENV           ADVANCED_PORT_HTTP=80
EXPOSE        443
EXPOSE        80
# By default, tls should be restricted to 1.3 - you may downgrade to 1.2+ for compatibility with older clients (webdav client on macos, older browsers)
ENV           ADVANCED_TLS_MIN=1.3
# Name advertised by Caddy in the server http header
ENV           ADVANCED_SERVER_NAME="DuboDubonDuponey/1.0 (Caddy/2) [$_SERVICE_NICK]"
# Root certificate to trust for mTLS - this is not used if MTLS is disabled
ENV           ADVANCED_MTLS_TRUST="/certs/mtls_ca.crt"
# Log verbosity for
ENV           LOG_LEVEL="warn"
# Whether to start caddy at all or not
ENV           PROXY_HTTPS_ENABLED=true
# Domain name to serve
ENV           DOMAIN="$_SERVICE_NICK.local"
ENV           ADDITIONAL_DOMAINS="https://*.debian.org"
# Control wether tls is going to be "internal" (eg: self-signed), or alternatively an email address to enable letsencrypt - use "" to disable TLS entirely
ENV           TLS="internal"
# Issuer name to appear in certificates
#ENV           TLS_ISSUER="Dubo Dubon Duponey"
# Either disable_redirects or ignore_loaded_certs if one wants the redirects
ENV           TLS_AUTO=disable_redirects
# Staging
# https://acme-staging-v02.api.letsencrypt.org/directory
# Plain
# https://acme-v02.api.letsencrypt.org/directory
# PKI
# https://pki.local
ENV           TLS_SERVER="https://acme-v02.api.letsencrypt.org/directory"
# Either require_and_verify or verify_if_given, or "" to disable mTLS altogether
ENV           MTLS="require_and_verify"
# Realm for authentication - set to "" to disable authentication entirely
ENV           AUTH="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           AUTH_USERNAME="dubo-dubon-duponey"
ENV           AUTH_PASSWORD="cmVwbGFjZV9tZV93aXRoX3NvbWV0aGluZwo="

# Caddy will server on that domain
ENV           DOMAIN="$_SERVICE_NICK.local"
ENV           ADDITIONAL_DOMAINS=""
ENV           ADVANCED_PORT_HTTP=80
ENV           ADVANCED_PORT_HTTPS=443
ENV           TLS_SERVER="https://acme-v02.api.letsencrypt.org/directory"

### mDNS broadcasting
# The service will be annonced and reachable at $MDNS_HOST.local (set to empty string to disable mDNS announces entirely)
ENV           MDNS_HOST="$_SERVICE_NICK"
# Name is used as a short description for the service
ENV           MDNS_NAME="$_SERVICE_NICK mDNS display name"
# Whether to enable MDNS broadcasting or not
ENV           MDNS_ENABLED=true
# Type to advertise
ENV           MDNS_TYPE="_$_SERVICE_TYPE._tcp"
# Also announce the service as a workstation (for example for the benefit of coreDNS mDNS)
ENV           MDNS_STATION=true

# Stream, RPC, and Caddy
EXPOSE        1704/tcp
EXPOSE        1705/tcp
EXPOSE        443/tcp

# This is used by caddy to create the endpoint, so, mandatory even without active checks
ENV           HEALTHCHECK_URL="http://127.0.0.1:10000/?healthcheck"
#HEALTHCHECK --interval=120s --timeout=30s --start-period=10s --retries=1 CMD rtsp-health || exit 1


####### Client only
ENV           MDNS_NSS_ENABLED=true
ENV           SNAPCAST_SERVER="snappy.local"
ENV           SNAPCAST_TCP_ENABLED=false

# Alsa device and mixer to use
ENV           DEVICE=""
ENV           MIXER=""

# If using avahi, need run to be writable
# VOLUME        /run
