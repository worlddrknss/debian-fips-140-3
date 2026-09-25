#!/usr/bin/env bash
# Bumps pinned upstream versions and their checksums.
#
#   scripts/update-pins.sh [summary-file]
#
# Checks the Debian base digest, Node.js (same major), npm (same major), Go
# (same minor), Bun, .NET (same channel) and the Bouncy Castle TLS/util jars
# (same minor) against upstream, computes checksums from the official release
# files, and rewrites docker-bake.hcl and the Dockerfiles. Prints a Markdown
# list of changes (also written to summary-file when given).
#
# Deliberately never touched: the OpenSSL FIPS provider versions and bc-fips.
# Those are fixed by their CMVP certificates, so changing them is a
# compliance decision, not an update. Python and OpenJDK come from Debian and
# update through apt on every weekly build.
set -euo pipefail

cd "$(dirname "$0")/.."
summary="${1:-/dev/null}"
changes=()

# bake_var NAME: current default of a docker-bake.hcl variable.
bake_var() {
  awk -v name="$1" '
    $0 ~ "^variable \"" name "\"" { found = 1 }
    found && /default/ { gsub(/.*= *"|".*/, ""); print; exit }
  ' docker-bake.hcl
}

# replace_version OLD NEW FILE...: replaces a version string in the files.
replace_version() {
  local old="$1" new="$2"
  shift 2
  sed -i "s/$(printf '%s' "$old" | sed 's/\./\\./g')/$new/g" "$@"
}

# set_checksum FILE LABEL VALUE: rewrites the checksum on a `LABEL) x=...` line.
set_checksum() {
  local label
  [ -n "$3" ] && [ "$3" != "null" ] || { echo "update-pins: no checksum found for $2 in $1" >&2; exit 1; }
  label="$(printf '%s' "$2" | sed 's/\./\\./g')"
  sed -i -E "s/^( *${label}\) [a-z_0-9]+=)[0-9a-f]+/\1$3/" "$1"
}

sha256_of() { curl -fsSL "$1" | sha256sum | cut -d' ' -f1; }

# --- Debian base digest -----------------------------------------------------
current="$(grep -oE 'debian:trixie-slim@sha256:[0-9a-f]{64}' docker-bake.hcl | head -n1)"
token="$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/debian:pull" | jq -r .token)"
digest="$(curl -fsSI -H "Authorization: Bearer $token" \
  -H "Accept: application/vnd.oci.image.index.v1+json" \
  -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
  https://registry-1.docker.io/v2/library/debian/manifests/trixie-slim \
  | awk -F': ' 'tolower($1) == "docker-content-digest" {print $2}' | tr -d '\r')"
latest="debian:trixie-slim@$digest"
if [ "$current" != "$latest" ]; then
  grep -rlF "$current" docker-bake.hcl images | xargs sed -i "s|$current|$latest|g"
  changes+=("Debian \`trixie-slim\` → \`${digest:0:19}\`")
fi

# --- Node.js (same major) and npm (same major) ------------------------------
current="$(bake_var NODE_VERSION)"
latest="$(curl -fsSL https://nodejs.org/dist/index.json \
  | jq -r --arg major "v${current%%.*}." '[.[] | select(.version | startswith($major))][0].version' | sed 's/^v//')"
if [ "$current" != "$latest" ]; then
  sums="$(curl -fsSL "https://nodejs.org/dist/v$latest/SHASUMS256.txt")"
  replace_version "$current" "$latest" docker-bake.hcl images/node/Dockerfile
  for arch in x64 arm64; do
    set_checksum images/node/Dockerfile "$latest-$arch" \
      "$(echo "$sums" | awk -v f="node-v$latest-linux-$arch.tar.xz" '$2 == f {print $1}')"
  done
  changes+=("Node.js $current → $latest")
fi

current="$(bake_var NPM_VERSION)"
latest="$(curl -fsSL https://registry.npmjs.org/npm \
  | jq -r --arg major "${current%%.*}" '[.versions | keys[] | select(test("^" + $major + "\\.[0-9]+\\.[0-9]+$"))]
      | sort_by(split(".") | map(tonumber)) | last')"
if [ "$current" != "$latest" ]; then
  replace_version "$current" "$latest" docker-bake.hcl images/node/Dockerfile
  changes+=("npm $current → $latest")
fi

# --- Go (same minor) --------------------------------------------------------
current="$(bake_var GO_VERSION)"
minor="${current%.*}"
release="$(curl -fsSL 'https://go.dev/dl/?mode=json&include=all' \
  | jq -c --arg minor "go$minor." '[.[] | select(.stable and (.version | startswith($minor)))][0]')"
