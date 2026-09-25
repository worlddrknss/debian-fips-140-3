# debian-fips-140-3

A family of `debian:trixie-slim` container images where crypto runs through a FIPS 140-3 module,
configured for the CJIS Security Policy's 256-bit minimum. Everything is built from open-source
components.

| Image | Contents | FIPS module |
| --- | --- | --- |
| `debian-fips-base` | Debian slim with system OpenSSL locked to a FIPS provider | OpenSSL FIPS provider 3.5.4 (default) or 3.1.2 |
| `debian-fips-go` | Base + Go toolchain that builds FIPS binaries | Go Cryptographic Module v1.0.0 ([CMVP #5247](https://go.dev/doc/security/fips140)) |
| `debian-fips-node` | Base + Node.js compiled against the system OpenSSL | OpenSSL FIPS provider from the base |
| `debian-fips-bun` | Node image + Bun | **None for Bun.** `node` is FIPS; `bun` is not |

## OpenSSL FIPS provider versions

| `OPENSSL_FIPS_VERSION` | CMVP status | PQC |
| --- | --- | --- |
| `3.5.4` (default) | Submitted for FIPS 140-3, **in CMVP review, not yet validated** | ML-KEM, ML-DSA, SLH-DSA, hybrid TLS (`X25519MLKEM768`, `SecP256r1MLKEM768`) |
| `3.1.2` | FIPS 140-3 validated ([cert #4985](https://csrc.nist.gov/projects/cryptographic-module-validation-program/certificate/4985)) | No |

**Accepted risk:** the default images use 3.5.4, which is in CMVP review and not yet validated.
CJIS (SC-13) requires FIPS 140-3 *certified* modules, so until 3.5.4 receives its certificate,
don't describe the default images as validated. They need no code changes once it's certified.
If you need a validated module today, build with `OPENSSL_FIPS_VERSION=3.1.2`.

Each image records its module in labels (`fips.openssl.provider.cmvp`, `fips.go.module.cmvp`,
`fips.bun.crypto`), so you can check an image with `docker inspect`.

## Build and test

```sh
make build        # docker buildx bake --load: base, go, node and bun
make test         # run every test suite in its image
make lint         # hadolint, shellcheck, actionlint, markdownlint, gofmt/vet

# Validated 3.1.2 provider instead of 3.5.4
OPENSSL_FIPS_VERSION=3.1.2 docker buildx bake --load
```

The go and node images build `FROM` the base, and bun builds `FROM` node, through named bake
contexts, so one `bake` call builds the whole family. Versions are set in
[docker-bake.hcl](docker-bake.hcl). Each Dockerfile pins the SHA-256 of every download it makes.

## CI

[.github/workflows/build.yml](.github/workflows/build.yml) runs on every pull request, on `main`,
and weekly to pick up Debian security updates:

1. **Lint** everything (`make lint`).
2. **Build and test** all four images on native amd64 and arm64 runners.
3. **Scan** each image with Grype. Fixable vulnerabilities are listed in the job summary and in
   the repository's code scanning alerts. Findings are report-only and never fail the build.
4. On `main`: **publish** multi-arch images to `ghcr.io/<owner>/debian-fips-{base,go,node,bun}`,
   tagged `latest`, the version, and a unique `YYYYMMDD-<sha>` build tag. Each image carries an
   SBOM and SLSA provenance, plus a GitHub build attestation signed through Sigstore:

   ```sh
   gh attestation verify oci://ghcr.io/<owner>/debian-fips-base:latest --owner <owner>
   ```

5. **Prune** the registry to the 5 newest builds of each image.

[codeql.yml](.github/workflows/codeql.yml) scans the workflows themselves, and Dependabot keeps
the SHA-pinned actions current.

## Base image

1. Both stages start from `debian:trixie-slim` pinned by digest. A builder stage downloads the
   provider source selected by `OPENSSL_FIPS_VERSION`, checks its pinned SHA-256, and builds it
   with `./Configure enable-fips && make && make install_fips`, the steps the security policy
   requires.
2. The runtime stage keeps Debian's system OpenSSL (3.5.x) and installs `fips.so` into its module
   directory. Upstream OpenSSL supports a newer libcrypto loading an older validated provider.
3. `/etc/ssl/openssl.cnf` activates only the `fips` and `base` providers and sets
   `default_properties = fips=yes`, so non-approved algorithms (such as MD5) fail. Node.js reads
   the same settings through the `nodejs_conf` section.
4. The same file sets a system-wide TLS policy: TLS 1.2 minimum, and **AES-256-GCM only**
   (`TLS_AES_256_GCM_SHA384` for TLS 1.3; ECDHE with AES-256-GCM for TLS 1.2). This meets the
   CJIS 256-bit minimum for CJI in transit. Key exchange keeps OpenSSL's defaults, including the
   hybrid ML-KEM groups.
5. `fipsinstall -self_test_onload` makes the module run its integrity check and self-tests every
   time it loads, so the image stays valid on any host. For 3.5.4, `-pedantic` also makes the
   provider reject non-approved operations such as 3DES encryption, RSA PKCS#1 v1.5 padding and
   TLS 1.2 without Extended Master Secret.
6. The legacy provider (`legacy.so`: MD4, RC4, DES, Blowfish, ...) is deleted. `libssl3t64`
   depends on its package, so a `dpkg` `path-exclude` rule keeps upgrades from restoring it.
7. A `nonroot` user (UID/GID 65532) exists for workloads. The image still defaults to root so
   downstream builds can install packages. Application images should end with `USER nonroot`.

## Go image

Go doesn't use OpenSSL. It has its own validated module. The image sets:

- `GOFIPS140=certified`, so every binary is built against the certified module snapshot (v1.0.0)
  and runs in FIPS mode by default.
- `GODEBUG=fips140=only`, so non-approved algorithms fail at runtime.
- `CGO_ENABLED=0`, so binaries are static and can run on the base image.

The toolchain is downloaded in a separate build stage, so neither `curl` nor `git` is in the
image. Modules come through `GOPROXY`. If a build fetches private modules straight from Git,
install `git` in that build stage.

For a multi-stage build, compile in `debian-fips-go` and copy the binary into `debian-fips-base`.
Set `ENV GODEBUG=fips140=only` in the runtime stage too, or add `godebug fips140=only` to
`go.mod`, because `GOFIPS140` alone turns FIPS mode on but doesn't block non-approved algorithms.

**Go TLS doesn't follow the 256-bit policy.** Go ignores `openssl.cnf`, and it doesn't let you
choose TLS 1.3 cipher suites. A Go server negotiates `TLS_AES_128_GCM_SHA256` whenever the client
offers it. For Go services that carry CJI, either terminate TLS in a FIPS proxy or service mesh,
or limit the service to TLS 1.2 with AES-256 suites:

```go
cfg := &tls.Config{
    MaxVersion: tls.VersionTLS12,
    CipherSuites: []uint16{
        tls.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
        tls.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
    },
}
```

Limiting to TLS 1.2 gives up TLS 1.3 and hybrid PQC key exchange.

## Node.js image

The official Node.js binaries bundle their own OpenSSL, which bypasses the FIPS provider. This
image compiles Node.js from source with `--shared-openssl`, so `crypto`, `tls` and `https` all
use the base image's FIPS configuration (`crypto.getFips() === 1`).

Node.js sets its own TLS cipher list and ignores the system one, so the image repeats the 256-bit
policy in `NODE_OPTIONS`. If you set `NODE_OPTIONS` in a downstream image, keep these flags:

```sh
--tls-min-v1.2 --tls-cipher-list=TLS_AES_256_GCM_SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
```

## Bun image

`debian-fips-bun` is the Node.js image with Bun added, as a convenience for projects that use Bun.
**It is not a FIPS runtime for Bun.** Bun builds BoringSSL into its binary and ignores the system
OpenSSL, so any crypto Bun runs (TLS, `fetch` over HTTPS, `node:crypto`, WebCrypto) is outside
the FIPS boundary. The 256-bit TLS policy doesn't apply to it either. The test suite confirms this
by checking that `bun` still computes MD5.

- Use `bun` for `bun install`, `bun test` and `bun build`.
- Run workloads that need FIPS, including anything that handles CJI, with `node`.

## Scope and caveats

- **Only software that uses the system OpenSSL, or the Go module in the Go image, is covered.**
  Runtimes that bundle their own crypto (Bun, official Node.js binaries, Java JCE, Rust
  `ring`/`rustls`) bypass it and each need their own FIPS setup.
- **Downstream images must not override the FIPS configuration.** The `default` provider is
  compiled into Debian's libcrypto, so setting `OPENSSL_CONF` to another file or calling
  `OSSL_PROVIDER_load(NULL, "default")` re-enables non-approved algorithms. For Go, don't
  override `GODEBUG=fips140`.
- `apt` checks repository signatures with `sqv`, which uses nettle. That's crypto outside the
  FIPS boundary, and it runs when packages are installed, not when your application runs.
- **The host kernel is outside the image.** Both the OpenSSL provider and the Go module get
  their randomness from the host kernel, and a container can't enable kernel FIPS mode
  (`/proc/sys/crypto/fips_enabled`). For a strict deployment, run on FIPS-enabled hosts, such as
  FIPS node pools or a FIPS-validated host OS.
- **CJIS covers more than the images.** Every hop that carries CJI outside a physically secure
  location (ingress, service mesh, databases, backups) needs FIPS 140-3 certified crypto with
  256-bit keys, and CJI at rest needs AES-256. MFA, audit log retention and account lockout are
  platform controls.
- The 3.5.4 security policy isn't public yet. It's built with the standard `./Configure enable-fips`
  and OS entropy (not `enable-fips-jitter`). When the certificate is issued, check the build and
  `fipsinstall` options against its security policy.
