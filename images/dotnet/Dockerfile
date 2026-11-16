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
ARG DEBIAN_IMAGE=debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2

# ---------------------------------------------------------------------------
# Download and verify the ASP.NET Core runtime and the SDK.
# ---------------------------------------------------------------------------
FROM ${DEBIAN_IMAGE} AS dotnet-download

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DOTNET_VERSION=10.0.15
ARG DOTNET_SDK_VERSION=10.0.404
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
      10.0.15-x64) runtime_sha512=704751c6d671b720935a18849e8f10cdb6938549e9cf25493050ebc838a95eb5cb1caa9936d2edae3b85c5975778ed926e9b736e3a2582d861411babba3229c3 ;; \
      10.0.15-arm64) runtime_sha512=1d82a6822871c0e750d2d3d3b9b27657d24a2083eb999c2f78b39b0cd10862178cb2c6d21f941579cd521baf5738a78d3378e5754c5895a93d7546135eb40ec6 ;; \
      *) echo "Unsupported DOTNET_VERSION/arch: ${DOTNET_VERSION}/${rid}" >&2; exit 1 ;; \
    esac \
 && case "${DOTNET_SDK_VERSION}-${rid}" in \
      10.0.404-x64) sdk_sha512=577d0eb17fec33d029104c5c63a1ab0accc3e28776274abef2218dbac5af18d2109b5406d26b31d76f5c245215e3ba0926a94c20246c672c41847c9e1eb1dc50 ;; \
      10.0.404-arm64) sdk_sha512=3533a3869da219cac45c567aadac3d8e96cdf1c6a04fe1c1d5fdeefea5d45af8424488f0144730d11b4a751f7ad546fb11e4c2b2725cd8401efee726711f8f11 ;; \
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

ARG DOTNET_VERSION=10.0.15
ARG DOTNET_SDK_VERSION=10.0.404

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

ARG DOTNET_VERSION=10.0.15

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