latest="$(echo "$release" | jq -r '.version' | sed 's/^go//')"
if [ -n "$latest" ] && [ "$current" != "$latest" ]; then
  replace_version "$current" "$latest" docker-bake.hcl images/go/Dockerfile Makefile
  for arch in amd64 arm64; do
    set_checksum images/go/Dockerfile "$latest-$arch" \
      "$(echo "$release" | jq -r --arg a "$arch" '.files[] | select(.os == "linux" and .arch == $a and .kind == "archive") | .sha256')"
  done
  changes+=("Go $current → $latest")
fi

# --- Bun ---------------------------------------------------------------------
current="$(bake_var BUN_VERSION)"
latest="$(curl -fsSL https://api.github.com/repos/oven-sh/bun/releases/latest | jq -r .tag_name | sed 's/^bun-v//')"
if [ "$current" != "$latest" ]; then
  sums="$(curl -fsSL "https://github.com/oven-sh/bun/releases/download/bun-v$latest/SHASUMS256.txt")"
  replace_version "$current" "$latest" docker-bake.hcl images/bun/Dockerfile
  for arch in x64 aarch64; do
    set_checksum images/bun/Dockerfile "$latest-$arch" \
      "$(echo "$sums" | awk -v f="bun-linux-$arch.zip" '$2 == f {print $1}')"
  done
  set_checksum images/bun/Dockerfile "$latest" \
    "$(sha256_of "https://raw.githubusercontent.com/oven-sh/bun/bun-v$latest/LICENSE.md")"
  changes+=("Bun $current → $latest")
fi

# --- .NET (same channel) -----------------------------------------------------
current="$(bake_var DOTNET_VERSION)"
current_sdk="$(bake_var DOTNET_SDK_VERSION)"
release="$(curl -fsSL "https://builds.dotnet.microsoft.com/dotnet/release-metadata/${current%.*}/releases.json" | jq -c '.releases[0]')"
latest="$(echo "$release" | jq -r '."aspnetcore-runtime".version')"
latest_sdk="$(echo "$release" | jq -r '.sdk.version')"
if [ "$current" != "$latest" ] || [ "$current_sdk" != "$latest_sdk" ]; then
  replace_version "$current_sdk" "$latest_sdk" docker-bake.hcl images/dotnet/Dockerfile
  replace_version "$current" "$latest" docker-bake.hcl images/dotnet/Dockerfile
  for rid in x64 arm64; do
    set_checksum images/dotnet/Dockerfile "$latest-$rid" \
      "$(echo "$release" | jq -r --arg f "/aspnetcore-runtime-$latest-linux-$rid.tar.gz" '."aspnetcore-runtime".files[] | select(.url | endswith($f)) | .hash')"
    set_checksum images/dotnet/Dockerfile "$latest_sdk-$rid" \
      "$(echo "$release" | jq -r --arg f "/dotnet-sdk-$latest_sdk-linux-$rid.tar.gz" '.sdk.files[] | select(.url | endswith($f)) | .hash')"
  done
  changes+=(".NET $current → $latest (SDK $current_sdk → $latest_sdk)")
fi

# --- Bouncy Castle TLS and util jars (same minor; bc-fips never) -------------
for artifact in bctls-fips bcutil-fips; do
  var="$(echo "$artifact" | tr 'a-z-' 'A-Z_')_VERSION"
  current="$(grep -oE "^ARG ${var}=[0-9.]+" images/java/Dockerfile | cut -d= -f2)"
  latest="$(curl -fsSL "https://repo1.maven.org/maven2/org/bouncycastle/$artifact/maven-metadata.xml" \
    | grep -oE "<version>${current%.*}\.[0-9]+</version>" | sed -E 's/<\/?version>//g' | sort -V | tail -n1)"
  if [ -n "$latest" ] && [ "$current" != "$latest" ]; then
    sed -i "s/^ARG ${var}=${current}$/ARG ${var}=${latest}/" images/java/Dockerfile
    replace_version "$current) " "$latest) " images/java/Dockerfile
    set_checksum images/java/Dockerfile "$latest" \
      "$(sha256_of "https://repo1.maven.org/maven2/org/bouncycastle/$artifact/$latest/$artifact-$latest.jar")"
    changes+=("$artifact $current → $latest")
  fi
done

if [ "${#changes[@]}" -eq 0 ]; then
  echo "All pins are current." | tee "$summary"
else
  printf -- '- %s\n' "${changes[@]}" | tee "$summary"
fi
