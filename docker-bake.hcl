# Builds the FIPS image family.
#
# Every image except Go is built for two OpenSSL FIPS providers (flavors) and
# two variants:
#
#   flavor   ""      OpenSSL FIPS provider 3.1.2, FIPS 140-3 validated (#4985)
#            "-pqc"  OpenSSL FIPS provider 3.5.4, adds ML-KEM/ML-DSA/SLH-DSA;
#                    in CMVP review, not yet validated
#   variant  ""      distroless runtime (no shell or package manager)
#            "-dev"  Debian slim with a shell and apt
#
# Targets are named <image><flavor><variant> (base, base-dev, base-pqc,
# base-pqc-dev, ...) and tagged latest<flavor><variant> and
# <version><flavor><variant>. Language images take the matching base through
# named contexts, so one bake invocation builds everything without pushing
# the base to a registry first.
#
#   docker buildx bake --load              # all published images
#   docker buildx bake --load test         # the test images (never published)
#   docker buildx bake --load node node-dev

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

# GitHub Actions cache scope suffix, e.g. "amd64". When set, every target
# reads and writes its own gha cache scope. Empty locally.
variable "CACHE_ARCH" {
  default = ""
}

variable "DEBIAN_IMAGE" {
  default = "debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a"
}

# Any new value reruns the base image's apt layer. CI sets the ISO week.
variable "APT_REFRESH" {
  default = ""
}

# The validated provider. Changing it is a compliance decision, never an
# automated bump: only versions with an active CMVP certificate belong here.
variable "OPENSSL_FIPS_VERSION" {
  default = "3.1.2"
}

