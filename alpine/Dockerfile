# Build image for the Alpine/musl target (Raspberry Pi running Alpine Linux).
# The binaries link against musl, alsa-lib and libdbus from Alpine 3.24, and
# run on any Alpine 3.24+ aarch64 install with alsa-lib + dbus-libs present.
FROM alpine:3.24

RUN apk add --no-cache build-base rust cargo pkgconf alsa-lib-dev dbus-dev

WORKDIR /build

# Separate target dir so glibc (Debian) and musl builds never mix objects.
ENV CARGO_TARGET_DIR=/build/target-alpine

CMD ["cargo", "build", "--release", "--workspace"]
