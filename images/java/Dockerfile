# syntax=docker/dockerfile:1

# Java on the FIPS base images, using Bouncy Castle FIPS.
#
# Java does not use OpenSSL. Cryptography comes from BC-FJA 2.1.1 (Bouncy
# Castle FIPS Java API, FIPS 140-3 cert #4943, tested on Java 8, 11, 17 and
# 21), so the image uses Debian's OpenJDK 21. The JDK's own providers are
# replaced by BCFIPS (cryptography, approved-only mode), BCJSSE (TLS) and a
# one-service entropy provider, so non-approved algorithms have no fallback.
# See configure-fips.sh and entropy/.
#
# Targets:
#   runtime  Distroless base + the OpenJDK 21 JRE (headless). Published as
#            latest.
#   dev      Dev base + the OpenJDK 21 JDK (headless). Published as
#            latest-dev.
#   test     runtime + busybox + openssl CLI + a prebuilt check program. Not
#            published.

ARG BASE_IMAGE=debian-fips-base:latest
ARG BASE_DEV_IMAGE=debian-fips-base:latest-dev
ARG BASE_TEST_IMAGE=debian-fips-base:test
ARG DEBIAN_IMAGE=debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a

# ---------------------------------------------------------------------------
# Download and verify the Bouncy Castle FIPS jars from Maven Central.
# bc-fips is the certified module and stays at the certified version; bctls
# and bcutil sit outside the module boundary and take compatible updates.
# ---------------------------------------------------------------------------
FROM ${DEBIAN_IMAGE} AS bc-download

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG BC_FIPS_VERSION=2.1.1
ARG BCTLS_FIPS_VERSION=2.1.25
ARG BCUTIL_FIPS_VERSION=2.1.8
ARG BC_LICENSE_TAG=r1rv86

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /bc
RUN fetch() { \
      curl -fsSLo "$2" "https://repo1.maven.org/maven2/org/bouncycastle/$1/$3/$1-$3.jar" \
      && echo "$4  $2" | sha256sum -c -; \
    } \
 && case "${BC_FIPS_VERSION}" in \
      2.1.1) bc_sha256=a430d935ad6cec6d045930758457740f5a5f8f9715894e347f6800f7926a7321 ;; \
      *) echo "Unsupported BC_FIPS_VERSION: ${BC_FIPS_VERSION}" >&2; exit 1 ;; \
    esac \
 && case "${BCTLS_FIPS_VERSION}" in \
      2.1.25) bctls_sha256=af604aa5b337725872651067a819ebc03aa298685572b0b2ad5343c786faad0a ;; \
      *) echo "Unsupported BCTLS_FIPS_VERSION: ${BCTLS_FIPS_VERSION}" >&2; exit 1 ;; \
    esac \
 && case "${BCUTIL_FIPS_VERSION}" in \
      2.1.8) bcutil_sha256=f44904f61552c823bcc3686a24052ee3135212d547754eaa2ff6532e210103cb ;; \
      *) echo "Unsupported BCUTIL_FIPS_VERSION: ${BCUTIL_FIPS_VERSION}" >&2; exit 1 ;; \
    esac \
 && case "${BC_LICENSE_TAG}" in \
      r1rv86) license_sha256=afaf5bd0b0d869dc86b71711e1b775b204948634c9710a35a9a70d1613a2ab14 ;; \
      *) echo "Unsupported BC_LICENSE_TAG: ${BC_LICENSE_TAG}" >&2; exit 1 ;; \
    esac \
 && fetch bc-fips bc-fips.jar "${BC_FIPS_VERSION}" "${bc_sha256}" \
 && fetch bctls-fips bctls-fips.jar "${BCTLS_FIPS_VERSION}" "${bctls_sha256}" \
 && fetch bcutil-fips bcutil-fips.jar "${BCUTIL_FIPS_VERSION}" "${bcutil_sha256}" \
 && curl -fsSLo LICENSE.html \
      "https://raw.githubusercontent.com/bcgit/bc-java/${BC_LICENSE_TAG}/LICENSE.html" \
 && echo "${license_sha256}  LICENSE.html" | sha256sum -c -

# ---------------------------------------------------------------------------
# jdk: shared by the dev image and the entropy provider build.
# ---------------------------------------------------------------------------
FROM ${BASE_DEV_IMAGE} AS jdk

ARG JAVA_VERSION=21