# The PQC provider, published under the -pqc tags until it is validated.
variable "OPENSSL_FIPS_PQC_VERSION" {
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

# .NET runtime (ASP.NET Core, distroless) and SDK (dev).
variable "DOTNET_VERSION" {
  default = "10.0.12"
}

variable "DOTNET_SDK_VERSION" {
  default = "10.0.401"
}

# Java comes from Debian (openjdk-<major>-jre/jdk-headless). BC-FJA 2.1.1 is
# certified for Java 8, 11, 17 and 21, so this stays 21 until a BC FIPS
# certificate covers a newer major.
variable "JAVA_VERSION" {
  default = "21"
}

# F5 NGINX Ingress Controller source release and the NGINX OSS version its
# Debian image uses (nginx.org mainline packages).
variable "NIC_VERSION" {
  default = "5.6.3"
}

variable "NGINX_VERSION" {
  default = "1.31.6"
}

# Python comes from Debian (security updates arrive through apt), so this is
# only the version tag. It must match trixie's python3; the build fails
# otherwise.
variable "PYTHON_VERSION" {
  default = "3.13"
}

variable "FLAVORS" {
  default = ["", "-pqc"]
}

variable "VARIANTS" {
  default = ["", "-dev"]
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function "provider_version" {
  params = [flavor]
  result = flavor == "-pqc" ? OPENSSL_FIPS_PQC_VERSION : OPENSSL_FIPS_VERSION
}

# CMVP certificate for each supported OpenSSL FIPS provider version.
function "openssl_cmvp" {
  params = [version]
  result = version == "3.1.2" ? "4985" : "in-process"
}

# Dockerfile stage for a variant.
function "stage" {
  params = [variant]
  result = variant == "-dev" ? "dev" : "runtime"
}

function "tags" {
  params = [name, version, suffix]
  result = PUSH_BY_DIGEST ? [] : concat(
    ["${REGISTRY}${name}:latest${suffix}", "${REGISTRY}${name}:${version}${suffix}"],
    BUILD_TAG != "" ? ["${REGISTRY}${name}:${BUILD_TAG}${suffix}"] : [],
  )
}

# SBOM and max-mode provenance attestations are stored with pushed images.
# The docker exporter used by --load can't carry them.
function "attest" {
  params = []
  result = PUSH_BY_DIGEST ? ["type=sbom", "type=provenance,mode=max"] : []
}

function "cache_from" {
  params = [name]
  result = CACHE_ARCH != "" ? ["type=gha,scope=${name}-${CACHE_ARCH}"] : []
}

function "cache_to" {
  params = [name]
  result = CACHE_ARCH != "" && !PUSH_BY_DIGEST ? ["type=gha,scope=${name}-${CACHE_ARCH},mode=max"] : []
}

function "output" {
  params = [name]
  result = PUSH_BY_DIGEST ? [
    "type=image,name=${REGISTRY}${name},push-by-digest=true,name-canonical=true,push=true",
  ] : []
}

# Named contexts for a language image: the base in the same flavor, as both
# variants. Test targets additionally get the base test image.
function "base_contexts" {
  params = [flavor]
  result = {
    fips-base     = "target:base${flavor}"
    fips-base-dev = "target:base${flavor}-dev"
  }
}

function "base_args" {
  params = []
  result = {
    BASE_IMAGE      = "fips-base"
    BASE_DEV_IMAGE  = "fips-base-dev"
    BASE_TEST_IMAGE = "fips-base-test"
    DEBIAN_IMAGE    = DEBIAN_IMAGE
  }
}

# ---------------------------------------------------------------------------
# Groups
# ---------------------------------------------------------------------------

# Published images.
group "default" {
  targets = ["base", "go", "node", "bun", "python", "dotnet", "java", "nginx-ingress"]
}

# Distroless variants plus busybox and the openssl CLI, for running tests/.
# Built and loaded in CI, never pushed.
group "test" {
  targets = ["base-test", "node-test", "bun-test", "python-test", "dotnet-test", "java-test", "nginx-ingress-test"]
}

# ---------------------------------------------------------------------------
# base
# ---------------------------------------------------------------------------

target "base" {
  name = "base${flavor}${variant}"
  matrix = {
    flavor  = FLAVORS
    variant = VARIANTS
  }
  context    = "."
  dockerfile = "images/base/Dockerfile"
  target     = stage(variant)
  args = {
    DEBIAN_IMAGE         = DEBIAN_IMAGE
    APT_REFRESH          = APT_REFRESH
    OPENSSL_FIPS_VERSION = provider_version(flavor)
    OPENSSL_FIPS_CMVP    = openssl_cmvp(provider_version(flavor))
  }
  tags       = tags("debian-fips-base", provider_version(flavor), "${flavor}${variant}")
  output     = output("debian-fips-base")
  attest     = attest()
  cache-from = cache_from("base${flavor}${variant}")
  cache-to   = cache_to("base${flavor}${variant}")
}

target "base-test" {
  name = "base${flavor}-test"
  matrix = {
    flavor = FLAVORS
  }
  context    = "."
  dockerfile = "images/base/Dockerfile"
  target     = "test"
  args = {
    DEBIAN_IMAGE         = DEBIAN_IMAGE
    APT_REFRESH          = APT_REFRESH
    OPENSSL_FIPS_VERSION = provider_version(flavor)
    OPENSSL_FIPS_CMVP    = openssl_cmvp(provider_version(flavor))
  }
  tags       = ["debian-fips-base:test${flavor}"]
  cache-from = cache_from("base${flavor}-test")
  cache-to   = cache_to("base${flavor}-test")
}

# ---------------------------------------------------------------------------
# go: a toolchain image, so it has one variant, built on the validated dev
# base. The static binaries it builds run on the distroless base.
# ---------------------------------------------------------------------------

target "go" {
  context    = "."
  dockerfile = "images/go/Dockerfile"
  contexts = {
    fips-base-dev = "target:base-dev"
  }
  args = {
    BASE_IMAGE   = "fips-base-dev"
    DEBIAN_IMAGE = DEBIAN_IMAGE
    GO_VERSION   = GO_VERSION
  }
  tags       = tags("debian-fips-go", GO_VERSION, "")
  output     = output("debian-fips-go")
  attest     = attest()
  cache-from = cache_from("go")
  cache-to   = cache_to("go")
}

# ---------------------------------------------------------------------------
# node
# ---------------------------------------------------------------------------

target "node" {
  name = "node${flavor}${variant}"
  matrix = {
    flavor  = FLAVORS
    variant = VARIANTS
  }
  context    = "."
  dockerfile = "images/node/Dockerfile"
  target     = stage(variant)
  contexts   = base_contexts(flavor)
  args = merge(base_args(), {
    NODE_VERSION = NODE_VERSION
    NPM_VERSION  = NPM_VERSION
  })
  tags       = tags("debian-fips-node", NODE_VERSION, "${flavor}${variant}")
  output     = output("debian-fips-node")
  attest     = attest()
  cache-from = cache_from("node${flavor}${variant}")
  cache-to   = cache_to("node${flavor}${variant}")
}

target "node-test" {
  name = "node${flavor}-test"
  matrix = {
    flavor = FLAVORS
  }
  context    = "."
  dockerfile = "images/node/Dockerfile"
  target     = "test"
  contexts   = merge(base_contexts(flavor), { fips-base-test = "target:base${flavor}-test" })
  args = merge(base_args(), {
    NODE_VERSION = NODE_VERSION
    NPM_VERSION  = NPM_VERSION
  })
  tags       = ["debian-fips-node:test${flavor}"]
  cache-from = cache_from("node${flavor}-test")
  cache-to   = cache_to("node${flavor}-test")
}

# ---------------------------------------------------------------------------
# bun. Published as debian-fipsbase-bun: the base is FIPS-configured, Bun's
# own crypto is not. See images/bun/Dockerfile.
# ---------------------------------------------------------------------------

target "bun" {
  name = "bun${flavor}${variant}"
  matrix = {
    flavor  = FLAVORS
    variant = VARIANTS
  }
  context    = "."
  dockerfile = "images/bun/Dockerfile"
  target     = stage(variant)
  contexts   = base_contexts(flavor)
  args = merge(base_args(), {
    BUN_VERSION = BUN_VERSION
  })
  tags       = tags("debian-fipsbase-bun", BUN_VERSION, "${flavor}${variant}")
  output     = output("debian-fipsbase-bun")
  attest     = attest()
  cache-from = cache_from("bun${flavor}${variant}")
  cache-to   = cache_to("bun${flavor}${variant}")
}

target "bun-test" {
  name = "bun${flavor}-test"
  matrix = {
    flavor = FLAVORS
  }
  context    = "."
  dockerfile = "images/bun/Dockerfile"
  target     = "test"
  contexts   = merge(base_contexts(flavor), { fips-base-test = "target:base${flavor}-test" })
  args = merge(base_args(), {
    BUN_VERSION = BUN_VERSION
  })
  tags       = ["debian-fipsbase-bun:test${flavor}"]
  cache-from = cache_from("bun${flavor}-test")
  cache-to   = cache_to("bun${flavor}-test")
}

# ---------------------------------------------------------------------------
# python: Debian's python3, with hashlib enforced by sitecustomize.py.
# ---------------------------------------------------------------------------

target "python" {
  name = "python${flavor}${variant}"
  matrix = {
    flavor  = FLAVORS
    variant = VARIANTS
  }
  context    = "."
  dockerfile = "images/python/Dockerfile"
  target     = stage(variant)
  contexts   = base_contexts(flavor)
  args       = merge(base_args(), { PYTHON_VERSION = PYTHON_VERSION })
  tags       = tags("debian-fips-python", PYTHON_VERSION, "${flavor}${variant}")
  output     = output("debian-fips-python")
  attest     = attest()
  cache-from = cache_from("python${flavor}${variant}")
  cache-to   = cache_to("python${flavor}${variant}")
}

target "python-test" {
  name = "python${flavor}-test"
  matrix = {
    flavor = FLAVORS
  }
  context    = "."
  dockerfile = "images/python/Dockerfile"
  target     = "test"
  contexts   = merge(base_contexts(flavor), { fips-base-test = "target:base${flavor}-test" })
  args       = merge(base_args(), { PYTHON_VERSION = PYTHON_VERSION })
  tags       = ["debian-fips-python:test${flavor}"]
  cache-from = cache_from("python${flavor}-test")
  cache-to   = cache_to("python${flavor}-test")
}

# ---------------------------------------------------------------------------
# dotnet: ASP.NET Core runtime (distroless) and SDK (dev).
# ---------------------------------------------------------------------------

target "dotnet" {
  name = "dotnet${flavor}${variant}"
  matrix = {
    flavor  = FLAVORS
    variant = VARIANTS
  }
  context    = "."
  dockerfile = "images/dotnet/Dockerfile"
  target     = stage(variant)
  contexts   = base_contexts(flavor)
  args = merge(base_args(), {
    DOTNET_VERSION     = DOTNET_VERSION
    DOTNET_SDK_VERSION = DOTNET_SDK_VERSION
  })
  tags       = tags("debian-fips-dotnet", DOTNET_VERSION, "${flavor}${variant}")
  output     = output("debian-fips-dotnet")
  attest     = attest()
  cache-from = cache_from("dotnet${flavor}${variant}")
  cache-to   = cache_to("dotnet${flavor}${variant}")
}

target "dotnet-test" {
  name = "dotnet${flavor}-test"
  matrix = {
    flavor = FLAVORS
  }
  context    = "."
  dockerfile = "images/dotnet/Dockerfile"
  target     = "test"
  contexts   = merge(base_contexts(flavor), { fips-base-test = "target:base${flavor}-test" })
  args = merge(base_args(), {
    DOTNET_VERSION     = DOTNET_VERSION
    DOTNET_SDK_VERSION = DOTNET_SDK_VERSION
  })
  tags       = ["debian-fips-dotnet:test${flavor}"]
  cache-from = cache_from("dotnet${flavor}-test")
  cache-to   = cache_to("dotnet${flavor}-test")
}

# ---------------------------------------------------------------------------
# java: Debian's OpenJDK with Bouncy Castle FIPS as the only crypto provider.
# ---------------------------------------------------------------------------

target "java" {
  name = "java${flavor}${variant}"
  matrix = {
    flavor  = FLAVORS
    variant = VARIANTS
  }
  context    = "."
  dockerfile = "images/java/Dockerfile"
  target     = stage(variant)
  contexts   = base_contexts(flavor)
  args       = merge(base_args(), { JAVA_VERSION = JAVA_VERSION })
  tags       = tags("debian-fips-java", JAVA_VERSION, "${flavor}${variant}")
  output     = output("debian-fips-java")
  attest     = attest()
  cache-from = cache_from("java${flavor}${variant}")
  cache-to   = cache_to("java${flavor}${variant}")
}

target "java-test" {
  name = "java${flavor}-test"
  matrix = {
    flavor = FLAVORS
  }
  context    = "."
  dockerfile = "images/java/Dockerfile"
  target     = "test"
  contexts   = merge(base_contexts(flavor), { fips-base-test = "target:base${flavor}-test" })
  args       = merge(base_args(), { JAVA_VERSION = JAVA_VERSION })
  tags       = ["debian-fips-java:test${flavor}"]
  cache-from = cache_from("java${flavor}-test")
  cache-to   = cache_to("java${flavor}-test")
}

# ---------------------------------------------------------------------------
# nginx-ingress: F5 NGINX Ingress Controller (NGINX OSS). The controller is
# compiled by the go target; NGINX runs on the base in the matching flavor.
# ---------------------------------------------------------------------------

target "nginx-ingress" {
  name = "nginx-ingress${flavor}${variant}"
  matrix = {
    flavor  = FLAVORS
    variant = VARIANTS
  }
  context    = "."
  dockerfile = "images/nginx-ingress/Dockerfile"
  target     = stage(variant)
  contexts   = merge(base_contexts(flavor), { fips-go = "target:go" })
  args = merge(base_args(), {
    GO_IMAGE      = "fips-go"
    NIC_VERSION   = NIC_VERSION
    NGINX_VERSION = NGINX_VERSION
  })
  tags       = tags("debian-fips-nginx-ingress", NIC_VERSION, "${flavor}${variant}")
  output     = output("debian-fips-nginx-ingress")
  attest     = attest()
  cache-from = cache_from("nginx-ingress${flavor}${variant}")
  cache-to   = cache_to("nginx-ingress${flavor}${variant}")
}

target "nginx-ingress-test" {
  name = "nginx-ingress${flavor}-test"
  matrix = {
    flavor = FLAVORS
  }
  context    = "."
  dockerfile = "images/nginx-ingress/Dockerfile"
  target     = "test"
  contexts = merge(base_contexts(flavor), {
    fips-base-test = "target:base${flavor}-test"
    fips-go        = "target:go"
  })
  args = merge(base_args(), {
    GO_IMAGE      = "fips-go"
    NIC_VERSION   = NIC_VERSION
    NGINX_VERSION = NGINX_VERSION
  })
  tags       = ["debian-fips-nginx-ingress:test${flavor}"]
  cache-from = cache_from("nginx-ingress${flavor}-test")
  cache-to   = cache_to("nginx-ingress${flavor}-test")
}
