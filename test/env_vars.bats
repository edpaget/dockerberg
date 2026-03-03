#!/usr/bin/env bats
# test/env_vars.bats — Verify custom environment variable overrides

load test_helper/common

# --- Custom POSTGRES_USER / POSTGRES_DB ---

@test "custom POSTGRES_USER and POSTGRES_DB" {
    CONTAINER_NAME="dockerberg-envtest-pg-$$"
    docker run -d --name "$CONTAINER_NAME" \
        -e POSTGRES_USER=myuser \
        -e POSTGRES_PASSWORD=mypass \
        -e POSTGRES_DB=mydb \
        "$DOCKERBERG_IMAGE"

    # Wait for PostgreSQL
    local elapsed=0
    while [ "$elapsed" -lt 30 ]; do
        if docker exec "$CONTAINER_NAME" pg_isready -h 127.0.0.1 -p 5432 -q 2>/dev/null; then
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    # Verify the custom user can connect to the custom database
    result=$(docker exec "$CONTAINER_NAME" env PGPASSWORD=mypass psql -h 127.0.0.1 -U myuser -d mydb -tAqc "SELECT 1")
    [ "$result" = "1" ]

    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
}

# --- Custom CATALOG_NAME ---

@test "custom CATALOG_NAME" {
    CONTAINER_NAME="dockerberg-envtest-cat-$$"
    docker run -d --name "$CONTAINER_NAME" \
        -e CATALOG_NAME=my_lakehouse \
        "$DOCKERBERG_IMAGE"

    # Wait for Trino
    local elapsed=0
    while [ "$elapsed" -lt 120 ]; do
        local info
        info=$(docker exec "$CONTAINER_NAME" curl -sf http://localhost:8080/v1/info 2>/dev/null) || true
        if echo "$info" | grep -q '"starting":false'; then
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    result=$(docker exec "$CONTAINER_NAME" trino --execute "SHOW CATALOGS" --output-format TSV 2>/dev/null)
    [[ "$result" == *"my_lakehouse"* ]]

    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
}

# --- Custom S3 keys ---

@test "custom S3_ACCESS_KEY and S3_SECRET_KEY" {
    CONTAINER_NAME="dockerberg-envtest-s3-$$"
    docker run -d --name "$CONTAINER_NAME" \
        -e S3_ACCESS_KEY=customaccess \
        -e S3_SECRET_KEY=customsecret \
        "$DOCKERBERG_IMAGE"

    # Wait for SeaweedFS
    local elapsed=0
    while [ "$elapsed" -lt 30 ]; do
        if docker exec "$CONTAINER_NAME" curl -s -o /dev/null -w '%{http_code}' http://localhost:8333/ 2>/dev/null | grep -q '[234]'; then
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    # SeaweedFS S3 should still be reachable (403 is OK — auth is configured)
    run docker exec "$CONTAINER_NAME" curl -s -o /dev/null -w '%{http_code}' http://localhost:8333/
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]

    # Verify config file has the custom keys
    run docker exec "$CONTAINER_NAME" cat /etc/seaweedfs/s3.json
    [ "$status" -eq 0 ]
    [[ "$output" == *"customaccess"* ]]
    [[ "$output" == *"customsecret"* ]]

    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
}

# --- Custom TRINO_MEMORY ---

@test "custom TRINO_MEMORY" {
    CONTAINER_NAME="dockerberg-envtest-mem-$$"
    docker run -d --name "$CONTAINER_NAME" \
        -e TRINO_MEMORY=1G \
        "$DOCKERBERG_IMAGE"

    # Give entrypoint time to generate configs
    sleep 5

    result=$(docker exec "$CONTAINER_NAME" cat /etc/trino/jvm.config)
    [[ "$result" == *"-Xmx1G"* ]]

    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
}

# --- Custom WAREHOUSE_PATH ---

@test "custom WAREHOUSE_PATH" {
    CONTAINER_NAME="dockerberg-envtest-wh-$$"
    docker run -d --name "$CONTAINER_NAME" \
        -e WAREHOUSE_PATH=s3://custom-bucket \
        "$DOCKERBERG_IMAGE"

    # Wait for SeaweedFS filer
    local elapsed=0
    while [ "$elapsed" -lt 30 ]; do
        if docker exec "$CONTAINER_NAME" curl -sf http://localhost:8888/ >/dev/null 2>&1; then
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    # Wait for the custom bucket to be created by the entrypoint background process
    elapsed=0
    while [ "$elapsed" -lt 30 ]; do
        if docker exec "$CONTAINER_NAME" curl -sf http://localhost:8888/buckets/custom-bucket/ >/dev/null 2>&1; then
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    # Verify the custom bucket was created
    run docker exec "$CONTAINER_NAME" curl -sf http://localhost:8888/buckets/custom-bucket/
    [ "$status" -eq 0 ]

    # Verify Trino catalog points to custom warehouse path
    result=$(docker exec "$CONTAINER_NAME" cat /etc/trino/catalog/iceberg.properties)
    [[ "$result" == *"s3://custom-bucket"* ]]

    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
}