RUN apt-get update \
 && apt-get install -y --no-install-recommends "openjdk-${JAVA_VERSION}-jdk-headless" \
 && rm -rf /var/lib/apt/lists/*

FROM jdk AS entropy-build

ARG JAVA_VERSION=21

COPY images/java/entropy/ /src/
RUN javac --release "${JAVA_VERSION}" -d /classes /src/fips/entropy/EntropyProvider.java \
 && jar --create --file /fips-entropy.jar -C /classes .

# ---------------------------------------------------------------------------
# dev: the JDK on the dev base.
# ---------------------------------------------------------------------------
FROM jdk AS dev

ARG JAVA_VERSION=21

LABEL org.opencontainers.image.title="debian-fips-java" \
      org.opencontainers.image.description="OpenJDK ${JAVA_VERSION} with Bouncy Castle FIPS (BC-FJA 2.1.1, cert #4943) as the only crypto provider (dev variant: JDK, shell and apt)" \
      fips.java.module="BC-FJA 2.1.1" \
      fips.java.module.cmvp="4943"

COPY --from=bc-download /bc/bc-fips.jar /bc/bctls-fips.jar /bc/bcutil-fips.jar /usr/share/java/bc-fips/
COPY --from=bc-download /bc/LICENSE.html /usr/share/doc/bc-fips/LICENSE.html
COPY --from=entropy-build /fips-entropy.jar /usr/share/java/fips-entropy.jar
COPY --chmod=0755 images/java/configure-fips.sh /usr/local/sbin/configure-java-fips
RUN configure-java-fips "${JAVA_VERSION}"

ENV JAVA_HOME=/usr/lib/jvm/java-${JAVA_VERSION}-openjdk \
    PATH=/usr/lib/jvm/java-${JAVA_VERSION}-openjdk/bin:${PATH} \
    JAVA_TOOL_OPTIONS="-Xbootclasspath/a:/usr/share/java/bc-fips/bc-fips.jar:/usr/share/java/bc-fips/bctls-fips.jar:/usr/share/java/bc-fips/bcutil-fips.jar:/usr/share/java/fips-entropy.jar -Dorg.bouncycastle.fips.approved_only=true -Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts.bcfks -Djavax.net.ssl.trustStoreType=BCFKS -Djavax.net.ssl.trustStorePassword=changeit -Djdk.tls.client.protocols=TLSv1.3,TLSv1.2 -Djdk.tls.server.protocols=TLSv1.3,TLSv1.2 -Djdk.tls.client.cipherSuites=TLS_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384 -Djdk.tls.server.cipherSuites=TLS_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"

# ---------------------------------------------------------------------------
# rootfs: the JRE, configured the same way, and the libraries its native code
# links beyond the base. libpcsclite1 is left out: only the removed SunPCSC
# provider uses it.
# ---------------------------------------------------------------------------
FROM ${BASE_DEV_IMAGE} AS rootfs

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG JAVA_VERSION=21

RUN apt-get update \
 && apt-get install -y --no-install-recommends "openjdk-${JAVA_VERSION}-jre-headless" \
 && rm -rf /var/lib/apt/lists/*

COPY --from=bc-download /bc/bc-fips.jar /bc/bctls-fips.jar /bc/bcutil-fips.jar /usr/share/java/bc-fips/
COPY --from=bc-download /bc/LICENSE.html /usr/share/doc/bc-fips/LICENSE.html
COPY --from=entropy-build /fips-entropy.jar /usr/share/java/fips-entropy.jar
COPY --chmod=0755 images/java/configure-fips.sh /usr/local/sbin/configure-java-fips
COPY --chmod=0755 images/rootfs/install-packages.sh /usr/local/sbin/install-packages

# configure-java-fips edits the package's java.security in place, so the
# rootfs copy below picks up the FIPS configuration.
RUN configure-java-fips "${JAVA_VERSION}" \
 && install-packages /rootfs \
      "openjdk-${JAVA_VERSION}-jre-headless" libstdc++6 libjpeg62-turbo liblcms2-2 \
 && mkdir -p /rootfs/usr/share/java /rootfs/usr/share/doc /rootfs/etc/ssl/certs/java \
 && cp -a /usr/share/java/bc-fips /usr/share/java/fips-entropy.jar /rootfs/usr/share/java/ \
 && cp -a /usr/share/doc/bc-fips /rootfs/usr/share/doc/ \
 && cp -a /etc/ssl/certs/java/cacerts.bcfks /rootfs/etc/ssl/certs/java/ \
 && cp -a "/usr/lib/jvm/java-${JAVA_VERSION}-openjdk" /rootfs/usr/lib/jvm/

# ---------------------------------------------------------------------------
# runtime: distroless.
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS runtime

ARG JAVA_VERSION=21

LABEL org.opencontainers.image.title="debian-fips-java" \
      org.opencontainers.image.description="Distroless OpenJDK ${JAVA_VERSION} JRE with Bouncy Castle FIPS (BC-FJA 2.1.1, cert #4943) as the only crypto provider" \
      fips.java.module="BC-FJA 2.1.1" \
      fips.java.module.cmvp="4943"

COPY --from=rootfs /rootfs/ /

ENV JAVA_HOME=/usr/lib/jvm/java-${JAVA_VERSION}-openjdk \
    PATH=/usr/lib/jvm/java-${JAVA_VERSION}-openjdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    JAVA_TOOL_OPTIONS="-Xbootclasspath/a:/usr/share/java/bc-fips/bc-fips.jar:/usr/share/java/bc-fips/bctls-fips.jar:/usr/share/java/bc-fips/bcutil-fips.jar:/usr/share/java/fips-entropy.jar -Dorg.bouncycastle.fips.approved_only=true -Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts.bcfks -Djavax.net.ssl.trustStoreType=BCFKS -Djavax.net.ssl.trustStorePassword=changeit -Djdk.tls.client.protocols=TLSv1.3,TLSv1.2 -Djdk.tls.server.protocols=TLSv1.3,TLSv1.2 -Djdk.tls.client.cipherSuites=TLS_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384 -Djdk.tls.server.cipherSuites=TLS_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"

CMD ["java", "-version"]

# ---------------------------------------------------------------------------
# test: runtime + busybox + openssl CLI + the prebuilt check program.
# Never published.
# ---------------------------------------------------------------------------
FROM dev AS test-build

COPY tests/java/ /src/
RUN javac -cp /usr/share/java/bc-fips/bc-fips.jar -d /classes /src/FipsCheck.java \
 && jar --create --file /fipscheck.jar --main-class FipsCheck -C /classes .

FROM ${BASE_TEST_IMAGE} AS test-tools

FROM runtime AS test

COPY --from=test-tools /bin/busybox /bin/busybox
COPY --from=test-tools /usr/bin/openssl /usr/bin/openssl
COPY --from=test-build /fipscheck.jar /opt/fipscheck/fipscheck.jar

USER 0
RUN ["/bin/busybox", "--install", "-s", "/bin"]
USER 65532:65532

# ---------------------------------------------------------------------------
# Default target for a plain `docker build`: the distroless runtime.
# ---------------------------------------------------------------------------
FROM runtime
