# syntax=docker/dockerfile:1

# .NET on the FIPS base images.
#
# On Linux, .NET performs its cryptography (System.Security.Cryptography,
# SslStream, HttpClient) through the system OpenSSL, so the FIPS provider and
# the 256-bit TLS policy apply directly.
#
# Targets:
#   runtime  Distroless base + the ASP.NET Core runtime (which includes the
#            .NET runtime) and ICU. Published as latest.
#   dev      Dev base + the .NET SDK. Published as latest-dev.
#   test     runtime + busybox + openssl CLI + a prebuilt check program. Not
#            published.

ARG BASE_IMAGE=debian-fips-base:latest
ARG BASE_DEV_IMAGE=debian-fips-base:latest-dev
ARG BASE_TEST_IMAGE=debian-fips-base:test
ARG DEBIAN_IMAGE=debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f

# ---------------------------------------------------------------------------
# Download and verify the ASP.NET Core runtime and the SDK.
# ---------------------------------------------------------------------------
FROM ${DEBIAN_IMAGE} AS dotnet-download

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DOTNET_VERSION=10.0.13
ARG DOTNET_SDK_VERSION=10.0.402
ARG TARGETARCH

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

RUN case "${TARGETARCH}" in \
      amd64) rid=x64 ;; \
      arm64) rid=arm64 ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && case "${DOTNET_VERSION}-${rid}" in \
      10.0.13-x64) runtime_sha512=7b20d4164f097e1cf616d8174b6a64be100e6f30dc4e028b16e551e8b0c86dff0ef424bb4bf52d1ff0ecca38e102d3fa80814e06cb85a32d6eee4c3b99764f79 ;; \
      10.0.13-arm64) runtime_sha512=7f70bf12f71d0949370b5d6681ad9702d13f5f1e476f9ec8f0455c564a9b69e4fca455d3d201aef8500fef7f24455b278772152233d5a36a1db7de9afad4ed37 ;; \
      *) echo "Unsupported DOTNET_VERSION/arch: ${DOTNET_VERSION}/${rid}" >&2; exit 1 ;; \
    esac \
 && case "${DOTNET_SDK_VERSION}-${rid}" in \
      10.0.402-x64) sdk_sha512=1904a98dda2db34ba78ba3c4fb1b224455329af91c341d83547843c1839e112b04ae699ee92fa2449a8f62249196a938723078c0c60b9f65c88539d5687729c2 ;; \
      10.0.402-arm64) sdk_sha512=db85ae85527251fbb1290720ac3bf324bb1d9eea74516ef291ed4bb1f8ff6ec63a17593367f49b456115e8b24ead6d0c2ece2801e501f36a6cd4444ed01a498f ;; \
      *) echo "Unsupported DOTNET_SDK_VERSION/arch: ${DOTNET_SDK_VERSION}/${rid}" >&2; exit 1 ;; \
    esac \
 && curl -fsSLo /tmp/runtime.tar.gz \
      "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/${DOTNET_VERSION}/aspnetcore-runtime-${DOTNET_VERSION}-linux-${rid}.tar.gz" \
 && echo "${runtime_sha512}  /tmp/runtime.tar.gz" | sha512sum -c - \
 && curl -fsSLo /tmp/sdk.tar.gz \
      "https://builds.dotnet.microsoft.com/dotnet/Sdk/${DOTNET_SDK_VERSION}/dotnet-sdk-${DOTNET_SDK_VERSION}-linux-${rid}.tar.gz" \
 && echo "${sdk_sha512}  /tmp/sdk.tar.gz" | sha512sum -c - \
 && mkdir -p /runtime /sdk \
 && tar -xzf /tmp/runtime.tar.gz -C /runtime \
 && tar -xzf /tmp/sdk.tar.gz -C /sdk \
 && rm /tmp/runtime.tar.gz /tmp/sdk.tar.gz

# ---------------------------------------------------------------------------
# dev: the .NET SDK on the dev base.
# ---------------------------------------------------------------------------
FROM ${BASE_DEV_IMAGE} AS dev

ARG DOTNET_VERSION=10.0.13
ARG DOTNET_SDK_VERSION=10.0.402

LABEL org.opencontainers.image.title="debian-fips-dotnet" \
      org.opencontainers.image.description=".NET SDK ${DOTNET_SDK_VERSION} (runtime ${DOTNET_VERSION}) with cryptography through the OpenSSL FIPS provider (dev variant: shell and apt)"

RUN apt-get update \
 && apt-get install -y --no-install-recommends libicu76 libstdc++6 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=dotnet-download /sdk/ /usr/share/dotnet/

ENV DOTNET_ROOT=/usr/share/dotnet \
    PATH=/usr/share/dotnet:${PATH} \
    DOTNET_RUNNING_IN_CONTAINER=true \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    DOTNET_GENERATE_ASPNET_CERTIFICATE=false \
    ASPNETCORE_HTTP_PORTS=8080

# ---------------------------------------------------------------------------
# rootfs: the runtime and the libraries it needs beyond the base.
# ---------------------------------------------------------------------------
FROM ${BASE_DEV_IMAGE} AS rootfs

RUN apt-get update \
 && apt-get install -y --no-install-recommends libicu76 libstdc++6 \
 && rm -rf /var/lib/apt/lists/*

RUN install-packages /rootfs libicu76 libstdc++6

COPY --from=dotnet-download /runtime/ /rootfs/usr/share/dotnet/

# ---------------------------------------------------------------------------
# runtime: distroless.
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS runtime

ARG DOTNET_VERSION=10.0.13

LABEL org.opencontainers.image.title="debian-fips-dotnet" \
      org.opencontainers.image.description="Distroless ASP.NET Core ${DOTNET_VERSION} runtime with cryptography through the OpenSSL FIPS provider"

COPY --from=rootfs /rootfs/ /

# 8080 because the image runs as nonroot and can't bind ports below 1024.
ENV DOTNET_ROOT=/usr/share/dotnet \
    PATH=/usr/share/dotnet:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    DOTNET_RUNNING_IN_CONTAINER=true \
    ASPNETCORE_HTTP_PORTS=8080

CMD ["dotnet"]

# ---------------------------------------------------------------------------
# test: runtime + busybox + openssl CLI + the prebuilt check program.
# Never published.
# ---------------------------------------------------------------------------
FROM dev AS test-build

COPY tests/dotnet/ /src/
RUN dotnet publish /src -c Release -o /fipscheck --nologo

FROM ${BASE_TEST_IMAGE} AS test-tools

FROM runtime AS test

COPY --from=test-tools /bin/busybox /bin/busybox
COPY --from=test-tools /usr/bin/openssl /usr/bin/openssl
COPY --from=test-build /fipscheck/ /opt/fipscheck/

USER 0
RUN ["/bin/busybox", "--install", "-s", "/bin"]
USER 65532:65532

# ---------------------------------------------------------------------------
# Default target for a plain `docker build`: the distroless runtime.
# ---------------------------------------------------------------------------
FROM runtime
