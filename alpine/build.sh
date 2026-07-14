#!/usr/bin/env bash
# Build the workspace for Alpine Linux (aarch64/musl) and deploy to the Pi.
# Mirrors ../build.sh but targets musl instead of glibc.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

IMAGE="carplay-builder-alpine"
BINDIR="target-alpine/release"

build_image() {
    echo "Building Alpine Docker build image..."
    docker build --platform linux/arm64 -f alpine/Dockerfile -t "$IMAGE" alpine
}

build_binary() {
    echo "Compiling workspace for Alpine (musl)..."
    docker run --rm -t --platform linux/arm64 \
        -e CARGO_TERM_COLOR=always \
        -v "$(pwd)":/build \
        -v carplay-cargo-cache-alpine:/root/.cargo/registry \
        "$IMAGE"
    echo "Binaries ready:"
    echo "  ${BINDIR}/carplay-audio  (service)"
    echo "  ${BINDIR}/carplay-tui    (TUI client)"
}

deploy() {
    local host="${1:?Usage: $0 deploy <user@host>}"
    scp "${BINDIR}/carplay-audio" "${BINDIR}/carplay-tui" \
        alpine/provision.sh "$host":~/
    scp -r alpine/overlay "$host":~/
    echo "Deployed to $host — run 'doas sh provision.sh' (or as root) there."
}

case "${1:-build}" in
    image)  build_image ;;
    build)  build_binary ;;
    deploy) deploy "${2:-}" ;;
    all)    build_image && build_binary ;;
    *)
        echo "Usage: $0 [image|build|deploy <user@host>|all]"
        exit 1
        ;;
esac
