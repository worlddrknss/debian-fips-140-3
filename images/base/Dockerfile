# syntax=docker/dockerfile:1

# FIPS 140-3 Debian base images.
#
# Targets:
#   runtime  Distroless: glibc, OpenSSL + the FIPS provider, CA certificates,
#            tzdata and a nonroot user. No shell or package manager. Published
#            as latest / <version>.
#   dev      Debian slim with the same FIPS configuration plus a shell and apt,
#            for build stages and debugging. Published as latest-dev.
#   test     runtime + busybox + the openssl CLI, used only to run the test
#            suite against the distroless filesystem. Never published.
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
 && cp "$(find /usr/local -name fips.so -path '*/ossl-modules/*')" /fips/fips.so \
 && cp LICENSE.txt /fips/LICENSE.txt

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
# dev: Debian slim with the FIPS configuration, a shell and apt.
# ---------------------------------------------------------------------------
FROM ${DEBIAN_IMAGE} AS dev

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG OPENSSL_FIPS_VERSION
ARG OPENSSL_FIPS_CMVP
# Changing this value reruns the apt layer below. CI sets it to the ISO week
# so scheduled builds pick up Debian security updates despite the layer cache.
ARG APT_REFRESH=""

LABEL org.opencontainers.image.title="debian-fips-base" \
      org.opencontainers.image.description="Debian slim with OpenSSL routed through the OpenSSL ${OPENSSL_FIPS_VERSION} FIPS provider (dev variant: shell and apt)" \
      org.opencontainers.image.source="https://github.com/worlddrknss/debian-fips-140-3" \
      fips.openssl.provider.version="${OPENSSL_FIPS_VERSION}" \
      fips.openssl.provider.cmvp="${OPENSSL_FIPS_CMVP}"

# Unprivileged user for workloads (UID/GID 65532, the distroless convention).
# The dev image defaults to root so builds can install packages; the
# distroless runtime defaults to this user.
RUN groupadd --gid 65532 nonroot \
 && useradd --uid 65532 --gid 65532 --no-create-home --home-dir /nonexistent \
      --shell /usr/sbin/nologin nonroot

