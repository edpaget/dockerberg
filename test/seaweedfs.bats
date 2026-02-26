#!/usr/bin/env bats
# test/seaweedfs.bats — SeaweedFS S3 endpoint, bucket, and object operations

load test_helper/common

setup_file() {
    start_container
    wait_for_seaweedfs
}

teardown_file() {
    stop_container
}

@test "S3 endpoint is reachable" {
    run s3_curl http://localhost:8333/
    [ "$status" -eq 0 ]
}

@test "warehouse bucket exists" {
    run s3_curl http://localhost:8333/warehouse/
    [ "$status" -eq 0 ]
}

@test "PUT object to warehouse bucket" {
    run container_exec curl -sf -X PUT \
        -d "test-data-content" \
        http://localhost:8333/warehouse/test-object.txt
    [ "$status" -eq 0 ]
}

@test "GET object from warehouse bucket" {
    # Ensure the object exists
    container_exec curl -sf -X PUT \
        -d "test-data-content" \
        http://localhost:8333/warehouse/test-object.txt

    run s3_curl http://localhost:8333/warehouse/test-object.txt
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-data-content"* ]]
}

@test "DELETE object from warehouse bucket" {
    # Ensure the object exists
    container_exec curl -sf -X PUT \
        -d "delete-me" \
        http://localhost:8333/warehouse/delete-test.txt

    run container_exec curl -sf -X DELETE \
        http://localhost:8333/warehouse/delete-test.txt
    [ "$status" -eq 0 ]

    # Verify it's gone (expect 404 / non-zero exit)
    run s3_curl http://localhost:8333/warehouse/delete-test.txt
    [ "$status" -ne 0 ]
}
