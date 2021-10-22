ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_FETCHER=base:golang-bullseye-2021-10-15@sha256:a35b057a1f360f1af4bc4743ca82cc3dbfce7c06599fcc6b531d592cbbf2fe12
ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2021-10-15@sha256:1609d1af44c0048ec0f2e208e6d4e6a525c6d6b1c0afcc9d71fccf985a8b0643
ARG           FROM_IMAGE_AUDITOR=base:auditor-bullseye-2021-10-15@sha256:2c95e3bf69bc3a463b00f3f199e0dc01cab773b6a0f583904ba6766b3401cb7b
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2021-10-15@sha256:4de02189b785c865257810d009e56f424d29a804cc2645efb7f67b71b785abde
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2021-10-15@sha256:5c54594a24e3dde2a82e2027edd6d04832204157e33775edc66f716fa938abba

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools


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

WORKDIR       /source

RUN           eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/^armv6$/armel/" -e "s/^armv7$/armhf/" -e "s/^ppc64le$/ppc64el/" -e "s/^386$/i386/")")"; \
              export PKG_CONFIG="${DEB_TARGET_GNU_TYPE}-pkg-config"; \
              export AR="${DEB_TARGET_GNU_TYPE}-ar"; \
              export CC="${DEB_TARGET_GNU_TYPE}-gcc"; \
              export CXX="${DEB_TARGET_GNU_TYPE}-g++"; \
              export CMAKE_C_COMPILER="$CC"; \
              export CMAKE_CXX_COMPILER="$CXX"; \
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
              export CMAKE_C_COMPILER="$CC"; \
              export CMAKE_CXX_COMPILER="$CXX"; \
              sed -Ei "s/CXX       = g[+][+]/CXX     = $CXX/" server/Makefile; \
              sed -Ei "s/ -DHAS_AVAHI//" client/Makefile; \
              sed -Ei "s/ -lavahi-client -lavahi-common//" client/Makefile; \
              sed -Ei "s/ publishZeroConf\/publish_avahi.o//" client/Makefile; \
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

COPY          --from=builder-cross  /dist/boot           /dist/boot
COPY          --from=builder-tools  /boot/bin/goello-server-ng  /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/goello-client  /dist/boot/bin

RUN           cp /usr/sbin/avahi-daemon                 /dist/boot/bin
RUN           setcap 'cap_chown+ei cap_dac_override+ei' /dist/boot/bin/avahi-daemon

# hadolint ignore=SC2016
RUN           patchelf --set-rpath '$ORIGIN/../lib'           /dist/boot/bin/snapclient
# hadolint ignore=SC2016
RUN           patchelf --set-rpath '$ORIGIN/../lib'           /dist/boot/bin/snapserver

RUN           patchelf --set-rpath '$ORIGIN/../lib'           /dist/boot/lib/libvorbisenc.so.2
RUN           patchelf --set-rpath '$ORIGIN/../lib'           /dist/boot/lib/libvorbis.so.0
RUN           patchelf --set-rpath '$ORIGIN/../lib'           /dist/boot/lib/libsoxr.so.0
RUN           patchelf --set-rpath '$ORIGIN/../lib'           /dist/boot/lib/libFLAC.so.8

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

RUN           --mount=type=secret,uid=100,id=CA \
              --mount=type=secret,uid=100,id=CERTIFICATE \
              --mount=type=secret,uid=100,id=KEY \
              --mount=type=secret,uid=100,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_CONFIG \
              apt-get update -qq \
              && apt-get install -qq --no-install-recommends \
                libnss-mdns=0.14.1-2 \
                jq=1.6-2.1 \
              && apt-get -qq autoremove       \
              && apt-get -qq clean            \
              && rm -rf /var/lib/apt/lists/*  \
              && rm -rf /tmp/*                \
              && rm -rf /var/tmp/*

RUN           mkdir -p /run/avahi-daemon \
              && chown "$BUILD_UID":root /run/avahi-daemon \
              && chmod 775 /run/avahi-daemon

VOLUME        /run

#                libavahi-client3=0.8-5 \
#                libavahi-common3=0.8-5 \
#                dbus=1.12.20-2 \
#                avahi-daemon=0.8-5 \
#                libatomic1=10.2.1-6 \
#                libpulse0=14.2-2 \

#RUN           dbus-uuidgen --ensure \
#              && mkdir -p /run/dbus \
#              && mkdir -p /run/avahi-daemon \
#              && chown "$BUILD_UID":root /run/dbus \
#              && chown "$BUILD_UID":root /run/avahi-daemon \
#              && chmod 775 /run/avahi-daemon \
#              && chmod 775 /run/dbus

USER          dubo-dubon-duponey

COPY          --from=assembly --chown=$BUILD_UID:root /dist /

ENV           MODE="server"
ENV           _SERVICE_NICK="snap"
ENV           _SERVICE_TYPE="snapcast"

ENV           DOMAIN="$_SERVICE_NICK.local"
ENV           ADDITIONAL_DOMAINS=""
ENV           PORT=1704
EXPOSE        $PORT/tcp

### mDNS broadcasting
# Type to advertise
ENV           MDNS_TYPE="_$_SERVICE_TYPE._tcp"
# Name is used as a short description for the service
ENV           MDNS_NAME="$_SERVICE_NICK mDNS display name"
# The service will be annonced and reachable at $MDNS_HOST.local (set to empty string to disable mDNS announces entirely)
ENV           MDNS_HOST="$_SERVICE_NICK"
# Also announce the service as a workstation (for example for the benefit of coreDNS mDNS)
ENV           MDNS_STATION=true

####### Client only
ENV           DEVICE=""
ENV           MIXER=""


#ENV           NAME=TotaleCroquette

# ENV           HEALTHCHECK_URL=rtsp://127.0.0.1:5000

#EXPOSE        5000/tcp
#EXPOSE        6001-6011/udp

#HEALTHCHECK --interval=120s --timeout=30s --start-period=10s --retries=1 CMD rtsp-health || exit 1

