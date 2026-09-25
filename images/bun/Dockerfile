# syntax=docker/dockerfile:1

# Bun on the FIPS Node.js image.
#
# NOT A FIPS RUNTIME. Bun statically links BoringSSL, which is not FIPS
# validated and ignores the system OpenSSL configuration. Crypto that Bun
# performs (TLS, fetch over HTTPS, node:crypto, WebCrypto) is outside the FIPS
# boundary, and the 256-bit TLS policy does not apply to it.
#
# Use bun for installs, tests and bundling, and run workloads that need FIPS
# with node, which is FIPS-enforced in this image.

ARG NODE_IMAGE=debian-fips-node:latest
ARG DEBIAN_IMAGE=debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a

# ---------------------------------------------------------------------------
# Download and verify the Bun release binary.
# ---------------------------------------------------------------------------
FROM ${DEBIAN_IMAGE} AS bun-download

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG BUN_VERSION=1.4.2
ARG TARGETARCH

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*

RUN case "${TARGETARCH}" in \
      amd64) bun_arch=x64 ;; \
      arm64) bun_arch=aarch64 ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && case "${BUN_VERSION}-${bun_arch}" in \
      1.4.2-x64) sha256=36368faef7527875d5ffa52e53cd48021741f2a83eb6208a8dd64068d422a913 ;; \
      1.4.2-aarch64) sha256=54328bbc2d9c8e0c9f892c544d66c57a83b84139e34909e5ee81758f1ac8fda7 ;; \
      *) echo "Unsupported BUN_VERSION/arch: ${BUN_VERSION}/${bun_arch}" >&2; exit 1 ;; \
    esac \
 && curl -fsSLo /tmp/bun.zip \
      "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-${bun_arch}.zip" \
 && echo "${sha256}  /tmp/bun.zip" | sha256sum -c - \
 && unzip -j /tmp/bun.zip '*/bun' -d /out \
 && chmod 0755 /out/bun

# ---------------------------------------------------------------------------
# Runtime image
# ---------------------------------------------------------------------------
FROM ${NODE_IMAGE}

ARG BUN_VERSION=1.4.2

LABEL org.opencontainers.image.title="debian-fips-bun" \
      org.opencontainers.image.description="Bun ${BUN_VERSION} on the FIPS Node.js image. Bun's own crypto (BoringSSL) is NOT FIPS validated; node is." \
      fips.bun.crypto="not-validated"

COPY --from=bun-download /out/bun /usr/local/bin/bun

RUN ln -s bun /usr/local/bin/bunx \
 && bun --version
