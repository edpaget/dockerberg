#!/usr/bin/env bats
# test/iceberg.bats — Full Iceberg workflow: schema, table, insert, query, verify metadata

load test_helper/common

setup_file() {
    start_container
    wait_for_all_services
}

teardown_file() {
    stop_container
}

@test "create schema in iceberg catalog" {
    run trino_exec "CREATE SCHEMA IF NOT EXISTS iceberg.test_schema"
    [ "$status" -eq 0 ]
}

@test "schema appears in SHOW SCHEMAS" {
    trino_exec "CREATE SCHEMA IF NOT EXISTS iceberg.test_schema"
    result=$(trino_exec "SHOW SCHEMAS FROM iceberg")
    [[ "$result" == *"test_schema"* ]]
}

@test "create Iceberg table" {
    trino_exec "CREATE SCHEMA IF NOT EXISTS iceberg.test_schema"
    run trino_exec "CREATE TABLE IF NOT EXISTS iceberg.test_schema.users (
        id INTEGER,
        name VARCHAR,
        created_at TIMESTAMP
    )"
    [ "$status" -eq 0 ]
}

@test "table appears in SHOW TABLES" {
    trino_exec "CREATE SCHEMA IF NOT EXISTS iceberg.test_schema"
    trino_exec "CREATE TABLE IF NOT EXISTS iceberg.test_schema.users (
        id INTEGER,
        name VARCHAR,
        created_at TIMESTAMP
    )"
    result=$(trino_exec "SHOW TABLES FROM iceberg.test_schema")
    [[ "$result" == *"users"* ]]
}

@test "insert data into Iceberg table" {
    trino_exec "CREATE SCHEMA IF NOT EXISTS iceberg.test_schema"
    trino_exec "CREATE TABLE IF NOT EXISTS iceberg.test_schema.users (
        id INTEGER,
        name VARCHAR,
        created_at TIMESTAMP
    )"
    run trino_exec "INSERT INTO iceberg.test_schema.users VALUES
        (1, 'Alice', TIMESTAMP '2024-01-01 00:00:00'),
        (2, 'Bob', TIMESTAMP '2024-01-02 00:00:00'),
        (3, 'Charlie', TIMESTAMP '2024-01-03 00:00:00')"
    [ "$status" -eq 0 ]
}

@test "query data from Iceberg table" {
    trino_exec "CREATE SCHEMA IF NOT EXISTS iceberg.test_schema"
    trino_exec "CREATE TABLE IF NOT EXISTS iceberg.test_schema.users (
        id INTEGER,
        name VARCHAR,
        created_at TIMESTAMP
    )"
    trino_exec "INSERT INTO iceberg.test_schema.users VALUES
        (1, 'Alice', TIMESTAMP '2024-01-01 00:00:00'),
        (2, 'Bob', TIMESTAMP '2024-01-02 00:00:00'),
        (3, 'Charlie', TIMESTAMP '2024-01-03 00:00:00')" 2>/dev/null || true

    result=$(trino_exec "SELECT count(*) FROM iceberg.test_schema.users")
    [[ "$result" == *"3"* ]]
}

@test "query returns correct data" {
    trino_exec "CREATE SCHEMA IF NOT EXISTS iceberg.test_schema"
    trino_exec "CREATE TABLE IF NOT EXISTS iceberg.test_schema.users (
        id INTEGER,
        name VARCHAR,
        created_at TIMESTAMP
    )"
    trino_exec "INSERT INTO iceberg.test_schema.users VALUES
        (1, 'Alice', TIMESTAMP '2024-01-01 00:00:00'),
        (2, 'Bob', TIMESTAMP '2024-01-02 00:00:00'),
        (3, 'Charlie', TIMESTAMP '2024-01-03 00:00:00')" 2>/dev/null || true

    result=$(trino_exec "SELECT name FROM iceberg.test_schema.users WHERE id = 1")
    [[ "$result" == *"Alice"* ]]
}

@test "Iceberg metadata exists in PostgreSQL" {
    trino_exec "CREATE SCHEMA IF NOT EXISTS iceberg.test_schema"
    trino_exec "CREATE TABLE IF NOT EXISTS iceberg.test_schema.users (
        id INTEGER,
        name VARCHAR,
        created_at TIMESTAMP
    )"

    # The JDBC catalog stores metadata in the iceberg PostgreSQL database
    result=$(pg_exec "SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog', 'information_schema')")
    # Should have at least one table (iceberg catalog metadata)
    [ "$result" -gt 0 ]
}

@test "data files exist in S3 warehouse" {
    trino_exec "CREATE SCHEMA IF NOT EXISTS iceberg.test_schema"
    trino_exec "CREATE TABLE IF NOT EXISTS iceberg.test_schema.users (
        id INTEGER,
        name VARCHAR,
        created_at TIMESTAMP
    )"
    trino_exec "INSERT INTO iceberg.test_schema.users VALUES
        (1, 'Alice', TIMESTAMP '2024-01-01 00:00:00')" 2>/dev/null || true

    # List objects under the warehouse bucket — should find data files
    run s3_curl "http://localhost:8333/warehouse/?prefix=test_schema"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test_schema"* ]]
}

@test "drop table succeeds" {
    trino_exec "CREATE SCHEMA IF NOT EXISTS iceberg.test_schema"
    trino_exec "CREATE TABLE IF NOT EXISTS iceberg.test_schema.drop_test (id INTEGER)"
    run trino_exec "DROP TABLE iceberg.test_schema.drop_test"
    [ "$status" -eq 0 ]
}

@test "drop schema succeeds" {
    trino_exec "CREATE SCHEMA IF NOT EXISTS iceberg.drop_schema"
    run trino_exec "DROP SCHEMA iceberg.drop_schema"
    [ "$status" -eq 0 ]
}
