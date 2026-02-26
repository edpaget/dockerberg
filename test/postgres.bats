#!/usr/bin/env bats
# test/postgres.bats — PostgreSQL connectivity, auth, and basic CRUD

load test_helper/common

setup_file() {
    start_container
    wait_for_postgres
}

teardown_file() {
    stop_container
}

@test "default database 'iceberg' exists" {
    result=$(pg_exec "SELECT datname FROM pg_database WHERE datname='iceberg'")
    [ "$result" = "iceberg" ]
}

@test "default user 'iceberg' can authenticate" {
    run pg_exec "SELECT 1"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "create table" {
    run pg_exec "CREATE TABLE test_crud (id serial PRIMARY KEY, name text)"
    [ "$status" -eq 0 ]
}

@test "insert row" {
    pg_exec "CREATE TABLE IF NOT EXISTS test_crud (id serial PRIMARY KEY, name text)"
    run pg_exec "INSERT INTO test_crud (name) VALUES ('hello') RETURNING id"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "select row" {
    pg_exec "CREATE TABLE IF NOT EXISTS test_crud (id serial PRIMARY KEY, name text)"
    pg_exec "INSERT INTO test_crud (name) VALUES ('hello')" || true
    result=$(pg_exec "SELECT name FROM test_crud WHERE id=1")
    [ "$result" = "hello" ]
}

@test "update row" {
    pg_exec "CREATE TABLE IF NOT EXISTS test_crud (id serial PRIMARY KEY, name text)"
    pg_exec "INSERT INTO test_crud (name) VALUES ('hello')" || true
    pg_exec "UPDATE test_crud SET name='world' WHERE id=1"
    result=$(pg_exec "SELECT name FROM test_crud WHERE id=1")
    [ "$result" = "world" ]
}

@test "delete row" {
    pg_exec "CREATE TABLE IF NOT EXISTS test_crud (id serial PRIMARY KEY, name text)"
    pg_exec "INSERT INTO test_crud (name) VALUES ('hello')" || true
    pg_exec "DELETE FROM test_crud WHERE id=1"
    result=$(pg_exec "SELECT count(*) FROM test_crud WHERE id=1")
    [ "$result" = "0" ]
}
