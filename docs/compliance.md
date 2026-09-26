# Compliance mapping

How these images address the NIST publications that apply to container images, and where
each claim is tested or recorded. It covers **the images only**. A system built on them
still has to meet the controls that belong to the host, the cluster and the organization
(see [Deployer responsibilities](#deployer-responsibilities)).

Evidence links point to this repository. "Tested" means a check in `tests/` that runs in
CI against every image and variant; a failing check fails the build.

## Cryptography

| Requirement | How the images meet it | Evidence |
| --- | --- | --- |
| FIPS 140-3 validated cryptography (SP 800-53 SC-13; CJIS 5.10.1.2) | OpenSSL FIPS provider 3.1.2 (CMVP #4985) on `latest` tags; Go Cryptographic Module v1.0.0 (#5247); Bouncy Castle FIPS Java API 2.1.1 (#4943). The only other provider loaded is OpenSSL's `base` (encoders, no algorithms). | Tested: [tests/base.sh](../tests/base.sh), [tests/go.sh](../tests/go.sh), [tests/java.sh](../tests/java.sh) |
| Non-approved algorithms refused (SP 800-131A) | MD5 and RSA below 2048 bits are rejected; the legacy provider is not installed. Python's `hashlib` and Java's providers are restricted to the FIPS module. | Tested: [tests/base.sh](../tests/base.sh), [tests/python.sh](../tests/python.sh), [tests/java.sh](../tests/java.sh) |
| TLS configuration (SP 800-52r2) | TLS 1.2 and 1.3 only; TLS 1.0/1.1 refused. | Tested: [tests/base.sh](../tests/base.sh), [tests/nginx-ingress.sh](../tests/nginx-ingress.sh) |
| 256-bit symmetric encryption in transit (CJIS 5.10.1.2) | System-wide policy allows only AES-256-GCM suites, repeated for runtimes that set their own cipher lists (Node.js, Java, NGINX). | Tested: [tests/base.sh](../tests/base.sh), [tests/node.sh](../tests/node.sh), [tests/nginx-ingress.sh](../tests/nginx-ingress.sh) |

## Image hardening (SP 800-190, SP 800-53 CM-7 and AC-6)

| Requirement | How the images meet it | Evidence |
| --- | --- | --- |
| Minimal images (800-190 §4.1.2, CM-7 least functionality) | The published `latest` variants are distroless: no shell, package manager or build tools. `-dev` variants are build images. | Tested: [tests/base.sh](../tests/base.sh) records every package in `/var/lib/dpkg/status.d/` |
| Least privilege (AC-6) | Runtime images run as `nonroot` (UID 65532). | Tested: [tests/base.sh](../tests/base.sh); Dockle CIS-DI-0001 |
| No privilege escalation paths | No setuid/setgid files, no world-writable paths, no `/etc/shadow` in distroless images. | Tested: [tests/base.sh](../tests/base.sh) |
| CIS Docker Benchmark | Dockle runs on every image in CI; any WARN or FATAL finding on a runtime image fails the build. | [scripts/dockle-images.sh](../scripts/dockle-images.sh) |
| No embedded secrets (800-190 §4.1.4) | Images contain no credentials; the SBOM of every image is published. | [GitHub Releases](https://github.com/worlddrknss/debian-fips-140-3/releases) (SPDX SBOMs) |

## Vulnerability management (SP 800-53 RA-5, SI-2; SP 800-190 §4.1.1)

| Requirement | How the images meet it | Evidence |
| --- | --- | --- |
| Vulnerability scanning (RA-5) | Grype scans every image and variant in CI; results go to the job summary and GitHub code scanning. Scans are report-only so a new CVE can't block the security rebuild that fixes it. | [scripts/scan-images.sh](../scripts/scan-images.sh) |
| Flaw remediation (SI-2) | Rebuilt weekly with Debian security updates, and within a day when Debian publishes a security update for a package in the images (checked daily). Pins for upstream runtimes are updated by an automated workflow. | [.github/workflows/build.yml](../.github/workflows/build.yml), [.github/workflows/security-updates.yml](../.github/workflows/security-updates.yml) |
| Exploitability statements | OpenVEX documents record the status of known findings: `not_affected`/`fixed` statements drop a finding from scans, `affected` statements explain why it remains and what to do. | [vex/](../vex/) |

## Supply chain integrity (SP 800-53 SR-3, SR-4, SI-7; SP 800-218 SSDF)

| Requirement | How the images meet it | Evidence |
| --- | --- | --- |
| Verified sources (SR-3, SSDF PW.4) | Every downloaded artifact (OpenSSL, runtimes, Bouncy Castle, NGINX) is pinned by version and SHA-256 checksum. | `images/*/Dockerfile`, [docker-bake.hcl](../docker-bake.hcl) |
| Provenance (SR-4, SSDF PS.3) | SLSA build provenance attestation for every published image, signed through GitHub's Sigstore instance. | `gh attestation verify` (see README) |
| Integrity verification (SI-7, SSDF PS.2) | Every published image is signed with cosign (keyless, GitHub OIDC identity, public Rekor transparency log). | `cosign verify` (see README) |
| Software bill of materials (SSDF PS.3.2) | SPDX SBOM attached to every image and to every build's GitHub Release. | README "Verifying an image" |

## Known exceptions

- **`-pqc` tags** use the OpenSSL FIPS provider 3.5.4, which is in CMVP review, **not yet
  validated**. Use `latest` (3.1.2) where validated cryptography is required.
- **`debian-fips-java`: bc-fips 2.1.1 has five published vulnerabilities**, fixed in 2.1.2 and
  2.1.3, which are not validated. The image keeps the validated version; each finding and its
  mitigation is in [vex/debian-fips-java.openvex.json](../vex/debian-fips-java.openvex.json).
- **`debian-fipsbase-bun`**: Bun's own crypto (BoringSSL) is **not** FIPS validated. Only
  software using the system OpenSSL runs under the FIPS provider.
- **Go** can't enforce the 256-bit-only TLS policy for programs that configure their own
  cipher suites; they must choose AES-256 suites themselves.
- **Operational environment**: each CMVP certificate lists the platforms the module was tested
  on (see README "Operational environment").

## Deployer responsibilities

Controls these images can't satisfy on their own:

- **Host**: a FIPS-mode kernel and host crypto (for example Ubuntu Pro FIPS) for anything
  outside the containers, such as node-to-node encryption.
- **Cluster admission**: enforce non-root, no privilege escalation and read-only root
  filesystems (Pod Security Admission `restricted`), and allow only trusted, signed images
  (ValidatingAdmissionPolicy for registries; Sigstore policy-controller or Kyverno to require
  signatures).
- **Network**: TLS at the edge and between services; the images' TLS policy only governs
  connections they make or accept.
- **Audit, access control, incident response** (SP 800-53 AU, AC, IR families) and
  keeping deployed images current (image automation, digest pinning).
