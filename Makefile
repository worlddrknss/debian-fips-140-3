IMAGES  := base go node bun python dotnet java
FLAVORS := "" -pqc

HADOLINT     := hadolint/hadolint:v2.15.1
SHELLCHECK   := koalaman/shellcheck:v0.11.0
ACTIONLINT   := rhysd/actionlint:1.7.12
MARKDOWNLINT := davidanson/markdownlint-cli2:v0.23.3
GO           := golang:1.27.1

DOCKER_RUN := docker run --rm -v "$(CURDIR):/repo" -w /repo
# Mounts the test suite. Distroless images are tested through their :test
# variant (runtime + busybox + openssl CLI), since they have no shell.
TEST_RUN := docker run --rm -v "$(CURDIR)/tests:/tests:ro"

.PHONY: build test lint distroless $(addprefix test-,$(IMAGES))

build:
	docker buildx bake --load default test

test: $(addprefix test-,$(IMAGES)) distroless

# $(call suite,<image>,<scripts>): runs the scripts against the distroless
# (:test) and dev variants of both flavors.
define suite
	@for f in $(FLAVORS); do \
	  for ref in "$(1):test$$f" "$(1):latest$$f-dev"; do \
	    echo "== $$ref"; \
	    $(TEST_RUN) "$$ref" sh -c '$(2)' || exit 1; \
	  done; \
	done
endef

test-base:
	$(call suite,debian-fips-base,/tests/base.sh)

# Builds the check program in the Go image, then runs the static binary on the
# distroless base to prove Go binaries need nothing else.
test-go:
	$(TEST_RUN) debian-fips-go:latest sh -c '/tests/base.sh && /tests/go.sh'
	docker volume create fips-go-test >/dev/null
	docker run --rm -v "$(CURDIR)/tests:/tests:ro" -v fips-go-test:/out debian-fips-go:latest \
	  sh -c 'mkdir /work && cd /work && cp /tests/go/main.go . && go mod init fipscheck >/dev/null 2>&1 && go build -o /out/fipscheck .'
	docker run --rm -v fips-go-test:/out:ro debian-fips-base:latest /out/fipscheck; \
	  status=$$?; docker volume rm fips-go-test >/dev/null; exit $$status

test-node:
	$(call suite,debian-fips-node,/tests/base.sh && /tests/node.sh)

test-bun:
	$(call suite,debian-fipsbase-bun,/tests/base.sh && /tests/bun.sh)

test-python:
	$(call suite,debian-fips-python,/tests/base.sh && /tests/python.sh)

test-dotnet:
	$(call suite,debian-fips-dotnet,/tests/base.sh && /tests/dotnet.sh)

test-java:
	$(call suite,debian-fips-java,/tests/base.sh && /tests/java.sh)

# The published distroless images must have no shell and run as nonroot.
distroless:
	@for image in debian-fips-base debian-fips-node debian-fipsbase-bun debian-fips-python debian-fips-dotnet debian-fips-java; do \
	  for tag in latest latest-pqc; do \
	    ref="$$image:$$tag"; \
	    if docker run --rm --entrypoint /bin/sh "$$ref" -c true >/dev/null 2>&1; then \
	      echo "FAIL: $$ref has a shell"; exit 1; fi; \
	    user="$$(docker inspect -f '{{.Config.User}}' "$$ref")"; \
	    [ "$$user" = "65532:65532" ] || { echo "FAIL: $$ref runs as '$$user'"; exit 1; }; \
	    echo "PASS: $$ref has no shell and runs as 65532"; \
	  done; \
	done

lint:
	$(DOCKER_RUN) $(HADOLINT) hadolint images/*/Dockerfile
	$(DOCKER_RUN) $(SHELLCHECK) tests/*.sh scripts/*.sh images/rootfs/install-packages.sh images/java/configure-fips.sh
	$(DOCKER_RUN) $(ACTIONLINT) -color=false
	$(DOCKER_RUN) $(MARKDOWNLINT) '*.md'
	$(DOCKER_RUN) -w /repo/tests/go $(GO) sh -c 'test -z "$$(gofmt -l .)" && go vet main.go'
	docker buildx bake --print default test >/dev/null