# The legacy provider (MD4, RC4, DES, Blowfish, ...) ships in the base image
# as a hard dependency of libssl3t64, so it can't be purged. Delete the module
# and exclude it from dpkg so package upgrades don't restore it.
RUN echo "apt refresh: ${APT_REFRESH:-none}" \
 && echo 'path-exclude=/usr/lib/*/ossl-modules/legacy.so' \
      > /etc/dpkg/dpkg.cfg.d/no-openssl-legacy-provider \
 && apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends ca-certificates openssl \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /usr/lib/*/ossl-modules/legacy.so

COPY --from=fips-builder /fips/fips.so /tmp/fips.so
COPY --from=fips-builder /fips/fipsmodule.cnf /usr/lib/ssl/fipsmodule.cnf
COPY --from=fips-builder /fips/LICENSE.txt /usr/share/doc/openssl-fips-provider/LICENSE.txt
COPY images/base/openssl.cnf /etc/ssl/openssl.cnf

# Install the provider into Debian's multiarch module directory, which is
# where the system libcrypto looks by default. /usr/lib/ossl-modules links to
# it so OPENSSL_MODULES can be arch-independent.
RUN modules_dir="$(openssl version -m | sed -E 's/^MODULESDIR: "(.*)"$/\1/')" \
 && install -m 0644 /tmp/fips.so "${modules_dir}/fips.so" \
 && rm /tmp/fips.so \
 && ln -s "${modules_dir}" /usr/lib/ossl-modules \
 && openssl list -providers | grep 'OpenSSL FIPS Provider' >/dev/null

# Applications that bundle their own OpenSSL 3 (the official Node.js binaries,
# Python cryptography wheels, ...) look elsewhere for providers and config by
# default. Pointing them here makes them load this FIPS provider and policy.
#
# GODEBUG=fips140=only makes Go binaries built with GOFIPS140 (see the Go
# image) reject non-approved algorithms. It only affects Go programs.
ENV OPENSSL_CONF=/etc/ssl/openssl.cnf \
    OPENSSL_MODULES=/usr/lib/ossl-modules \
    GODEBUG=fips140=only

# Restore the default shell so images built FROM this one aren't affected.
SHELL ["/bin/sh", "-c"]

# ---------------------------------------------------------------------------
# rootfs: assemble the distroless filesystem from dev's patched packages.
# ---------------------------------------------------------------------------
FROM dev AS rootfs

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# netbase provides /etc/services and /etc/protocols; busybox-static is only
# for the test image and is not copied into the rootfs.
RUN apt-get update \
 && apt-get install -y --no-install-recommends netbase busybox-static \
 && rm -rf /var/lib/apt/lists/*

COPY --chmod=0755 images/rootfs/install-packages.sh /usr/local/sbin/install-packages

# openssl-provider-legacy is deliberately absent: libssl3t64 depends on it,
# but its module is removed and nothing in the rootfs needs it. gcc-*-base
# only carries the copyright file libgcc-s1 (and libstdc++6) point to.
RUN install-packages /rootfs \
      base-files netbase tzdata ca-certificates \
      libc6 libgcc-s1 libssl3t64 zlib1g libzstd1 \
      "$(dpkg-query -W -f='${Package}' 'gcc-*-base')"

# FIPS provider, its configuration and the system policy. The multiarch
# module directory and the /usr/lib/ssl links come from dev, where the
# openssl package created them.
RUN modules_dir="$(readlink /usr/lib/ossl-modules)" \
 && mkdir -p "/rootfs${modules_dir}" /rootfs/usr/lib/ssl /rootfs/etc/ssl \
 && cp -a "${modules_dir}/fips.so" "/rootfs${modules_dir}/" \
 && cp -a /usr/lib/ossl-modules /rootfs/usr/lib/ \
 && cp -a /usr/lib/ssl/fipsmodule.cnf /usr/lib/ssl/openssl.cnf /usr/lib/ssl/cert.pem \
      /usr/lib/ssl/certs /usr/lib/ssl/private /rootfs/usr/lib/ssl/ \
 && cp -a /etc/ssl/openssl.cnf /etc/ssl/certs /rootfs/etc/ssl/ \
 && mkdir -p /rootfs/usr/share/doc \
 && cp -a /usr/share/doc/openssl-fips-provider /rootfs/usr/share/doc/ \
 && mkdir -m 0700 /rootfs/etc/ssl/private

# Users, name service configuration and writable directories.
RUN printf 'root:x:0:0:root:/root:/sbin/nologin\nnonroot:x:65532:65532:nonroot:/home/nonroot:/sbin/nologin\n' \
      > /rootfs/etc/passwd \
 && printf 'root:x:0:\nnonroot:x:65532:\n' > /rootfs/etc/group \
 && printf 'hosts: files dns\n' > /rootfs/etc/nsswitch.conf \
 && mkdir -m 0700 /rootfs/root \
 && mkdir -m 0755 /rootfs/home \
 && install -d -m 0700 -o 65532 -g 65532 /rootfs/home/nonroot \
 && install -d -m 1777 /rootfs/tmp

# ---------------------------------------------------------------------------
# runtime: distroless.
# ---------------------------------------------------------------------------
FROM scratch AS runtime

ARG OPENSSL_FIPS_VERSION
ARG OPENSSL_FIPS_CMVP

LABEL org.opencontainers.image.title="debian-fips-base" \
      org.opencontainers.image.description="Distroless Debian with OpenSSL routed through the OpenSSL ${OPENSSL_FIPS_VERSION} FIPS provider" \
      org.opencontainers.image.source="https://github.com/worlddrknss/debian-fips-140-3" \
      fips.openssl.provider.version="${OPENSSL_FIPS_VERSION}" \
      fips.openssl.provider.cmvp="${OPENSSL_FIPS_CMVP}"

COPY --from=rootfs /rootfs/ /

ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    OPENSSL_CONF=/etc/ssl/openssl.cnf \
    OPENSSL_MODULES=/usr/lib/ossl-modules \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    GODEBUG=fips140=only

USER 65532:65532
WORKDIR /home/nonroot

# ---------------------------------------------------------------------------
# test: runtime + busybox + the openssl CLI, to run tests/ against the
# distroless filesystem. Never published.
# ---------------------------------------------------------------------------
FROM runtime AS test

COPY --from=rootfs /bin/busybox /bin/busybox
COPY --from=rootfs /usr/bin/openssl /usr/bin/openssl

USER 0
RUN ["/bin/busybox", "--install", "-s", "/bin"]
USER 65532:65532

# ---------------------------------------------------------------------------
# Default target for a plain `docker build`: the distroless runtime.
# ---------------------------------------------------------------------------
FROM runtime
