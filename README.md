# debian-fips-140-3

[![build](https://github.com/worlddrknss/debian-fips-140-3/actions/workflows/build.yml/badge.svg)](https://github.com/worlddrknss/debian-fips-140-3/actions/workflows/build.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/worlddrknss/debian-fips-140-3/badge)](https://scorecard.dev/viewer/?uri=github.com/worlddrknss/debian-fips-140-3)

Debian trixie container images for Go, Node.js, Python, .NET, Java and the F5 NGINX Ingress
Controller whose cryptography runs
through FIPS 140-3 validated modules. Each image is configured to reject non-approved
algorithms and allow only 256-bit TLS ciphers (the CJIS Security Policy minimum). Every
enforcement claim below is checked by the test suite on every build. Everything is built from
open-source components, and every image is published with an SBOM, SLSA provenance and a signed
build attestation.

> [!IMPORTANT]
> **These images are not FIPS 140-3 certified, and nothing can make a container image
> certified.** CMVP certificates cover cryptographic *modules*. These images *use* validated
> modules, configured according to their security policies. Whether a system built on them is
> compliant depends on how you deploy and operate it (see [Limitations](#limitations)). This
> project isn't affiliated with or endorsed by NIST, the OpenSSL project, Debian, Bouncy Castle,
> Microsoft or the Go team, and it comes with no warranty (see [LICENSE](LICENSE)).

## Images

| Image | Runtime | Cryptographic module | CMVP status |
| --- | --- | --- | --- |
| `debian-fips-base` | glibc + OpenSSL | OpenSSL FIPS provider 3.1.2 | Validated, [#4985](https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/4985) |
| `debian-fips-node` | Node.js 24 | OpenSSL FIPS provider (from the base) | as base |
| `debian-fips-python` | Python 3.13 (Debian) | OpenSSL FIPS provider (from the base) | as base |
| `debian-fips-dotnet` | ASP.NET Core 10 / .NET 10 SDK | OpenSSL FIPS provider (from the base) | as base |
| `debian-fips-java` | OpenJDK 21 (Debian) | Bouncy Castle FIPS Java API (BC-FJA) 2.1.1 | Validated (interim), [#4943](https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/4943) |
| `debian-fips-go` | Go 1.27 toolchain | Go Cryptographic Module v1.0.0 | Validated, [#5247](https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/5247) |
| `debian-fips-nginx-ingress` | F5 NGINX Ingress Controller 5.6 (NGINX OSS 1.31) | NGINX: OpenSSL FIPS provider (from the base); controller: Go Cryptographic Module | as base / #5247 |
| `debian-fipsbase-bun` | Bun | **None for Bun's own crypto** (BoringSSL, not validated) | n/a |

All images are published for `linux/amd64` and `linux/arm64` at
`ghcr.io/worlddrknss/<image>`.

### Tags

| Tag | Provider | Variant |
| --- | --- | --- |
| `latest`, `<version>` | OpenSSL FIPS provider **3.1.2** (validated) | Distroless |
| `latest-dev`, `<version>-dev` | 3.1.2 | Dev |
| `latest-pqc`, `<version>-pqc` | OpenSSL FIPS provider **3.5.4**, adds ML-KEM, ML-DSA, SLH-DSA and hybrid PQC TLS. **In CMVP review, not yet validated.** | Distroless |
| `latest-pqc-dev`, `<version>-pqc-dev` | 3.5.4 | Dev |

Each build is also tagged `YYYYMMDD-<commit>` (plus the same suffixes), so you can pin a build.
For production, pin by digest.

- **Distroless** images contain only what the runtime needs: glibc, OpenSSL and the FIPS
  provider, CA certificates, tzdata and the runtime. They have no shell, package manager or
  coreutils, and run as `nonroot` (UID/GID 65532).
- **Dev** images are Debian trixie-slim with the same FIPS configuration plus bash and apt, and
  the build tools for their language (npm, pip, the .NET SDK, the JDK). They run as root.

The `-pqc` images exist for testing post-quantum cryptography ahead of certification. Don't
describe them as FIPS 140-3 validated until OpenSSL 3.5.4 receives its certificate.

Approximate sizes (linux/arm64):

| Image | Distroless | Dev |
| --- | --- | --- |
| base | 16 MB | 108 MB |
| python | 44 MB | 158 MB |
| bun | 95 MB | 187 MB |
| node | 142 MB | 257 MB |
| dotnet | 176 MB | 818 MB (SDK) |
| java | 229 MB | 420 MB (JDK) |
| nginx-ingress | 131 MB | 343 MB (all modules) |
| go | use `debian-fips-base` (16 MB) | 346 MB (toolchain) |

## Usage

Build in a `-dev` image, ship on distroless:

```dockerfile
FROM ghcr.io/worlddrknss/debian-fips-node:latest-dev AS build
WORKDIR /app
COPY . .
RUN npm ci && npm run build

FROM ghcr.io/worlddrknss/debian-fips-node:latest
COPY --from=build --chown=65532:65532 /app /app
CMD ["node", "/app/server.js"]
```

Distroless images have no shell, so `CMD` and `ENTRYPOINT` must use the exec (JSON) form, and
anything that needs `RUN` (creating users, changing permissions) happens in a `-dev` stage and is
copied in.

### Adding Debian packages to a distroless image

Some apps need system packages the distroless images leave out, such as fonts or `libstdc++`.
Every `-dev` image includes `install-packages`, the script that assembles the distroless images:
it copies the files of installed Debian packages into a directory, keeps their copyright files,
and records them in `/var/lib/dpkg/status.d/` so scanners and SBOMs still see them. Install the
packages in a `-dev` stage, collect them, and copy the result onto the distroless image:

```dockerfile
FROM ghcr.io/worlddrknss/debian-fips-node:latest-dev AS rootfs
RUN apt-get update \
 && apt-get install -y --no-install-recommends fontconfig fonts-dejavu-core \
 && install-packages /rootfs fontconfig fontconfig-config libfontconfig1 fonts-dejavu-core

FROM ghcr.io/worlddrknss/debian-fips-node:latest
COPY --from=rootfs /rootfs/ /
```

List every package the files need, including dependencies not already in the distroless image;
`install-packages` copies only the packages it's given.

## Verifying an image

```sh
# Build provenance, signed through GitHub's Sigstore instance
gh attestation verify oci://ghcr.io/worlddrknss/debian-fips-base:latest --owner worlddrknss

# SBOM (SPDX) attached at build time
docker buildx imagetools inspect ghcr.io/worlddrknss/debian-fips-base:latest \
  --format '{{ json (index .SBOM "linux/amd64").SPDX }}'

# Which FIPS module an image uses
docker inspect ghcr.io/worlddrknss/debian-fips-base:latest --format '{{ json .Config.Labels }}'
```

Every published build also gets a [GitHub Release](https://github.com/worlddrknss/debian-fips-140-3/releases)
listing each image's digest and FIPS module, with SPDX SBOMs attached.

## What is enforced

Each item is checked by the [test suite](tests/) against both the distroless and dev variants
of both provider versions.

| Image | Checks |
| --- | --- |
| base (and every image built on it) | Only the `fips` and `base` OpenSSL providers are loaded; the legacy provider isn't installed. MD5 and RSA-1024 are rejected. TLS 1.0/1.1 are refused; TLS allows only AES-256-GCM. Every Debian package ships its copyright file. On `-pqc`: ML-DSA, ML-KEM and hybrid `SecP256r1MLKEM768` TLS. |
| node | `crypto.getFips() === 1`. Node refuses to start if the provider can't load. MD5 and ChaCha20-Poly1305 are rejected. TLS negotiates AES-256 and refuses AES-128-only servers. |
| python | `hashlib`/`hmac` run in OpenSSL; MD5 and BLAKE2 are rejected for security use. `ssl` negotiates AES-256 and refuses AES-128-only servers. The `cryptography` wheel's bundled OpenSSL runs in FIPS mode. |
| dotnet | MD5, HMAC-MD5 and 3DES encryption are rejected. `SslStream` negotiates AES-256 and refuses AES-128-only servers. |
| java | The only providers are BCFIPS, BCJSSE and an entropy provider; BC is in approved-only mode. MD5, HMAC-MD5, SHA1PRNG and 3DES encryption are rejected. TLS (BCJSSE) negotiates AES-256 and refuses AES-128-only servers. |
| go | Binaries build with `GOFIPS140`, run in FIPS mode and reject MD5 on the distroless base. |
| nginx-ingress | NGINX runs on the system OpenSSL; the controller is built with `GOFIPS140`; every shipped module loads. Client TLS negotiates AES-256 and refuses AES-128-only clients; backend TLS refuses an AES-128-only upstream (502). On `-pqc`: hybrid `X25519MLKEM768`. NGINX binds port 80 as UID 101 with privileged ports restricted. |
| bun | Documents the boundary: `bun` still computes MD5 (see [bun](#bun)). |
| all distroless | No shell; runs as 65532. |

## Limitations

Read these before relying on the images for compliance.

- **Only the cryptography each image routes through its module is covered.** Code can bypass it:
  Bun's BoringSSL, a Rust crate using `ring`, a Python package with its own crypto, and so on.
- **Randomness comes from the host kernel.** The OpenSSL provider, the Go module and the Java
  entropy provider all seed from the kernel, and a container can't turn on kernel FIPS mode
  (`/proc/sys/crypto/fips_enabled`). For strict deployments, run on FIPS-enabled hosts, such as
  FIPS node pools or a FIPS-validated host OS.
- **Operational environment.** Each CMVP certificate lists the platforms the module was tested
  on. Running on others relies on the CMVP rules for porting a module to a new environment,
  which is the operator's responsibility, not this project's.
- **The configuration can be undone.** Changing `OPENSSL_CONF`, `OPENSSL_MODULES`,
  `GODEBUG=fips140`, `JAVA_TOOL_OPTIONS` or `NODE_OPTIONS`, or loading OpenSSL's `default`
  provider in code, re-enables non-approved algorithms. Keep them as the images set them.
- **Go TLS doesn't follow the 256-bit policy.** Go ignores `openssl.cnf` and doesn't let you
  choose TLS 1.3 cipher suites, so a Go server negotiates AES-128 when a client offers it. For
  traffic that must use 256-bit keys, terminate TLS in a proxy or mesh, or limit the service to
  TLS 1.2 with AES-256 suites (which gives up TLS 1.3 and PQC key exchange).
- **Python:** `usedforsecurity=False` deliberately still allows non-approved hashes, since FIPS
  permits them for non-security uses. `python -S` and direct imports of the built-in hash
  modules (`_md5`, ...) bypass the enforcement.
- **Java:** every JVM prints `Picked up JAVA_TOOL_OPTIONS: ...` on stderr, because that is how
  the FIPS providers are loaded. JAAS, Kerberos and PKCS#11 aren't available, since their JDK
  providers are removed. SHA-1 signatures are rejected in TLS and certificate paths.
- **NGINX Ingress:** the controller's API-key authentication policy hashes keys with njs's
  built-in SHA-256, not the FIPS module. Setting `ssl-ciphers` in the controller's ConfigMap
  replaces the AES-256 default for client TLS 1.2, and backend TLS 1.2 is fixed to AES-256-GCM
  regardless of a policy's `ciphers`. The `-dev` variant's `xslt` module links `libgcrypt`, a
  non-validated library used only by EXSLT crypto functions; distroless leaves `xslt` out. The
  image has been tested standalone, not against a live cluster.
- **The `-pqc` provider (3.5.4) isn't validated yet** (see [Tags](#tags)).
- **`-dev` images include apt**, which verifies repository signatures with `sqv` (nettle).
  That's crypto outside the FIPS boundary, used only when packages are installed. apt's TLS
  does run under the FIPS provider: over `https`, repositories whose Release files still list MD5
  checksums (nginx.org, for example) fail with `digital envelope routines::unsupported`, because
  apt's MD5 attempt is refused. Use such repositories over `http`, as Debian's own sources are;
  apt authenticates packages by the repository signature, not by TLS.

### CJIS

The images implement the CJIS Security Policy's cryptographic minimums for data in transit
(FIPS 140-3 validated modules, 256-bit symmetric keys) within the container, except as noted
above. Everything else CJIS requires is outside an image: validated crypto on every hop that
carries CJI (ingress, service mesh, databases, backups), AES-256 encryption at rest, MFA, audit
log retention, account lockout and the rest of the policy.

## Image details

### base

1. Every stage starts from `debian:trixie-slim`, pinned by digest. A builder stage downloads the
   OpenSSL release for the selected provider, checks its pinned SHA-256, and builds it with
   `./Configure enable-fips && make && make install_fips`, the steps the security policy
   requires.
2. The `dev` stage keeps Debian's system OpenSSL (3.5.x) and installs `fips.so` into its module
   directory. OpenSSL supports a newer libcrypto loading an older validated provider.
3. [`openssl.cnf`](images/base/openssl.cnf) activates only the `fips` and `base` providers, sets
   `default_properties = fips=yes`, and sets the system TLS policy (TLS 1.2+, AES-256-GCM only,
   OpenSSL's default key exchange groups).
4. `fipsinstall -self_test_onload` makes the module run its integrity check and self-tests every
   time it loads. For 3.5.4, `-pedantic` also rejects operations the policy doesn't approve,
   such as 3DES encryption, RSA PKCS#1 v1.5 padding and TLS 1.2 without Extended Master Secret.
5. The legacy provider (`legacy.so`: MD4, RC4, DES, ...) is deleted, and a `dpkg` rule keeps
   package upgrades from restoring it.
6. `OPENSSL_CONF` and `OPENSSL_MODULES` are set, so software that bundles its own OpenSSL 3 (the
   official Node.js binaries, Python `cryptography` wheels) loads the same provider and policy.
   `GODEBUG=fips140=only` is set for Go binaries.
7. The distroless variant is assembled from the dev stage's patched packages by
   [`install-packages.sh`](images/rootfs/install-packages.sh). Each package is recorded in
   `/var/lib/dpkg/status.d/`, so scanners and SBOM tools still see Debian packages and versions,
   and keeps its copyright file. glibc's `gconv` modules (legacy iconv character sets, ~20 MB)
   are left out.

### node

The official Node.js release binary, pinned by checksum. Its bundled OpenSSL 3 loads the base
image's FIPS provider and policy through `OPENSSL_MODULES` and `OPENSSL_CONF`. Node.js sets its
own TLS cipher list, so the 256-bit policy is repeated in `NODE_OPTIONS`; keep these flags if you
set `NODE_OPTIONS`:

```sh
--tls-min-v1.2 --tls-cipher-list=TLS_AES_256_GCM_SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
```

Distroless ships only `node`. npm (pinned to a patched npm 11) and corepack are in `-dev`. C
headers are left out; `node-gyp` downloads them when compiling native add-ons.

### python

Debian's `python3`, which links the system OpenSSL. On its own, CPython falls back to its
built-in (non-validated) hash implementations for any hash OpenSSL refuses, so `hashlib.md5()`
would still work. [`sitecustomize.py`](images/python/sitecustomize.py) closes that gap: security
use of `hashlib` and `hmac` goes through OpenSSL or raises `ValueError`. Distroless has no pip;
build a virtual environment in `-dev` and copy it (it uses `/usr/bin/python3`, which both
variants share).

### dotnet

The ASP.NET Core runtime (which includes the .NET runtime) and ICU in distroless, and the .NET
SDK in `-dev`, both pinned by SHA-512. On Linux, .NET performs its cryptography through the
system OpenSSL, so the provider and TLS policy apply directly. `ASPNETCORE_HTTP_PORTS=8080`,
since the image runs as `nonroot`. The SDK's telemetry is turned off.

### java

Debian's OpenJDK 21 (headless JRE in distroless, JDK in `-dev`). BC-FJA 2.1.1 is certified for
Java 8, 11, 17 and 21, so the image stays on 21. [`configure-fips.sh`](images/java/configure-fips.sh)
replaces the JDK's providers with:

1. `BCFIPS`, the certified module (`bc-fips` 2.1.1), in approved-only mode;
2. `BCJSSE`, Bouncy Castle's TLS provider, running on BCFIPS;
3. `FIPSEntropy`, a [small provider](images/java/entropy/fips/entropy/EntropyProvider.java)
   that supplies kernel entropy to BCFIPS. BC-FJA would otherwise take its entropy from the
   JDK's `SUN` provider, which also serves MD5 and other non-approved algorithms. This is the
   approach the Bouncy Castle maintainers suggest in
   [bc-java discussion #1910](https://github.com/bcgit/bc-java/discussions/1910).

The trust store is converted to BCFKS (`/etc/ssl/certs/java/cacerts.bcfks`, password
`changeit`, which protects only its integrity). All settings are applied through
`JAVA_TOOL_OPTIONS`.

### go

A Go toolchain image (one variant), downloaded and pinned by checksum. Go programs compile to
static binaries that need no Go runtime, so their distroless image is `debian-fips-base`:

```dockerfile
FROM ghcr.io/worlddrknss/debian-fips-go:latest AS build
WORKDIR /src
COPY . .
RUN go build -o /out/app .

FROM ghcr.io/worlddrknss/debian-fips-base:latest
COPY --from=build /out/app /app
CMD ["/app"]
```

The toolchain image sets
`GOFIPS140=certified`, so binaries build against the certified module snapshot (v1.0.0) and run
in FIPS mode, and `CGO_ENABLED=0`, so they're static. Copy them onto the distroless base, which
sets `GODEBUG=fips140=only`. `git` isn't included; modules come through `GOPROXY`.

### nginx-ingress

The [F5 NGINX Ingress Controller](https://github.com/nginx/kubernetes-ingress) (NGINX OSS),
built from its source release following upstream's Debian image, with these differences:

- The controller is compiled by `debian-fips-go`, so its TLS (to the Kubernetes API) uses the Go
  Cryptographic Module.
- NGINX comes from nginx.org's Debian packages (signing keys checked against their published
  fingerprints) and links Debian's OpenSSL, so client and backend TLS run through the base's FIPS
  provider. The `-pqc` tags negotiate hybrid ML-KEM key exchange by default.
- [`nginx.tmpl.patch`](images/nginx-ingress/nginx.tmpl.patch) makes the main template default
  `ssl_ciphers` to AES-256-GCM (NGINX's own default allows AES-128 for TLS 1.2) and include
  [`fips-tls-policy.conf`](images/nginx-ingress/fips-tls-policy.conf), which holds backend TLS
  1.2 to AES-256-GCM. TLS 1.3 follows the system policy in both directions.
- NGINX Agent isn't included.

Distroless ships NGINX with the modules the controller loads (`njs`, `otel`, `acme`); `-dev` has
every upstream module. Both run as UID 101 like upstream, with `cap_net_bind_service` on NGINX
and the controller, so they bind ports 80 and 443 without root. Deploy with the upstream Helm
chart or manifests, overriding the image.

### bun

Published as `debian-fipsbase-bun` because **only the base is FIPS-configured, not Bun.** Bun
builds BoringSSL into its binary and ignores the system OpenSSL, so its TLS, `fetch`,
`node:crypto` and WebCrypto are outside the FIPS boundary, and the 256-bit TLS policy doesn't
apply to them. Use it for projects that run on Bun where that's acceptable. Workloads that need
FIPS should run on `debian-fips-node`.

## Building and testing

```sh
make build   # docker buildx bake --load: every published image plus the test images
make test    # every test suite against the distroless and dev variants of both providers
make lint    # hadolint, shellcheck, actionlint, markdownlint, gofmt/vet
```

Versions live in [docker-bake.hcl](docker-bake.hcl), and every download is pinned by checksum.
Distroless images have no shell to run tests in, so each has an unpublished `:test` variant: the
distroless image plus busybox and the `openssl` CLI.

## Updates and CI

- [build.yml](.github/workflows/build.yml) builds and tests every image on native amd64 and
  arm64 runners for each pull request, on `main`, and weekly. The weekly build reruns
  `apt-get upgrade`, so Debian security fixes land within a week. Images are scanned with Grype
  (results in code scanning; report-only). On `main`, images are published with SBOMs,
  provenance and attestations, a GitHub Release records the build, and the registry keeps the 20
  newest tagged images per package (at least the 5 most recent builds).
- [update-pins.yml](.github/workflows/update-pins.yml) opens a pull request weekly when a pinned
  upstream release has a newer version (Debian digest, Node.js, npm, Go, Bun, .NET, Bouncy Castle
  TLS). **The OpenSSL FIPS provider and `bc-fips` versions are never changed automatically**,
  since only certified versions belong there. The NGINX Ingress Controller and NGINX versions are
  bumped by hand, since the template patch has to be checked against each release. Python and
  OpenJDK update through apt.
- [codeql.yml](.github/workflows/codeql.yml) and [scorecard.yml](.github/workflows/scorecard.yml)
  check the workflows and the repository's security practices; Dependabot keeps the pinned
  actions current.

See [SECURITY.md](SECURITY.md) to report a vulnerability and [CHANGELOG.md](CHANGELOG.md) for
changes.

## License

The build configuration in this repository is licensed under the [Apache License 2.0](LICENSE).
The images contain third-party software under its own licenses: each Debian package's terms are
in `/usr/share/doc/<package>/copyright`, the OpenSSL FIPS provider's in
`/usr/share/doc/openssl-fips-provider/`, and Node.js, Bun, .NET and Bouncy Castle ship their
license files alongside their binaries.
