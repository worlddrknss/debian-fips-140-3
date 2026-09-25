#!/bin/sh
# Configures an installed Debian OpenJDK for Bouncy Castle FIPS.
#
#   configure-fips.sh <java-major>
#
# Expects the BC FIPS jars in /usr/share/java/bc-fips and the entropy provider
# at /usr/share/java/fips-entropy.jar. Run by both the dev and distroless build
# stages so the two configurations can't drift apart.
set -eu

major="$1"
java_home="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
bc=/usr/share/java/bc-fips
classpath="$bc/bc-fips.jar:$bc/bctls-fips.jar:$bc/bcutil-fips.jar"

# Arch-independent JAVA_HOME.
ln -sfn "$java_home" "/usr/lib/jvm/java-$major-openjdk"

# Trust store: BCFKS is the key store type BC FIPS supports in approved-only
# mode. Converted from Debian's PKCS12 cacerts while the stock providers are
# still configured. "changeit" only protects the store's integrity; it holds
# public CA certificates.
keytool -importkeystore -noprompt \
  -srckeystore /etc/ssl/certs/java/cacerts -srcstoretype PKCS12 -srcstorepass changeit \
  -destkeystore /etc/ssl/certs/java/cacerts.bcfks -deststoretype BCFKS -deststorepass changeit \
  -providerpath "$classpath" \
  -providerclass org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider >/dev/null
chmod 0644 /etc/ssl/certs/java/cacerts.bcfks

# Providers: BC FIPS for all cryptography, BCJSSE for TLS (using BC FIPS),
# and the entropy provider. The JDK's own providers (SUN, SunJCE, SunEC,
# SunJSSE, ...) are removed so non-approved algorithms have no fallback.
security="$(readlink -f "$java_home/conf/security/java.security")"
sed -i \
  -e '/^security\.provider\./d' \
  -e 's/^ssl\.KeyManagerFactory\.algorithm=.*/ssl.KeyManagerFactory.algorithm=PKIX/' \
  -e 's/^keystore\.type=.*/keystore.type=bcfks/' \
  -e 's/^securerandom\.strongAlgorithms=.*/securerandom.strongAlgorithms=NativeEntropy:FIPSEntropy/' \
  "$security"
# The JDK's disabledAlgorithms qualify some SHA-1 entries with "usage ...",
# which BCJSSE doesn't support and would skip with a warning, enforcing
# nothing. The redefinitions below (the last definition in the file wins)
# keep every other JDK entry and disable those SHA-1 uses outright, in line
# with NIST SP 800-131A.
cat >> "$security" <<PROVIDERS

# Bouncy Castle FIPS (configured by debian-fips-140-3).
security.provider.1=org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider
security.provider.2=org.bouncycastle.jsse.provider.BouncyCastleJsseProvider fips:BCFIPS
security.provider.3=fips.entropy.EntropyProvider

jdk.tls.disabledAlgorithms=SSLv3, TLSv1, TLSv1.1, DTLSv1.0, RC4, DES, \\
    MD5withRSA, DH keySize < 1024, EC keySize < 224, 3DES_EDE_CBC, anon, NULL, \\
    ECDH, TLS_RSA_*, rsa_pkcs1_sha1, ecdsa_sha1, dsa_sha1

jdk.certpath.disabledAlgorithms=MD2, MD5, SHA1, \\
    RSA keySize < 1024, DSA keySize < 1024, EC keySize < 224
PROVIDERS
