# Dockerberg

A self-contained Docker container for Apache Iceberg development with SeaweedFS (S3-compatible storage), PostgreSQL (JDBC catalog), and Trino (query engine).

**Development use only.**

## Quick Start

```bash
# Build
docker build -t dockerberg .

# Run
docker run -d \
  -p 8080:8080 \
  -p 8333:8333 \
  -p 5432:5432 \
  --name dockerberg \
  dockerberg
```

## Test

```bash
# Query via Trino
docker exec -it dockerberg trino --execute "
  CREATE SCHEMA iceberg.test;
  CREATE TABLE iceberg.test.sample (id INT, name VARCHAR);
  INSERT INTO iceberg.test.sample VALUES (1, 'hello');
  SELECT * FROM iceberg.test.sample;
"

# List S3 objects (from host with aws cli)
aws --endpoint-url http://localhost:8333 s3 ls s3://warehouse/
```

## Ports

| Port | Service |
|------|---------|
| 8080 | Trino |
| 8333 | SeaweedFS S3 API |
| 5432 | PostgreSQL |

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `POSTGRES_USER` | `iceberg` | PostgreSQL user |
| `POSTGRES_PASSWORD` | `iceberg` | PostgreSQL password |
| `POSTGRES_DB` | `iceberg` | PostgreSQL database |
| `S3_ACCESS_KEY` | `admin` | SeaweedFS S3 access key |
| `S3_SECRET_KEY` | `admin123` | SeaweedFS S3 secret key |
| `WAREHOUSE_PATH` | `s3://warehouse` | Default Iceberg warehouse location |
| `CATALOG_NAME` | `iceberg` | Trino catalog name |
| `TRINO_MEMORY` | `2G` | Trino JVM heap size |

## Architecture

All services run inside a single container managed by supervisord:

- **PostgreSQL 16** — Stores Iceberg JDBC catalog metadata
- **SeaweedFS** — S3-compatible object storage for Iceberg data files
- **Trino 479** — SQL query engine with the Iceberg connector

## Data Persistence

Mount volumes to persist data across container restarts:

```bash
docker run -d \
  -v dockerberg-pg:/data/postgres \
  -v dockerberg-s3:/data/seaweedfs \
  -v dockerberg-trino:/data/trino \
  -p 8080:8080 -p 8333:8333 -p 5432:5432 \
  --name dockerberg \
  dockerberg
```

## Development

```bash
make build        # Build the Docker image
make test         # Run all BATS tests
make test-fast    # Fast tests only
make clean        # Remove test containers and image
```

Tests use [BATS](https://github.com/bats-core/bats-core) and live in the `test/` directory.

This project uses [Conventional Commits](https://www.conventionalcommits.org/) for commit messages. See [CLAUDE.md](CLAUDE.md) for full development guidelines.
