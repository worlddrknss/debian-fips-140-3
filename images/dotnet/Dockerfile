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
ARG DEBIAN_IMAGE=debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a

# ---------------------------------------------------------------------------
# Download and verify the ASP.NET Core runtime and the SDK.
# ---------------------------------------------------------------------------
FROM ${DEBIAN_IMAGE} AS dotnet-download

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DOTNET_VERSION=10.0.12
ARG DOTNET_SDK_VERSION=10.0.401
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
      10.0.12-x64) runtime_sha512=c489fc3a9dcc85f24f2d52e9a81b46fdf51affc8a360d008dbd5e3b7ce524969adc4a54f555ad13e29b822f59ed1cae9785608cbac2282f2c9c4fda45c21c7d1 ;; \
      10.0.12-arm64) runtime_sha512=9ba9889057a8b8a8371099f1fc99c6710b723fd0359941183b9a5040b7d9fb7f03bc06b7dad100969f43f852da88b6d843f6c7983c86691594612043233f2e02 ;; \
      *) echo "Unsupported DOTNET_VERSION/arch: ${DOTNET_VERSION}/${rid}" >&2; exit 1 ;; \
    esac \
 && case "${DOTNET_SDK_VERSION}-${rid}" in \
      10.0.401-x64) sdk_sha512=51c8b999af9e8dd9998c9edc5944e19a90788862068acd38694e098889054ce8c23d4f0c5cccfa16bf187d044562359e5ee69a9f8ad0bbe913ba90311fbce25b ;; \
      10.0.401-arm64) sdk_sha512=58ace73ced6b4360754689a686bdfb8a317f4da6cb8bb416dbc7d0ba9f47e43e3c09f5eb1f1a1cfaacbd10df9558da4882bf2a5e195d6ab56a02c1f9f76102ed ;; \
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

ARG DOTNET_VERSION=10.0.12
ARG DOTNET_SDK_VERSION=10.0.401

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

ARG DOTNET_VERSION=10.0.12

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
