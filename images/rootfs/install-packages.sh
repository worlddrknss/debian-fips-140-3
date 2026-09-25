#!/bin/sh
# Copies installed Debian packages into a distroless root filesystem.
#
#   install-packages.sh <rootfs> <package>...
#
# Each package must already be installed in the build stage running this
# script, so the copied files are exactly the patched versions apt resolved.
# For every package it copies the files dpkg owns (minus docs and a few
# excluded paths) and records the package in <rootfs>/var/lib/dpkg/status.d/,
# the layout Google's distroless images use, so vulnerability scanners and
# SBOM tools still see which Debian packages and versions are present.
set -eu

rootfs="$1"
shift

mkdir -p "$rootfs/var/lib/dpkg/status.d"

# Debian's merged-/usr aliases (/bin -> usr/bin, /lib -> usr/lib, ...). The
# dynamic loader is referenced through them, so binaries fail without them.
for alias in /bin /sbin /lib /lib32 /lib64 /libx32; do
  if [ -L "$alias" ] && [ ! -e "$rootfs$alias" ]; then
    cp -a "$alias" "$rootfs$alias"
  fi
done

# Paths that are never needed at runtime. gconv is glibc's iconv character
# set modules (~20 MB); UTF-8 and ASCII are built into glibc, and Node.js and
# Bun use ICU rather than iconv.
#
# Each package's copyright file is kept: it carries the license terms (GPL,
# LGPL, ...) that redistributing the package's binaries requires. Some
# packages' doc directory is a symlink to another package's (libgcc-s1 ->
# gcc-14-base), so those symlinks are kept too and the target package must be
# installed alongside.
excluded() {
  case "$1" in
    /usr/share/doc/*/copyright) return 1 ;;
    /usr/share/doc/*/*) ;;
    /usr/share/doc/*) [ -L "$1" ] && return 1 ;;
  esac
  case "$1" in
    /usr/share/doc/* | /usr/share/man/* | /usr/share/info/* | /usr/share/lintian/*) return 0 ;;
    /usr/share/bug/* | /usr/share/locale/* | */gconv/*) return 0 ;;
  esac
  return 1
}

for pkg in "$@"; do
  status="$(dpkg-query -s "$pkg")"
  echo "$status" | grep -q '^Status: install ok installed' \
    || { echo "install-packages: $pkg is not installed" >&2; exit 1; }

  dpkg-query -L "$pkg" | while read -r path; do
    if [ -d "$path" ] && [ ! -L "$path" ]; then
      continue
    fi
    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
      continue
    fi
    excluded "$path" && continue
    cp -a --parents "$path" "$rootfs"
  done

  echo "$status" > "$rootfs/var/lib/dpkg/status.d/$pkg"
  arch="$(dpkg-query -W -f='${Architecture}' "$pkg")"
  for md5 in "/var/lib/dpkg/info/$pkg:$arch.md5sums" "/var/lib/dpkg/info/$pkg.md5sums"; do
    if [ -f "$md5" ]; then
      cp "$md5" "$rootfs/var/lib/dpkg/status.d/$pkg.md5sums"
      break
    fi
  done
done
