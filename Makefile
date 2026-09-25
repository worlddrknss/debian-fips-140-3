IMAGES := base go node bun

HADOLINT     := hadolint/hadolint:v2.15.1
SHELLCHECK   := koalaman/shellcheck:v0.11.0
ACTIONLINT   := rhysd/actionlint:1.7.12
MARKDOWNLINT := davidanson/markdownlint-cli2:v0.23.3
GO           := golang:1.27.1

DOCKER_RUN := docker run --rm -v "$(CURDIR):/repo" -w /repo

.PHONY: build test lint $(addprefix test-,$(IMAGES))

build:
	docker buildx bake --load

test: $(addprefix test-,$(IMAGES))

test-base:
	docker run --rm -v "$(CURDIR)/tests:/tests:ro" debian-fips-base:latest /tests/base.sh

test-go:
	docker run --rm -v "$(CURDIR)/tests:/tests:ro" debian-fips-go:latest sh -c '/tests/base.sh && /tests/go.sh'

test-node:
	docker run --rm -v "$(CURDIR)/tests:/tests:ro" debian-fips-node:latest sh -c '/tests/base.sh && /tests/node.sh'

test-bun:
	docker run --rm -v "$(CURDIR)/tests:/tests:ro" debian-fips-bun:latest sh -c '/tests/base.sh && /tests/node.sh && /tests/bun.sh'

lint:
	$(DOCKER_RUN) $(HADOLINT) hadolint images/base/Dockerfile images/go/Dockerfile images/node/Dockerfile images/bun/Dockerfile
	$(DOCKER_RUN) $(SHELLCHECK) tests/base.sh tests/go.sh tests/node.sh tests/bun.sh
	$(DOCKER_RUN) $(ACTIONLINT) -color=false
	$(DOCKER_RUN) $(MARKDOWNLINT) README.md
	$(DOCKER_RUN) -w /repo/tests/go $(GO) sh -c 'test -z "$$(gofmt -l .)" && go vet main.go'
	docker buildx bake --print >/dev/null
