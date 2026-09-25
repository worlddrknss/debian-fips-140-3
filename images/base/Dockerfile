# syntax=docker/dockerfile:1

# FIPS 140-3 Debian slim base image.
#
# The system OpenSSL (libssl3t64 from Debian) is kept, but every algorithm
# fetch is routed to a standalone OpenSSL FIPS provider. Newer libcrypto
# loading an older provider is the configuration upstream OpenSSL supports
# for this purpose.
#
# OPENSSL_FIPS_VERSION selects the provider:
#   3.5.4  Default. Adds ML-KEM, ML-DSA and SLH-DSA. Submitted for
#          FIPS 140-3, in CMVP review, NOT yet validated.
#   3.1.2  FIPS 140-3 validated (CMVP cert #4985). No PQC.

# Pinned by multi-arch index digest so the assessed base is reproducible.
ARG DEBIAN_IMAGE=debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a
ARG OPENSSL_FIPS_VERSION=3.5.4
# CMVP certificate number for the provider, or "in-process". Set by
# docker-bake.hcl from OPENSSL_FIPS_VERSION and recorded as an image label.
ARG OPENSSL_FIPS_CMVP=in-process

# ---------------------------------------------------------------------------
# Build the FIPS provider exactly as the security policy requires:
#   ./Configure enable-fips && make && make install_fips
# ---------------------------------------------------------------------------
FROM ${DEBIAN_IMAGE} AS fips-builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG OPENSSL_FIPS_VERSION

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl perl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN case "${OPENSSL_FIPS_VERSION}" in \
      3.1.2) sha256=a0ce69b8b97ea6a35b96875235aa453b966ba3cba8af2de23657d8b6767d6539 ;; \
      3.5.4) sha256=967311f84955316969bdb1d8d4b983718ef42338639c621ec4c34fddef355e99 ;; \
      *) echo "Unsupported OPENSSL_FIPS_VERSION: ${OPENSSL_FIPS_VERSION}" >&2; exit 1 ;; \
    esac \
 && curl -fsSLo openssl.tar.gz \
      "https://www.openssl.org/source/openssl-${OPENSSL_FIPS_VERSION}.tar.gz" \
 && echo "${sha256}  openssl.tar.gz" | sha256sum -c - \
 && tar -xzf openssl.tar.gz --strip-components=1 \
 && rm openssl.tar.gz

# No options beyond enable-fips, so the build matches the security policy.
# The default libdir differs per arch (lib vs lib64), so the module is located
# after install and staged at a fixed path.
RUN ./Configure enable-fips \
 && make -j"$(nproc)" \
 && make install_fips \
 && mkdir /fips \
 && cp "$(find /usr/local -name fips.so -path '*/ossl-modules/*')" /fips/fips.so

# -self_test_onload omits the install/MAC status indicators, so the module
# runs its integrity check and KATs on every load. This keeps the generated
# config valid on any host the image is deployed to.
#
# -pedantic (3.4+) makes the provider reject non-approved operations instead
# of only reporting them through the approved-service indicator.
RUN case "${OPENSSL_FIPS_VERSION}" in \
      3.1.*) extra_opts= ;; \
      *) extra_opts=-pedantic ;; \
    esac \
 && /src/apps/openssl fipsinstall \
      -module /fips/fips.so \
      -out /fips/fipsmodule.cnf \
      -self_test_onload ${extra_opts}

# ---------------------------------------------------------------------------
# Runtime image
# ---------------------------------------------------------------------------
FROM ${DEBIAN_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG OPENSSL_FIPS_VERSION
ARG OPENSSL_FIPS_CMVP

LABEL org.opencontainers.image.title="debian-fips-base" \
      org.opencontainers.image.description="Debian slim with OpenSSL routed through the OpenSSL ${OPENSSL_FIPS_VERSION} FIPS provider" \
      org.opencontainers.image.source="https://github.com/worlddrknss/debian-fips-140-3" \
      fips.openssl.provider.version="${OPENSSL_FIPS_VERSION}" \
      fips.openssl.provider.cmvp="${OPENSSL_FIPS_CMVP}"

# Unprivileged user for workloads (UID/GID 65532, the distroless convention).
# The image still defaults to root so downstream builds can install packages;
# application images should end with USER nonroot.
RUN groupadd --gid 65532 nonroot \
 && useradd --uid 65532 --gid 65532 --no-create-home --home-dir /nonexistent \
      --shell /usr/sbin/nologin nonroot

# The legacy provider (MD4, RC4, DES, Blowfish, ...) ships in the base image
# as a hard dependency of libssl3t64, so it can't be purged. Delete the module
# and exclude it from dpkg so package upgrades don't restore it.
RUN echo 'path-exclude=/usr/lib/*/ossl-modules/legacy.so' \
      > /etc/dpkg/dpkg.cfg.d/no-openssl-legacy-provider \
 && apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates openssl \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /usr/lib/*/ossl-modules/legacy.so

COPY --from=fips-builder /fips/fips.so /tmp/fips.so
COPY --from=fips-builder /fips/fipsmodule.cnf /usr/lib/ssl/fipsmodule.cnf
COPY images/base/openssl.cnf /etc/ssl/openssl.cnf

# Install the provider into Debian's multiarch module directory, which is
# where libcrypto looks by default.
RUN modules_dir="$(openssl version -m | sed -E 's/^MODULESDIR: "(.*)"$/\1/')" \
 && install -m 0644 /tmp/fips.so "${modules_dir}/fips.so" \
 && rm /tmp/fips.so \
 && openssl list -providers | grep 'OpenSSL FIPS Provider' >/dev/null

# Restore the default shell so images built FROM this one aren't affected.
SHELL ["/bin/sh", "-c"]
