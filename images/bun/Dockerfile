# syntax=docker/dockerfile:1

# Bun on the FIPS base images, published as debian-fipsbase-bun: the base is
# FIPS-configured, Bun itself is not.
#
# NOT A FIPS RUNTIME. Bun statically links BoringSSL, which is not FIPS
# validated and ignores the system OpenSSL configuration. Crypto that Bun
# performs (TLS, fetch over HTTPS, node:crypto, WebCrypto) is outside the FIPS
# boundary, and the 256-bit TLS policy does not apply to it. Everything else
# in the image that uses the system OpenSSL is still FIPS-enforced.
#
# Targets:
#   runtime  Distroless base + bun. No shell or apt. Published as latest.
#   dev      Dev base + bun. Published as latest-dev.
#   test     runtime + busybox + openssl CLI for the test suite. Not published.

ARG BASE_IMAGE=debian-fips-base:latest
ARG BASE_DEV_IMAGE=debian-fips-base:latest-dev
ARG BASE_TEST_IMAGE=debian-fips-base:test
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
 && case "${BUN_VERSION}" in \
      1.4.2) license_sha256=b9caf52728691b4057e371232c221a132883198be2f3d2ddf92c90404c984b1a ;; \
      *) echo "No pinned LICENSE.md checksum for BUN_VERSION ${BUN_VERSION}" >&2; exit 1 ;; \
    esac \
 && curl -fsSLo /tmp/bun.zip \
      "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-${bun_arch}.zip" \
 && echo "${sha256}  /tmp/bun.zip" | sha256sum -c - \
 && unzip -j /tmp/bun.zip '*/bun' -d /out \
 && chmod 0755 /out/bun \
 && ln -s bun /out/bunx \
 && mkdir -p /doc \
 && curl -fsSLo /doc/LICENSE.md \
      "https://raw.githubusercontent.com/oven-sh/bun/bun-v${BUN_VERSION}/LICENSE.md" \
 && echo "${license_sha256}  /doc/LICENSE.md" | sha256sum -c -
# LICENSE.md carries Bun's MIT license and the LGPL-2 notices for the
# JavaScriptCore/WebKit code Bun links statically, which redistribution needs.

# ---------------------------------------------------------------------------
# dev: bun on the dev base.
# ---------------------------------------------------------------------------
FROM ${BASE_DEV_IMAGE} AS dev

ARG BUN_VERSION=1.4.2

LABEL org.opencontainers.image.title="debian-fipsbase-bun" \
      org.opencontainers.image.description="Bun ${BUN_VERSION} on the FIPS base image (dev variant: shell and apt). Bun's own crypto (BoringSSL) is NOT FIPS validated." \
      fips.bun.crypto="not-validated"

COPY --from=bun-download /out/ /usr/local/bin/
COPY --from=bun-download /doc/LICENSE.md /usr/local/share/doc/bun/LICENSE.md

# ---------------------------------------------------------------------------
# runtime: distroless. Bun only needs glibc, which the base already has.
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS runtime

ARG BUN_VERSION=1.4.2

LABEL org.opencontainers.image.title="debian-fipsbase-bun" \
      org.opencontainers.image.description="Distroless Bun ${BUN_VERSION} on the FIPS base image. Bun's own crypto (BoringSSL) is NOT FIPS validated." \
      fips.bun.crypto="not-validated"

COPY --from=bun-download /out/ /usr/local/bin/
COPY --from=bun-download /doc/LICENSE.md /usr/local/share/doc/bun/LICENSE.md

CMD ["bun"]

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
