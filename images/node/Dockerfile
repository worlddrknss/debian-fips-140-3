# syntax=docker/dockerfile:1

# Node.js on the FIPS base image.
#
# Uses the official Node.js release binary. It bundles its own OpenSSL 3.x,
# which loads the base image's FIPS provider (through OPENSSL_MODULES, set in
# the base) and reads /etc/ssl/openssl.cnf (nodejs_conf section), so crypto,
# tls and https run through the FIPS provider. If the provider can't be
# loaded, Node.js aborts at startup instead of running without FIPS.

ARG BASE_IMAGE=debian-fips-base:latest
ARG DEBIAN_IMAGE=debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a

# ---------------------------------------------------------------------------
# Download and verify the official Node.js release.
# ---------------------------------------------------------------------------
FROM ${DEBIAN_IMAGE} AS node-download

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG NODE_VERSION=24.21.0
ARG TARGETARCH

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl xz-utils \
 && rm -rf /var/lib/apt/lists/*

RUN case "${TARGETARCH}" in \
      amd64) node_arch=x64 ;; \
      arm64) node_arch=arm64 ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && case "${NODE_VERSION}-${node_arch}" in \
      24.21.0-x64) sha256=fd8e59d5a511510f6a298afb548f18c7d2b1be404d8b4a27d94fbe49f56cb2d6 ;; \
      24.21.0-arm64) sha256=6ad1325edbdb5649c379b75a237147a666c95d4f9ae8d340fef2d1575d289ad2 ;; \
      *) echo "Unsupported NODE_VERSION/arch: ${NODE_VERSION}/${node_arch}" >&2; exit 1 ;; \
    esac \
 && curl -fsSLo /tmp/node.tar.xz \
      "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" \
 && echo "${sha256}  /tmp/node.tar.xz" | sha256sum -c - \
 && mkdir /out \
 && tar -xJf /tmp/node.tar.xz -C /out --strip-components=1 \
      --exclude='*/CHANGELOG.md' --exclude='*/README.md' --exclude='*/LICENSE' \
      --exclude='*/share/doc' --exclude='*/share/man' \
      --exclude='*/include'
# C headers (include/) are left out: they're only for compiling native addons,
# which needs build tools this image doesn't have, and node-gyp downloads them.

# ---------------------------------------------------------------------------
# Runtime image
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE}

ARG NODE_VERSION=24.21.0
# The npm bundled with Node.js lags behind npm's own security fixes, so a newer
# npm within the same major version is installed over it.
ARG NPM_VERSION=11.20.0

LABEL org.opencontainers.image.title="debian-fips-node" \
      org.opencontainers.image.description="Node.js ${NODE_VERSION} running its crypto through the OpenSSL FIPS provider"

COPY --from=node-download /out/ /usr/local/

# Node.js sets its own cipher list and ignores the system CipherString, so the
# 256-bit-only policy from /etc/ssl/openssl.cnf is repeated here. Images that
# set NODE_OPTIONS must keep these flags.
ENV NODE_OPTIONS="--tls-min-v1.2 --tls-cipher-list=TLS_AES_256_GCM_SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384"

RUN node -e 'if (require("crypto").getFips() !== 1) process.exit(1)' \
 && npm install -g "npm@${NPM_VERSION}" \
 && npm cache clean --force \
 && rm -rf /root/.npm
