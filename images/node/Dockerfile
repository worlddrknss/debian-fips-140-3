# syntax=docker/dockerfile:1

# Node.js on the FIPS base images.
#
# Uses the official Node.js release binary. It bundles its own OpenSSL 3.x,
# which loads the base image's FIPS provider (through OPENSSL_MODULES, set in
# the base) and reads /etc/ssl/openssl.cnf (nodejs_conf section), so crypto,
# tls and https run through the FIPS provider. If the provider can't be
# loaded, Node.js aborts at startup instead of running without FIPS.
#
# Targets:
#   runtime  Distroless base + node. No npm, shell or apt. Published as latest.
#   dev      Dev base + node, npm and corepack. Published as latest-dev.
#   test     runtime + busybox + openssl CLI for the test suite. Not published.

ARG BASE_IMAGE=debian-fips-base:latest
ARG BASE_DEV_IMAGE=debian-fips-base:latest-dev
ARG BASE_TEST_IMAGE=debian-fips-base:test
ARG DEBIAN_IMAGE=debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2

# ---------------------------------------------------------------------------
# Download and verify the official Node.js release.
# ---------------------------------------------------------------------------
FROM ${DEBIAN_IMAGE} AS node-download

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG NODE_VERSION=24.22.2
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
      24.22.2-x64) sha256=48cc0e21e048790e54c0cf5749c2725005313d652651c40b7a21feb9697aaf75 ;; \
      24.22.2-arm64) sha256=eb187837a2230d4047161ac0be008584e16b46f726e9c9490ee35dc6b17d9ba8 ;; \
      *) echo "Unsupported NODE_VERSION/arch: ${NODE_VERSION}/${node_arch}" >&2; exit 1 ;; \
    esac \
 && curl -fsSLo /tmp/node.tar.xz \
      "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" \
 && echo "${sha256}  /tmp/node.tar.xz" | sha256sum -c - \
 && mkdir /out \
 && tar -xJf /tmp/node.tar.xz -C /out --strip-components=1 \
      --exclude='*/CHANGELOG.md' --exclude='*/README.md' \
      --exclude='*/share/doc' --exclude='*/share/man' \
      --exclude='*/include' \
 && mkdir -p /out/share/doc/node \
 && mv /out/LICENSE /out/share/doc/node/LICENSE
# C headers (include/) are left out: they're only for compiling native addons,
# which needs build tools this image doesn't have, and node-gyp downloads them.

# ---------------------------------------------------------------------------
# dev: node, npm and corepack on the dev base.
# ---------------------------------------------------------------------------
FROM ${BASE_DEV_IMAGE} AS dev

ARG NODE_VERSION=24.22.2
# The npm bundled with Node.js lags behind npm's own security fixes, so a newer
# npm within the same major version is installed over it.
ARG NPM_VERSION=11.21.2

LABEL org.opencontainers.image.title="debian-fips-node" \
      org.opencontainers.image.description="Node.js ${NODE_VERSION} running its crypto through the OpenSSL FIPS provider (dev variant: npm, shell and apt)"

COPY --from=node-download /out/ /usr/local/

# Node.js sets its own cipher list and ignores the system CipherString, so the
# 256-bit-only policy from /etc/ssl/openssl.cnf is repeated here. Images that
# set NODE_OPTIONS must keep these flags.
ENV NODE_OPTIONS="--tls-min-v1.2 --tls-cipher-list=TLS_AES_256_GCM_SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384"

RUN node -e 'if (require("crypto").getFips() !== 1) process.exit(1)' \
 && npm install -g "npm@${NPM_VERSION}" \
 && npm cache clean --force \
 && rm -rf /root/.npm

# ---------------------------------------------------------------------------
# rootfs: the node binary and the C++ runtime it links against.
# ---------------------------------------------------------------------------
FROM ${BASE_DEV_IMAGE} AS rootfs

RUN install-packages /rootfs libstdc++6

COPY --from=node-download /out/bin/node /rootfs/usr/local/bin/node
COPY --from=node-download /out/share/doc/node/LICENSE /rootfs/usr/local/share/doc/node/LICENSE

# ---------------------------------------------------------------------------
# runtime: distroless.
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS runtime

ARG NODE_VERSION=24.22.2

LABEL org.opencontainers.image.title="debian-fips-node" \
      org.opencontainers.image.description="Distroless Node.js ${NODE_VERSION} running its crypto through the OpenSSL FIPS provider"

COPY --from=rootfs /rootfs/ /

ENV NODE_OPTIONS="--tls-min-v1.2 --tls-cipher-list=TLS_AES_256_GCM_SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384"

CMD ["node"]

# ---------------------------------------------------------------------------
# test: runtime + busybox + openssl CLI. Never published.
# ---------------------------------------------------------------------------
FROM ${BASE_TEST_IMAGE} AS test-tools

FROM runtime AS test

COPY --from=test-tools /bin/busybox /bin/busybox
COPY --from=test-tools /usr/bin/openssl /usr/bin/openssl

USER 0
RUN ["/bin/busybox", "--install", "-s", "/bin"]
USER 65532:65532

# ---------------------------------------------------------------------------
# Default target for a plain `docker build`: the distroless runtime.
# ---------------------------------------------------------------------------
FROM runtime
