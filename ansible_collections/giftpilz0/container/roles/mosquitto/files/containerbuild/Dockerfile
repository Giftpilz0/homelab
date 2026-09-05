FROM golang:1.27-bookworm AS builder

ARG GO_AUTH_VERSION=3.5.0

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      build-essential \
      git \
      libcjson-dev \
      libmosquitto-dev \
      libsqlite3-dev \
      mosquitto-dev; \
    rm -rf /var/lib/apt/lists/*; \
    git clone --depth 1 --branch "${GO_AUTH_VERSION}" \
      https://github.com/lhns/mosquitto-go-auth.git /tmp/mosquitto-go-auth; \
    cd /tmp/mosquitto-go-auth; \
    export GOMODCACHE=/tmp/go-mod-cache; \
    export GOCACHE=/tmp/go-build-cache; \
    CGO_CFLAGS="-I/usr/include -I/usr/include/mosquitto -fPIC" \
    CGO_LDFLAGS="-shared -Wl,-unresolved-symbols=ignore-all" \
      go build -p=1 -buildvcs=false -buildmode=c-archive go-auth.go; \
    CGO_CFLAGS="-I/usr/include -I/usr/include/mosquitto -fPIC" \
    CGO_LDFLAGS="-shared -Wl,-unresolved-symbols=ignore-all" \
      go build -p=1 -buildvcs=false -buildmode=c-shared -o /tmp/go-auth.so .; \
    go build -p=1 -buildvcs=false -o /tmp/mosquitto-go-auth-pw ./pw-gen/pw.go; \
    rm -rf "${GOMODCACHE}" "${GOCACHE}" /tmp/mosquitto-go-auth go-auth.a go-auth.h

FROM debian:bookworm-slim

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      libcjson1 \
      libsqlite3-0 \
      mosquitto \
      mosquitto-clients; \
    rm -rf /var/lib/apt/lists/*; \
    mkdir -p /mosquitto/config /mosquitto/data /mosquitto/log; \
    chown -R mosquitto:mosquitto /mosquitto

COPY --from=builder /tmp/go-auth.so /usr/lib/go-auth.so
COPY --from=builder /tmp/mosquitto-go-auth-pw /usr/bin/mosquitto-go-auth-pw
COPY docker-entrypoint.sh /

VOLUME ["/mosquitto/data", "/mosquitto/log"]
EXPOSE 1883 9001
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/usr/sbin/mosquitto", "-c", "/mosquitto/config/mosquitto.conf"]
