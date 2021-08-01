ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2021-07-01@sha256:f1c46316c38cc1ca54fd53b54b73797b35ba65ee727beea1a5ed08d0ad7e8ccf
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2021-07-01@sha256:9f5b20d392e1a1082799b3befddca68cee2636c72c502aa7652d160896f85b36
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2021-07-01@sha256:f1e25694fe933c7970773cb323975bb5c995fa91d0c1a148f4f1c131cbc5872c

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools


#######################
# Fetcher
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-main

ENV           GIT_REPO=github.com/badaix/snapcast
ENV           GIT_VERSION=0.25.0
ENV           GIT_COMMIT=2af5292f9df9e8f5a54114ed0ef96ca25cd32135

RUN           git clone --recurse-submodules git://"$GIT_REPO" .
RUN           git checkout "$GIT_COMMIT"

#######################
# Building image - XXX not ready for X-pile yet - should also copy over libraries (see shairport for inspiration)
#######################
FROM          fetcher-main                                                                                              AS builder-main

ARG           BOOST_VERSION=76
WORKDIR       /tmp/boost

# XXXFIXME hey jfrog, what about upgrading your infrastructure to 1.3?
RUN           --mount=type=secret,id=CA \
              --mount=type=secret,id=CERTIFICATE \
              --mount=type=secret,id=KEY \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=.curlrc \
              curl --tlsv1.2 -sSfL -o boost.tgz "https://boostorg.jfrog.io/artifactory/main/release/1.${BOOST_VERSION}.0/source/boost_1_${BOOST_VERSION}_0.tar.bz2"

RUN           tar -xf boost.tgz

RUN           --mount=type=secret,uid=100,id=CA \
              --mount=type=secret,uid=100,id=CERTIFICATE \
              --mount=type=secret,uid=100,id=KEY \
              --mount=type=secret,uid=100,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_CONFIG \
              apt-get update -qq && \
              apt-get install -qq --no-install-recommends \
                libasound2-dev=1.2.4-1.1 \
                libsoxr-dev=0.1.3-4 \
                libpulse-dev=14.2-2 \
                libvorbisidec-dev=1.2.1+git20180316-7 \
                libvorbis-dev=1.3.7-1 \
                libopus-dev=1.3.1-0.1 \
                libflac-dev=1.3.3-2 \
                alsa-utils=1.2.4-1 \
                libavahi-client-dev=0.8-5 \
                avahi-daemon=0.8-5 \
                libexpat1-dev=2.2.10-2 \
                libboost-dev=1.74.0.3

WORKDIR       /source

RUN           ADD_CFLAGS="-I/tmp/boost/boost_1_${BOOST_VERSION}_0/" make client
RUN           ADD_CFLAGS="-I/tmp/boost/boost_1_${BOOST_VERSION}_0/" make server
RUN           mkdir -p /dist/boot/bin
RUN           cp client/snapclient /dist/boot/bin
RUN           cp server/snapserver /dist/boot/bin


#######################
# Builder assembly, XXX should be auditor
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS builder

COPY          --from=builder-main   /dist/boot/bin           /dist/boot/bin

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
                libasound2=1.2.4-1.1 \
                libsoxr0=0.1.3-4 \
                libopus0=1.3.1-0.1 \
                libflac8=1.3.3-2 \
                libvorbis0a=1.3.7-1 \
                libvorbisenc2=1.3.7-1 \
                libavahi-client3=0.8-5 \
                libavahi-common3=0.8-5 \
                libatomic1=10.2.1-6 \
                libpulse0=14.2-2 \
              && apt-get -qq autoremove       \
              && apt-get -qq clean            \
              && rm -rf /var/lib/apt/lists/*  \
              && rm -rf /tmp/*                \
              && rm -rf /var/tmp/*


USER          dubo-dubon-duponey

COPY          --from=builder --chown=$BUILD_UID:root /dist /

ENV           NICK="snap"

ENV           DOMAIN="$NICK.local"
ENV           PORT=4443
EXPOSE        $PORT/tcp

#ENV           NAME=TotaleCroquette

# ENV           HEALTHCHECK_URL=rtsp://127.0.0.1:5000

#EXPOSE        5000/tcp
#EXPOSE        6001-6011/udp

#HEALTHCHECK --interval=120s --timeout=30s --start-period=10s --retries=1 CMD rtsp-health || exit 1
