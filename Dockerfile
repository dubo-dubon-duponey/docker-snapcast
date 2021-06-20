ARG           FROM_IMAGE_BUILDER=ghcr.io/dubo-dubon-duponey/base:builder-bullseye-2021-06-01@sha256:f0ba079c698161922961d9492e27469fca807b9a86a68e6162c325b62b792e81
ARG           FROM_IMAGE_RUNTIME=ghcr.io/dubo-dubon-duponey/base:runtime-bullseye-2021-06-01@sha256:d904e13fbfd217ced9a853d932281f2f64e108d725a767858d2c1957b4e10232

#######################
# Extra builder for healthchecker
#######################
FROM          --platform=$BUILDPLATFORM $FROM_IMAGE_BUILDER                                                             AS builder-healthcheck

ARG           GIT_REPO=github.com/dubo-dubon-duponey/healthcheckers
ARG           GIT_VERSION=51ebf8c
ARG           GIT_COMMIT=51ebf8ca3d255e0c846307bf72740f731e6210c3
ARG           GO_BUILD_SOURCE=./cmd/rtsp
ARG           GO_BUILD_OUTPUT=rtsp-health
ARG           GO_LD_FLAGS="-s -w"
ARG           GO_TAGS="netgo osusergo"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"
ARG           GOOS="$TARGETOS"
ARG           GOARCH="$TARGETARCH"

# hadolint ignore=SC2046
RUN           env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/"$GO_BUILD_OUTPUT" "$GO_BUILD_SOURCE"

#######################
# Goello
#######################
FROM          --platform=$BUILDPLATFORM $FROM_IMAGE_BUILDER                                                             AS builder-goello

ARG           GIT_REPO=github.com/dubo-dubon-duponey/goello
ARG           GIT_VERSION=7ce1fb5
ARG           GIT_COMMIT=7ce1fb5d9c739128d2644fbc1968b11efcb96ca2
ARG           GO_BUILD_SOURCE=./cmd/server
ARG           GO_BUILD_OUTPUT=goello-server
ARG           GO_LD_FLAGS="-s -w"
ARG           GO_TAGS="netgo osusergo"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"
ARG           GOOS="$TARGETOS"
ARG           GOARCH="$TARGETARCH"

# hadolint ignore=SC2046
RUN           env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/"$GO_BUILD_OUTPUT" "$GO_BUILD_SOURCE"

#######################
# Caddy
#######################
FROM          --platform=$BUILDPLATFORM $FROM_IMAGE_BUILDER                                                             AS builder-caddy

# This is 2.4.0
ARG           GIT_REPO=github.com/caddyserver/caddy
ARG           GIT_VERSION=2.4.3
ARG           GIT_COMMIT=9d4ed3a3236df06e54c80c4f6633b66d68ad3673
ARG           GO_BUILD_SOURCE=./cmd/caddy
ARG           GO_BUILD_OUTPUT=caddy
ARG           GO_LD_FLAGS="-s -w"
ARG           GO_TAGS="netgo osusergo"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"
ARG           GOOS="$TARGETOS"
ARG           GOARCH="$TARGETARCH"

# hadolint ignore=SC2046
RUN           env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/"$GO_BUILD_OUTPUT" "$GO_BUILD_SOURCE"

#######################
# Building image
#######################
FROM          $FROM_IMAGE_BUILDER                                                                                       AS builder-main

ARG           BOOST_VERSION=76
WORKDIR       /tmp/boost
# XXXFIXME hey jfrog, what about upgrading your infrastructure to 1.3?
RUN           curl --proto '=https' --tlsv1.2 -sSfL -o boost.tgz "https://boostorg.jfrog.io/artifactory/main/release/1.${BOOST_VERSION}.0/source/boost_1_${BOOST_VERSION}_0.tar.bz2"
RUN           tar -xf boost.tgz

ARG           GIT_REPO=github.com/badaix/snapcast
ARG           GIT_VERSION=0.25.0
ARG           GIT_COMMIT=2af5292f9df9e8f5a54114ed0ef96ca25cd32135

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"

RUN           --mount=type=secret,mode=0444,id=CA,dst=/etc/ssl/certs/ca-certificates.crt \
              --mount=type=secret,id=CERTIFICATE \
              --mount=type=secret,id=KEY \
              --mount=type=secret,id=PASSPHRASE \
              --mount=type=secret,mode=0444,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_OPTIONS,dst=/etc/apt/apt.conf.d/dbdbdp.conf \
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

RUN           ADD_CFLAGS="-I/tmp/boost/boost_1_${BOOST_VERSION}_0/" make client
RUN           ADD_CFLAGS="-I/tmp/boost/boost_1_${BOOST_VERSION}_0/" make server
RUN           mkdir -p /dist/boot/bin
RUN           cp client/snapclient /dist/boot/bin
RUN           cp server/snapserver /dist/boot/bin


#######################
# Builder assembly
#######################
FROM          $FROM_IMAGE_BUILDER                                                                                       AS builder

#COPY          --from=builder-healthcheck /dist/boot/bin /dist/boot/bin
#COPY          --from=builder-goello /dist/boot/bin /dist/boot/bin
#COPY          --from=builder-caddy /dist/boot/bin /dist/boot/bin
COPY          --from=builder-main /dist/boot /dist/boot

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot/bin -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Running image
#######################
FROM          $FROM_IMAGE_RUNTIME

USER          root

RUN           --mount=type=secret,mode=0444,id=CA,dst=/etc/ssl/certs/ca-certificates.crt \
              --mount=type=secret,id=CERTIFICATE \
              --mount=type=secret,id=KEY \
              --mount=type=secret,id=PASSPHRASE \
              --mount=type=secret,mode=0444,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_OPTIONS,dst=/etc/apt/apt.conf.d/dbdbdp.conf \
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

# RUN /boot/bin/snapclient -h; /boot/bin/snapserver -h; exit 1
# RUN           ldd /boot/bin/snapclient; ldd /boot/bin/snapserver; exit 1;


#ENV           NAME=TotaleCroquette

# ENV           HEALTHCHECK_URL=rtsp://127.0.0.1:5000

#EXPOSE        5000/tcp
#EXPOSE        6001-6011/udp

#HEALTHCHECK --interval=120s --timeout=30s --start-period=10s --retries=1 CMD rtsp-health || exit 1
