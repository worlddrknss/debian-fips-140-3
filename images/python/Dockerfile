# syntax=docker/dockerfile:1

# Python on the FIPS base images.
#
# Debian's python3 links the system OpenSSL, so ssl and hashlib's OpenSSL
# paths use the FIPS provider and the 256-bit TLS policy. On its own, though,
# CPython quietly falls back to its built-in (non-validated) hash
# implementations for any hash OpenSSL refuses, so hashlib.md5() would still
# work. sitecustomize.py closes that gap: security use of hashlib and hmac
# goes through OpenSSL or raises, and usedforsecurity=False keeps working for
# non-security uses such as checksums.
#
# Targets:
#   runtime  Distroless base + python3. No pip, shell or apt. Published as
#            latest.
#   dev      Dev base + python3, pip and venv. Published as latest-dev.
#   test     runtime + busybox + openssl CLI for the test suite. Not published.

ARG BASE_IMAGE=debian-fips-base:latest
ARG BASE_DEV_IMAGE=debian-fips-base:latest-dev
ARG BASE_TEST_IMAGE=debian-fips-base:test

# ---------------------------------------------------------------------------
# dev: python3 with pip and venv.
# ---------------------------------------------------------------------------
FROM ${BASE_DEV_IMAGE} AS dev

LABEL org.opencontainers.image.title="debian-fips-python" \
      org.opencontainers.image.description="Python 3 with ssl and hashlib enforced through the OpenSSL FIPS provider (dev variant: pip, venv, shell and apt)"

RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-pip python3-venv \
 && rm -rf /var/lib/apt/lists/*

# Debian links /usr/lib/python3.X/sitecustomize.py to this file; it is on
# every interpreter's path, including virtual environments.
COPY images/python/sitecustomize.py /tmp/sitecustomize.py
RUN install -m 0644 /tmp/sitecustomize.py \
      "/etc/python$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')/sitecustomize.py" \
 && rm /tmp/sitecustomize.py \
 && python3 -c 'import hashlib; hashlib.sha256()' \
 && ! python3 -c 'import hashlib; hashlib.md5()' 2>/dev/null

# ---------------------------------------------------------------------------
# rootfs: the interpreter, its standard library and the libraries it links.
# ---------------------------------------------------------------------------
FROM ${BASE_DEV_IMAGE} AS rootfs

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# The version the image is tagged with. The build fails if Debian's python3
# is a different minor version, so tags can't drift from what's inside.
ARG PYTHON_VERSION=3.13

RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 \
 && rm -rf /var/lib/apt/lists/*


# The python3.X dependency closure, minus what the base already has and
# minus debconf (only used by package maintainer scripts).
RUN pyver="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')" \
 && { [ "${pyver}" = "${PYTHON_VERSION}" ] \
      || { echo "Debian python3 is ${pyver}, PYTHON_VERSION is ${PYTHON_VERSION}" >&2; exit 1; }; } \
 && install-packages /rootfs \
      "python${pyver}" "python${pyver}-minimal" \
      "libpython${pyver}-minimal" "libpython${pyver}-stdlib" \
      libbz2-1.0 libdb5.3t64 libexpat1 libffi8 liblzma5 libncursesw6 \
      libreadline8t64 readline-common libsqlite3-0 libtinfo6 libuuid1 \
      media-types \
 && ln -s "python${pyver}" /rootfs/usr/bin/python3 \
 && ln -s python3 /rootfs/usr/bin/python \
 && mkdir -p "/rootfs/etc/python${pyver}" \
 && rm -f "/rootfs/usr/lib/python${pyver}/sitecustomize.py" \
 && ln -s "/etc/python${pyver}/sitecustomize.py" "/rootfs/usr/lib/python${pyver}/sitecustomize.py" \
 && echo "${pyver}" > /pyver

COPY images/python/sitecustomize.py /tmp/sitecustomize.py
RUN install -m 0644 /tmp/sitecustomize.py "/rootfs/etc/python$(cat /pyver)/sitecustomize.py"

# ---------------------------------------------------------------------------
# runtime: distroless.
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS runtime

LABEL org.opencontainers.image.title="debian-fips-python" \
      org.opencontainers.image.description="Distroless Python 3 with ssl and hashlib enforced through the OpenSSL FIPS provider"

COPY --from=rootfs /rootfs/ /

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

CMD ["python3"]

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
