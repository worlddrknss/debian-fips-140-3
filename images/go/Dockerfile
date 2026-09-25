# syntax=docker/dockerfile:1

# Go toolchain on the FIPS base image.
#
# Go does not use OpenSSL. It ships its own FIPS 140-3 module, the Go
# Cryptographic Module (v1.0.0, CMVP cert #5247). GOFIPS140=certified builds
# every binary against the certified module snapshot and turns FIPS mode on
# by default. GODEBUG=fips140=only additionally makes non-approved algorithms
# fail at runtime.
#
# Binaries built here are static (CGO_ENABLED=0) and can run on the base image.
#
# git is not included (it pulls in curl and its CVEs). Modules come through
# GOPROXY; images that fetch private modules over VCS should install git.

ARG BASE_IMAGE=debian-fips-base:latest
ARG DEBIAN_IMAGE=debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a

# ---------------------------------------------------------------------------
# Download and verify the Go toolchain, so curl stays out of the final image.
# ---------------------------------------------------------------------------
FROM ${DEBIAN_IMAGE} AS go-download

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG GO_VERSION=1.27.1
ARG TARGETARCH

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

RUN case "${GO_VERSION}-${TARGETARCH}" in \
      1.27.1-amd64) sha256=63d339f0da5ab53635a56f2490a7984dfe12dfcff22ad749f63edaf590168445 ;; \
      1.27.1-arm64) sha256=3450b45a3f9ee8568792736a5c5e70a1f2e9b36c35a8f74958c03e51d7d92bec ;; \
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

ARG GO_VERSION=1.27.1

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
