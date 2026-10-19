# mosquitto built from source + mosquitto-go-auth built against its headers.
# glibc (Debian) on purpose: musl can't dlopen Go c-shared libraries (golang/go#54805).
ARG GO_VERSION=1.27
ARG DEBIAN_VERSION=trixie

FROM docker.io/library/golang:${GO_VERSION}-${DEBIAN_VERSION} AS builder
ARG MOSQUITTO_VERSION=2.1.2
ARG GO_AUTH_VERSION=3.5.0

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      build-essential libcjson-dev libedit-dev libmicrohttpd-dev libsqlite3-dev libssl-dev; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    wget -qO- "https://mosquitto.org/files/source/mosquitto-${MOSQUITTO_VERSION}.tar.gz" | tar -xz -C /tmp; \
    cd "/tmp/mosquitto-${MOSQUITTO_VERSION}"; \
    make -j "$(nproc)" WITH_WEBSOCKETS=yes WITH_DOCS=no; \
    make install WITH_WEBSOCKETS=yes WITH_DOCS=no DESTDIR=/out; \
    make install WITH_WEBSOCKETS=yes WITH_DOCS=no

RUN set -eux; \
    git clone --depth 1 --branch "${GO_AUTH_VERSION}" https://github.com/lhns/mosquitto-go-auth.git /tmp/go-auth; \
    cd /tmp/go-auth; \
    go build -buildvcs=false -o /out/usr/bin/mosquitto-go-auth-pw ./pw-gen/pw.go; \
    export CGO_CFLAGS="-I/usr/local/include -fPIC" CGO_LDFLAGS="-shared -Wl,-unresolved-symbols=ignore-all"; \
    go build -buildvcs=false -buildmode=c-archive go-auth.go; \
    go build -buildvcs=false -buildmode=c-shared -o /out/usr/lib/go-auth.so .

FROM docker.io/library/debian:${DEBIAN_VERSION}-slim

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates libcjson1 libedit2 libmicrohttpd12t64 libsqlite3-0 libssl3t64; \
    rm -rf /var/lib/apt/lists/*; \
    groupadd -r -g 1883 mosquitto; \
    useradd -r -u 1883 -g mosquitto -d /var/empty -s /usr/sbin/nologin mosquitto; \
    mkdir -p /mosquitto/config /mosquitto/data /mosquitto/log; \
    chown -R mosquitto:mosquitto /mosquitto

COPY --from=builder /out/ /
RUN ldconfig
# Only chowns data/log, not the bind-mounted config files
COPY docker-entrypoint.sh /

VOLUME ["/mosquitto/data", "/mosquitto/log"]
EXPOSE 1883 9001
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/usr/local/sbin/mosquitto", "-c", "/mosquitto/config/mosquitto.conf"]
