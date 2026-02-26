# Makefile for Dockerberg test suite
#
# Usage:
#   make build       — Build the Docker image
#   make test        — Run all tests (full suite, ~14 min)
#   make test-fast   — Run fast tests only (~6 min)
#   make test-slow   — Run slow tests only (env_vars + persistence)
#   make clean       — Remove test containers and image

DOCKERBERG_IMAGE ?= dockerberg:test
export DOCKERBERG_IMAGE

.PHONY: build test test-fast test-slow clean

build:
	docker build -t $(DOCKERBERG_IMAGE) .

test: build
	bats test/build.bats \
	     test/health.bats \
	     test/postgres.bats \
	     test/seaweedfs.bats \
	     test/trino.bats \
	     test/iceberg.bats \
	     test/env_vars.bats \
	     test/persistence.bats

test-fast: build
	bats test/build.bats \
	     test/health.bats \
	     test/postgres.bats \
	     test/seaweedfs.bats \
	     test/trino.bats \
	     test/iceberg.bats

test-slow: build
	bats test/env_vars.bats \
	     test/persistence.bats

clean:
	@echo "Removing test containers..."
	@docker ps -a --filter "name=dockerberg-test" --filter "name=dockerberg-envtest" --filter "name=dockerberg-persist" -q | xargs -r docker rm -f 2>/dev/null || true
	@echo "Removing test volumes..."
	@docker volume ls --filter "name=dockerberg-persist" -q | xargs -r docker volume rm 2>/dev/null || true
	@echo "Removing test image..."
	@docker rmi $(DOCKERBERG_IMAGE) 2>/dev/null || true
	@echo "Clean complete."
