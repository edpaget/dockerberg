#!/usr/bin/env bats
# test/health.bats — Verify all services start and respond

load test_helper/common

setup_file() {
    start_container
    wait_for_all_services
}

teardown_file() {
    stop_container
}

@test "supervisord is PID 1" {
    run container_exec ps -p 1 -o comm=
    [ "$status" -eq 0 ]
    [[ "$output" == *"supervisord"* ]]
}

@test "PostgreSQL responds to pg_isready" {
    run container_exec pg_isready -h 127.0.0.1 -p 5432
    [ "$status" -eq 0 ]
}

@test "SeaweedFS S3 endpoint responds" {
    run container_exec curl -s -o /dev/null -w '%{http_code}' http://localhost:8333/
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
}

@test "Trino reports starting:false" {
    run container_exec curl -sf http://localhost:8080/v1/info
    [ "$status" -eq 0 ]
    [[ "$output" == *'"starting":false'* ]]
}

@test "Trino reports node as active" {
    run container_exec curl -sf http://localhost:8080/v1/info/state
    [ "$status" -eq 0 ]
    [[ "$output" == *"ACTIVE"* ]]
}
