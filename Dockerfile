ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_FETCHER=base:golang-bullseye-2021-08-01@sha256:e4c52b4e7e46a04b49989d3077e62858e7ce9335e21c88718c391b294ebd25fc
ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2021-08-01@sha256:a49ab8a07a2da61eee63b7d9d33b091df190317aefb91203ad0ac41af18d5236
ARG           FROM_IMAGE_AUDITOR=base:auditor-bullseye-2021-08-01@sha256:607d8b42af53ebbeb0064a5fd41895ab34ec670a810a704dbf53a2beb3ab769d
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2021-08-01@sha256:9e54b76442e4d8e1cad76acc3c982a5623b59f395b594af15bef6b489862ceac
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2021-08-01@sha256:3fdb7b859e3fea12a7604ff4ae7e577628784ac1f6ea0d5609de65a4b26e5b3c

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools


#######################
# Fetcher
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_FETCHER                                              AS fetcher

ARG           GIT_REPO=github.com/badaix/snapcast
ARG           GIT_VERSION=0.25.0
ARG           GIT_COMMIT=2af5292f9df9e8f5a54114ed0ef96ca25cd32135

RUN           git clone --recurse-submodules git://"$GIT_REPO" .; git checkout "$GIT_COMMIT"

#######################
# Building image - XXX not ready for X-pile yet - should also copy over libraries (see shairport for inspiration)
#######################
FROM          $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                                                        AS builder-main

COPY          --from=fetcher /source /source

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
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_AUDITOR                                              AS assembly

COPY          --from=builder-main   /dist/boot/bin           /dist/boot/bin

# XXX check if they both need it or what
RUN           setcap 'cap_net_bind_service+ep' /dist/boot/bin/snapclient
RUN           setcap 'cap_net_bind_service+ep' /dist/boot/bin/snapserver

RUN           patchelf --set-rpath '$ORIGIN/../lib'           /dist/boot/bin/snapclient
RUN           patchelf --set-rpath '$ORIGIN/../lib'           /dist/boot/bin/snapserver

RUN           [ "$TARGETARCH" != "amd64" ] || export STACK_CLASH=true; \
              RUNNING=true \
              BIND_NOW=true \
              PIE=true \
              FORTIFIED=true \
              STACK_PROTECTED=true \
              RO_RELOCATIONS=true \
              NO_SYSTEM_LINK=true \
              STATIC=true \
                dubo-check validate /dist/boot/bin/snapclient

RUN           [ "$TARGETARCH" != "amd64" ] || export STACK_CLASH=true; \
              RUNNING=true \
              BIND_NOW=true \
              PIE=true \
              FORTIFIED=true \
              STACK_PROTECTED=true \
              RO_RELOCATIONS=true \
              NO_SYSTEM_LINK=true \
              STATIC=true \
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

COPY          --from=assembly --chown=$BUILD_UID:root /dist /

ENV           NICK="snap"

ENV           DOMAIN="$NICK.local"
ENV           ADDITIONAL_DOMAINS=""
ENV           PORT=4443
EXPOSE        $PORT/tcp

#ENV           NAME=TotaleCroquette

# ENV           HEALTHCHECK_URL=rtsp://127.0.0.1:5000

#EXPOSE        5000/tcp
#EXPOSE        6001-6011/udp

#HEALTHCHECK --interval=120s --timeout=30s --start-period=10s --retries=1 CMD rtsp-health || exit 1
