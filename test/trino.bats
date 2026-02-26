#!/usr/bin/env bats
# test/trino.bats — Trino CLI connectivity, catalog registration, system queries

load test_helper/common

setup_file() {
    start_container
    wait_for_all_services
}

teardown_file() {
    stop_container
}

@test "Trino CLI connects and runs SELECT 1" {
    result=$(trino_exec "SELECT 1")
    [[ "$result" == *"1"* ]]
}

@test "iceberg catalog is registered" {
    result=$(trino_exec "SHOW CATALOGS")
    [[ "$result" == *"iceberg"* ]]
}

@test "system catalog is available" {
    result=$(trino_exec "SHOW CATALOGS")
    [[ "$result" == *"system"* ]]
}

@test "can list schemas in iceberg catalog" {
    run trino_exec "SHOW SCHEMAS FROM iceberg"
    [ "$status" -eq 0 ]
    # At minimum, 'information_schema' should exist
    [[ "$output" == *"information_schema"* ]]
}

@test "can query system runtime nodes" {
    result=$(trino_exec "SELECT count(*) FROM system.runtime.nodes" "system")
    [[ "$result" == *"1"* ]]
}

@test "Trino version is queryable" {
    run trino_exec "SELECT version()"
    [ "$status" -eq 0 ]
    # Should return a version string (numeric)
    [[ "$output" =~ [0-9]+ ]]
}
