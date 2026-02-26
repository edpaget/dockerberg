#!/usr/bin/env bats
# test/persistence.bats — Data survives container restart using named volumes

load test_helper/common

PERSIST_PG_VOL="dockerberg-persist-pg-$$"
PERSIST_SW_VOL="dockerberg-persist-sw-$$"
PERSIST_TR_VOL="dockerberg-persist-tr-$$"

setup_file() {
    # Create named volumes
    docker volume create "$PERSIST_PG_VOL" >/dev/null
    docker volume create "$PERSIST_SW_VOL" >/dev/null
    docker volume create "$PERSIST_TR_VOL" >/dev/null

    # --- First run: start container, insert data, stop ---
    CONTAINER_NAME="dockerberg-persist-1-$$"
    docker run -d --name "$CONTAINER_NAME" \
        -v "${PERSIST_PG_VOL}:/data/postgres" \
        -v "${PERSIST_SW_VOL}:/data/seaweedfs" \
        -v "${PERSIST_TR_VOL}:/data/trino" \
        "$DOCKERBERG_IMAGE"

    wait_for_all_services

    # Create schema, table, and insert data
    trino_exec "CREATE SCHEMA IF NOT EXISTS iceberg.persist_test"
    trino_exec "CREATE TABLE IF NOT EXISTS iceberg.persist_test.notes (
        id INTEGER,
        body VARCHAR
    )"
    trino_exec "INSERT INTO iceberg.persist_test.notes VALUES (1, 'survive restart')"

    # Also insert into PostgreSQL directly
    pg_exec "CREATE TABLE IF NOT EXISTS persist_check (val text)"
    pg_exec "INSERT INTO persist_check VALUES ('pg-persisted')"

    # Stop and remove first container
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1

    # --- Second run: start new container with same volumes ---
    CONTAINER_NAME="dockerberg-persist-2-$$"
    docker run -d --name "$CONTAINER_NAME" \
        -v "${PERSIST_PG_VOL}:/data/postgres" \
        -v "${PERSIST_SW_VOL}:/data/seaweedfs" \
        -v "${PERSIST_TR_VOL}:/data/trino" \
        "$DOCKERBERG_IMAGE"

    wait_for_all_services
}

teardown_file() {
    docker rm -f "dockerberg-persist-1-$$" >/dev/null 2>&1 || true
    docker rm -f "dockerberg-persist-2-$$" >/dev/null 2>&1 || true
    docker volume rm "$PERSIST_PG_VOL" "$PERSIST_SW_VOL" "$PERSIST_TR_VOL" >/dev/null 2>&1 || true
}

@test "PostgreSQL data survives restart" {
    result=$(pg_exec "SELECT val FROM persist_check LIMIT 1")
    [ "$result" = "pg-persisted" ]
}

@test "Iceberg schema survives restart" {
    result=$(trino_exec "SHOW SCHEMAS FROM iceberg")
    [[ "$result" == *"persist_test"* ]]
}

@test "Iceberg table survives restart" {
    result=$(trino_exec "SHOW TABLES FROM iceberg.persist_test")
    [[ "$result" == *"notes"* ]]
}

@test "Iceberg data survives restart" {
    result=$(trino_exec "SELECT body FROM iceberg.persist_test.notes WHERE id = 1")
    [[ "$result" == *"survive restart"* ]]
}
