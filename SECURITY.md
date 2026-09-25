# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately through
[GitHub's private vulnerability reporting](https://github.com/worlddrknss/debian-fips-140-3/security/advisories/new),
not in a public issue. Include the affected image and tag (or digest), and steps to reproduce.

This is a volunteer-maintained project. You can expect an acknowledgement within a week; fixes
depend on severity and on whether the issue is in this repository or upstream.

## What's in scope

- The build configuration in this repository: Dockerfiles, the OpenSSL, Java and Python FIPS
  configuration, the rootfs assembly, and the CI workflows.
- A published image not doing what the README says it does, for example a non-approved
  algorithm that should be rejected but isn't.

Vulnerabilities in upstream components (Debian packages, OpenSSL, Node.js, Bun, Go, .NET,
OpenJDK, Bouncy Castle) should go to those projects. Findings from a vulnerability scanner in
Debian packages are tracked by Debian; the weekly rebuild picks up their fixes.

## Supported images

Only the current `latest*` tags are maintained. Images are rebuilt weekly for Debian security
updates, and pinned upstream versions are bumped through automated pull requests. Older build
tags stay available for a limited time (at least the 5 most recent builds) but aren't patched.
