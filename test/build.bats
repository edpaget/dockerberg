#!/usr/bin/env bats
# test/build.bats — Validate the Docker image builds and contains expected artifacts

load test_helper/common

setup_file() {
    # Build the image (skip if DOCKERBERG_SKIP_BUILD is set)
    if [ -z "${DOCKERBERG_SKIP_BUILD:-}" ]; then
        docker build -t "$DOCKERBERG_IMAGE" "$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    fi
}

@test "image builds successfully" {
    run docker image inspect "$DOCKERBERG_IMAGE"
    [ "$status" -eq 0 ]
}

@test "image contains PostgreSQL binary" {
    run docker run --rm --entrypoint bash "$DOCKERBERG_IMAGE" -c "which pg_isready"
    [ "$status" -eq 0 ]
}

@test "image contains SeaweedFS binary" {
    run docker run --rm --entrypoint bash "$DOCKERBERG_IMAGE" -c "which weed"
    [ "$status" -eq 0 ]
}

@test "image contains Trino server" {
    run docker run --rm --entrypoint bash "$DOCKERBERG_IMAGE" -c "test -x /opt/trino/bin/launcher"
    [ "$status" -eq 0 ]
}

@test "image contains Trino CLI" {
    run docker run --rm --entrypoint bash "$DOCKERBERG_IMAGE" -c "test -x /usr/local/bin/trino"
    [ "$status" -eq 0 ]
}

@test "image contains supervisord" {
    run docker run --rm --entrypoint bash "$DOCKERBERG_IMAGE" -c "which supervisord"
    [ "$status" -eq 0 ]
}

@test "image exposes port 8080 (Trino)" {
    run docker image inspect --format '{{json .Config.ExposedPorts}}' "$DOCKERBERG_IMAGE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"8080"* ]]
}

@test "image exposes port 8333 (SeaweedFS S3)" {
    run docker image inspect --format '{{json .Config.ExposedPorts}}' "$DOCKERBERG_IMAGE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"8333"* ]]
}

@test "image exposes port 5432 (PostgreSQL)" {
    run docker image inspect --format '{{json .Config.ExposedPorts}}' "$DOCKERBERG_IMAGE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"5432"* ]]
}

@test "image declares /data/postgres volume" {
    run docker image inspect --format '{{json .Config.Volumes}}' "$DOCKERBERG_IMAGE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"/data/postgres"* ]]
}

@test "image declares /data/seaweedfs volume" {
    run docker image inspect --format '{{json .Config.Volumes}}' "$DOCKERBERG_IMAGE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"/data/seaweedfs"* ]]
}

@test "image declares /data/trino volume" {
    run docker image inspect --format '{{json .Config.Volumes}}' "$DOCKERBERG_IMAGE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"/data/trino"* ]]
}

@test "entrypoint is /entrypoint.sh" {
    run docker image inspect --format '{{json .Config.Entrypoint}}' "$DOCKERBERG_IMAGE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"/entrypoint.sh"* ]]
}
