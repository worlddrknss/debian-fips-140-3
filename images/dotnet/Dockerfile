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
ARG DEBIAN_IMAGE=debian:trixie-slim@sha256:62bd423aeee912639ca8ee681c2b762cb3e25137e0a92b20be455898a9f034ad

# ---------------------------------------------------------------------------
# Download and verify the ASP.NET Core runtime and the SDK.
# ---------------------------------------------------------------------------
FROM ${DEBIAN_IMAGE} AS dotnet-download

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DOTNET_VERSION=10.0.14
ARG DOTNET_SDK_VERSION=10.0.403
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
      10.0.14-x64) runtime_sha512=dd024fd2616926a555b75cbf7a836f6dce998199f0596d9d75676dca2b9d59c8ee8673c6ac23473c0f1a4bdd59eb5cd02fe9ab097eeaf2dd8c8bd117c85e7031 ;; \
      10.0.14-arm64) runtime_sha512=b5d5ef8eaee3a0ebd24a359be9a0a4cf67b80b8e2e39b55427778eabad62bf6390ab48100d3b134d152436baa1a3bbff14a576fea1a2f2f7a396707056361afb ;; \
      *) echo "Unsupported DOTNET_VERSION/arch: ${DOTNET_VERSION}/${rid}" >&2; exit 1 ;; \
    esac \
 && case "${DOTNET_SDK_VERSION}-${rid}" in \
      10.0.403-x64) sdk_sha512=b7b3d8461cf98b07d2552ce9199702fa3ad010ac2671a5f8cd5136f7534e50f6855ba7bbb02b11494563f1d04156276a31cda1103b900e5eecd0d9473dc7b9c5 ;; \
      10.0.403-arm64) sdk_sha512=0966aa2b70f4677b8319be9df447a78a0dcd6164836425b55a68fd714f4023feb87b4cac21b9a996b79472ad54487cd0adcd2a9dfd570e2b2a1d26423a2baa9b ;; \
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

ARG DOTNET_VERSION=10.0.14
ARG DOTNET_SDK_VERSION=10.0.403

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

ARG DOTNET_VERSION=10.0.14

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
