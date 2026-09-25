# Builds the FIPS image family. The go and node targets set BASE_IMAGE to the
# named context "fips-base", which bake wires to the base target, so one bake
# invocation builds all three without pushing the base to a registry first.
#
#   docker buildx bake --load            # build everything locally
#   docker buildx bake --load go         # base + go
#   docker buildx bake --load bun        # base + bun

# Registry prefix including the trailing slash, e.g. "ghcr.io/owner/".
variable "REGISTRY" {
  default = ""
}

# Extra per-build tag, e.g. "20260924-abc1234". CI sets it so every build
# stays addressable after latest moves on.
variable "BUILD_TAG" {
  default = ""
}

# CI pushes each architecture untagged, by digest, and a later job joins the
# digests into multi-arch tags. See .github/workflows/build.yml.
variable "PUSH_BY_DIGEST" {
  default = false
}

variable "DEBIAN_IMAGE" {
  default = "debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a"
}

# Any new value reruns the base image's apt layer. CI sets the ISO week.
variable "APT_REFRESH" {
  default = ""
}

variable "OPENSSL_FIPS_VERSION" {
  default = "3.5.4"
}

variable "GO_VERSION" {
  default = "1.27.1"
}

variable "NODE_VERSION" {
  default = "24.21.0"
}

variable "NPM_VERSION" {
  default = "11.20.0"
}

variable "BUN_VERSION" {
  default = "1.4.2"
}

function "tags" {
  params = [name, version]
  result = PUSH_BY_DIGEST ? [] : concat(
    ["${REGISTRY}${name}:latest", "${REGISTRY}${name}:${version}"],
    BUILD_TAG != "" ? ["${REGISTRY}${name}:${BUILD_TAG}"] : [],
  )
}

# CMVP certificate for each supported OpenSSL FIPS provider version.
function "openssl_cmvp" {
  params = [version]
  result = version == "3.1.2" ? "4985" : "in-process"
}

# SBOM and max-mode provenance attestations are stored with pushed images.
# The docker exporter used by --load can't carry them.
function "attest" {
  params = []
  result = PUSH_BY_DIGEST ? ["type=sbom", "type=provenance,mode=max"] : []
}

function "output" {
  params = [name]
  result = PUSH_BY_DIGEST ? [
    "type=image,name=${REGISTRY}${name},push-by-digest=true,name-canonical=true,push=true",
  ] : []
}

group "default" {
  targets = ["base", "go", "node", "bun"]
}

target "base" {
  context    = "."
  dockerfile = "images/base/Dockerfile"
  args = {
    DEBIAN_IMAGE         = DEBIAN_IMAGE
    APT_REFRESH          = APT_REFRESH
    OPENSSL_FIPS_VERSION = OPENSSL_FIPS_VERSION
    OPENSSL_FIPS_CMVP    = openssl_cmvp(OPENSSL_FIPS_VERSION)
  }
  tags   = tags("debian-fips-base", OPENSSL_FIPS_VERSION)
  output = output("debian-fips-base")
  attest = attest()
}

target "go" {
  context    = "."
  dockerfile = "images/go/Dockerfile"
  contexts = {
    fips-base = "target:base"
  }
  args = {
    BASE_IMAGE   = "fips-base"
    DEBIAN_IMAGE = DEBIAN_IMAGE
    GO_VERSION   = GO_VERSION
  }
  tags   = tags("debian-fips-go", GO_VERSION)
  output = output("debian-fips-go")
  attest = attest()
}

target "node" {
  context    = "."
  dockerfile = "images/node/Dockerfile"
  contexts = {
    fips-base = "target:base"
  }
  args = {
    BASE_IMAGE   = "fips-base"
    DEBIAN_IMAGE = DEBIAN_IMAGE
    NODE_VERSION = NODE_VERSION
    NPM_VERSION  = NPM_VERSION
  }
  tags   = tags("debian-fips-node", NODE_VERSION)
  output = output("debian-fips-node")
  attest = attest()
}

# Bun is not a FIPS runtime; see images/bun/Dockerfile.
target "bun" {
  context    = "."
  dockerfile = "images/bun/Dockerfile"
  contexts = {
    fips-base = "target:base"
  }
  args = {
    BASE_IMAGE   = "fips-base"
    DEBIAN_IMAGE = DEBIAN_IMAGE
    BUN_VERSION  = BUN_VERSION
  }
  tags   = tags("debian-fips-bun", BUN_VERSION)
  output = output("debian-fips-bun")
  attest = attest()
}
