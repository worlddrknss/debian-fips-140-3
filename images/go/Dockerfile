# syntax=docker/dockerfile:1

# Go toolchain on the FIPS base image.
#
# Go does not use OpenSSL. It ships its own FIPS 140-3 module, the Go
# Cryptographic Module (v1.0.0, CMVP cert #5247). GOFIPS140=certified builds
# every binary against the certified module snapshot and turns FIPS mode on
# by default. GODEBUG=fips140=only additionally makes non-approved algorithms
# fail at runtime.
#
# Binaries built here are static (CGO_ENABLED=0) and run on the distroless
# base image (debian-fips-base:latest). This image builds on the -dev base.
#
# git is not included (it pulls in curl and its CVEs). Modules come through
# GOPROXY; images that fetch private modules over VCS should install git.

ARG BASE_IMAGE=debian-fips-base:latest-dev
ARG DEBIAN_IMAGE=debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2

# ---------------------------------------------------------------------------
# Download and verify the Go toolchain, so curl stays out of the final image.
# ---------------------------------------------------------------------------
FROM ${DEBIAN_IMAGE} AS go-download

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG GO_VERSION=1.27.4
ARG TARGETARCH

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

RUN case "${GO_VERSION}-${TARGETARCH}" in \
      1.27.4-amd64) sha256=7226736c2339719cda28fbf3a54d71aa63bcefe376e98cef00034268dab24840 ;; \
      1.27.4-arm64) sha256=3392582988a273a87ab5043ee1b2c9c17a2c3c00580bf9326c47a2e0aaaeac92 ;; \
      *) echo "Unsupported GO_VERSION/TARGETARCH: ${GO_VERSION}/${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && curl -fsSLo /tmp/go.tar.gz "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" \
 && echo "${sha256}  /tmp/go.tar.gz" | sha256sum -c - \
 && mkdir /out \
 && tar -C /out -xzf /tmp/go.tar.gz

# ---------------------------------------------------------------------------
# Runtime image
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE}

ARG GO_VERSION=1.27.4

LABEL org.opencontainers.image.title="debian-fips-go" \
      org.opencontainers.image.description="Go ${GO_VERSION} building against the FIPS 140-3 Go Cryptographic Module" \
      fips.go.module.version="v1.0.0" \
      fips.go.module.cmvp="5247"

COPY --from=go-download /out/go /usr/local/go

ENV GOPATH=/go \
    PATH=/go/bin:/usr/local/go/bin:${PATH} \
    CGO_ENABLED=0 \
    GOFIPS140=certified \
    GODEBUG=fips140=only

WORKDIR /go/src
