# test/test_helper/common.bash — Shared helpers for Dockerberg BATS tests

# Image name (override in CI with DOCKERBERG_IMAGE env var)
export DOCKERBERG_IMAGE="${DOCKERBERG_IMAGE:-dockerberg:test}"

# Generate a unique container name using PID to avoid collisions
_container_name() {
    echo "dockerberg-test-${BATS_SUITE_TEST_NUMBER:-0}-$$"
}

# Start a container with optional extra docker-run args.
# Usage: start_container [docker-run args...]
# Sets CONTAINER_NAME for use in subsequent helpers.
start_container() {
    export CONTAINER_NAME="$(_container_name)"
    docker run -d --name "$CONTAINER_NAME" "$@" "$DOCKERBERG_IMAGE"
}

# Stop and remove the container.
stop_container() {
    if [ -n "${CONTAINER_NAME:-}" ]; then
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
}

# Execute a command inside the running container.
# Usage: container_exec <command> [args...]
container_exec() {
    docker exec "$CONTAINER_NAME" "$@"
}

# Wait for PostgreSQL to accept connections (max 30s).
wait_for_postgres() {
    local max_wait="${1:-30}"
    local elapsed=0
    echo "# Waiting for PostgreSQL (max ${max_wait}s)..." >&3
    while [ "$elapsed" -lt "$max_wait" ]; do
        if container_exec pg_isready -h 127.0.0.1 -p 5432 -q 2>/dev/null; then
            echo "# PostgreSQL ready after ${elapsed}s" >&3
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "# PostgreSQL did not become ready within ${max_wait}s" >&3
    return 1
}

# Wait for SeaweedFS S3 endpoint to respond (max 30s).
wait_for_seaweedfs() {
    local max_wait="${1:-30}"
    local elapsed=0
    echo "# Waiting for SeaweedFS S3 (max ${max_wait}s)..." >&3
    while [ "$elapsed" -lt "$max_wait" ]; do
        if container_exec curl -s -o /dev/null -w '%{http_code}' http://localhost:8333/ 2>/dev/null | grep -q '[234]'; then
            echo "# SeaweedFS ready after ${elapsed}s" >&3
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    echo "# SeaweedFS did not become ready within ${max_wait}s" >&3
    return 1
}

# Wait for Trino to finish starting (max 120s, poll every 2s).
wait_for_trino() {
    local max_wait="${1:-120}"
    local elapsed=0
    echo "# Waiting for Trino (max ${max_wait}s)..." >&3
    while [ "$elapsed" -lt "$max_wait" ]; do
        local info
        info=$(container_exec curl -sf http://localhost:8080/v1/info 2>/dev/null) || true
        if echo "$info" | grep -q '"starting":false'; then
            echo "# Trino ready after ${elapsed}s" >&3
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "# Trino did not become ready within ${max_wait}s" >&3
    return 1
}

# Wait for the warehouse bucket to exist and accept writes (max 60s).
# SeaweedFS volume server needs time to initialize after the filer is up.
wait_for_warehouse_bucket() {
    local max_wait="${1:-60}"
    local elapsed=0
    echo "# Waiting for warehouse bucket (max ${max_wait}s)..." >&3
    while [ "$elapsed" -lt "$max_wait" ]; do
        if container_exec curl -sf -X PUT -d "healthcheck" http://localhost:8888/buckets/warehouse/.healthcheck >/dev/null 2>&1; then
            container_exec curl -sf -X DELETE http://localhost:8888/buckets/warehouse/.healthcheck >/dev/null 2>&1 || true
            echo "# Warehouse bucket ready after ${elapsed}s" >&3
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "# Warehouse bucket did not become writable within ${max_wait}s" >&3
    return 1
}

# Wait for all three services.
wait_for_all_services() {
    wait_for_postgres
    wait_for_seaweedfs
    wait_for_trino
}

# Run a SQL statement via psql inside the container.
# Usage: pg_exec "SELECT 1"
# Connects as the default iceberg user to the iceberg database.
pg_exec() {
    local sql="$1"
    local user="${2:-iceberg}"
    local db="${3:-iceberg}"
    container_exec env PGPASSWORD="${POSTGRES_PASSWORD:-iceberg}" psql -h 127.0.0.1 -U "$user" -d "$db" -tAqc "$sql"
}

# Run a SQL statement via the Trino CLI inside the container.
# Usage: trino_exec "SELECT 1"
trino_exec() {
    local sql="$1"
    local catalog="${2:-iceberg}"
    container_exec trino --execute "$sql" --catalog "$catalog" --output-format TSV 2>/dev/null
}

# Run a curl command against the S3 endpoint inside the container.
# Usage: s3_curl [curl args...]
s3_curl() {
    container_exec curl -sf "$@"
}
