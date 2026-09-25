# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/) for repository releases. Published images are also
rebuilt weekly with Debian security updates; those rebuilds get `build-YYYYMMDD-<sha>` releases
with SBOMs rather than changelog entries.

## [Unreleased]

### Added

- Distroless variants of every runtime image: no shell or package manager, running as `nonroot`
  (65532). The existing images become the `-dev` variants.
- `-pqc` tags built with the OpenSSL 3.5.4 FIPS provider (ML-KEM, ML-DSA, SLH-DSA), which is in
  CMVP review.
- `debian-fips-python`: Debian's Python 3.13, with `hashlib` and `hmac` restricted to OpenSSL's
  FIPS provider for security use.
- `debian-fips-dotnet`: the ASP.NET Core 10 runtime (distroless) and .NET 10 SDK (`-dev`).
- `debian-fips-java`: Debian's OpenJDK 21 with Bouncy Castle FIPS (BC-FJA 2.1.1, CMVP #4943)
  as the only cryptography provider.
- `debian-fips-nginx-ingress`: the F5 NGINX Ingress Controller 5.6.3 (NGINX OSS 1.31.6), with
  NGINX's TLS through the OpenSSL FIPS provider (hybrid ML-KEM on `-pqc`), an AES-256-only TLS
  policy for client and backend connections, and the controller built with the Go FIPS module.
- Copyright and license files for every package and runtime in the distroless images, with a
  test that enforces it.
- GitHub Release per published build with SPDX SBOMs, an automated pin-bump workflow, OpenSSF
  Scorecard, `SECURITY.md` and an Apache-2.0 `LICENSE`.

### Changed

- **`latest` now uses the OpenSSL 3.1.2 FIPS provider** (FIPS 140-3 validated, CMVP #4985).
  The 3.5.4 provider moved to the `-pqc` tags. The base Dockerfile's own defaults match, so a
  plain `docker build` also gets 3.1.2, and the build fails if `OPENSSL_FIPS_VERSION` and
  `OPENSSL_FIPS_CMVP` disagree, so an image's CMVP label can't misstate its provider.
- **The Bun image is now `debian-fipsbase-bun`**, since Bun's own crypto isn't FIPS validated.
  `debian-fips-bun` is no longer updated.
- `GODEBUG=fips140=only` is set in the base images, so Go binaries built with `GOFIPS140` reject
  non-approved algorithms on them by default.

## [0.1.0] - 2026-09-25

### Added

- Initial FIPS 140-3 image family on Debian trixie-slim: base, Go, Node.js and Bun.
