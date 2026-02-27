#!/bin/bash
set -euo pipefail

# --- Default ENV vars ---
export POSTGRES_USER="${POSTGRES_USER:-iceberg}"
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-iceberg}"
export POSTGRES_DB="${POSTGRES_DB:-iceberg}"
export S3_ACCESS_KEY="${S3_ACCESS_KEY:-admin}"
export S3_SECRET_KEY="${S3_SECRET_KEY:-admin123}"
export WAREHOUSE_PATH="${WAREHOUSE_PATH:-s3://warehouse}"
export CATALOG_NAME="${CATALOG_NAME:-iceberg}"
export TRINO_MEMORY="${TRINO_MEMORY:-2G}"

# --- Initialize PostgreSQL if needed ---
if [ ! -f /data/postgres/PG_VERSION ]; then
    echo "Initializing PostgreSQL data directory..."
    chown postgres:postgres /data/postgres
    su - postgres -c "/usr/lib/postgresql/16/bin/initdb -D /data/postgres"

    # Configure pg_hba.conf for local connections
    cat > /data/postgres/pg_hba.conf <<EOF
local   all   all                 trust
host    all   all   127.0.0.1/32  md5
host    all   all   ::1/128       md5
host    all   all   0.0.0.0/0     md5
EOF

    # Configure postgresql.conf
    cat >> /data/postgres/postgresql.conf <<EOF
listen_addresses = '*'
port = 5432
EOF

    # Start PostgreSQL temporarily to create user and database
    su - postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /data/postgres -w start"

    su - postgres -c "psql -c \"CREATE USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}';\""  2>/dev/null || true
    su - postgres -c "psql -c \"CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER};\"" 2>/dev/null || true

    # Pre-create Iceberg JDBC catalog metadata tables (works around schema migration bug)
    PGPASSWORD="${POSTGRES_PASSWORD}" psql -U "${POSTGRES_USER}" -h 127.0.0.1 -d "${POSTGRES_DB}" <<EOSQL
CREATE TABLE IF NOT EXISTS iceberg_tables (
    catalog_name VARCHAR(255) NOT NULL,
    table_namespace VARCHAR(255) NOT NULL,
    table_name VARCHAR(255) NOT NULL,
    metadata_location VARCHAR(1000),
    previous_metadata_location VARCHAR(1000),
    iceberg_type VARCHAR(5),
    PRIMARY KEY (catalog_name, table_namespace, table_name)
);
CREATE TABLE IF NOT EXISTS iceberg_namespace_properties (
    catalog_name VARCHAR(255) NOT NULL,
    namespace VARCHAR(255) NOT NULL,
    property_key VARCHAR(255) NOT NULL,
    property_value VARCHAR(1000),
    PRIMARY KEY (catalog_name, namespace, property_key)
);
EOSQL

    su - postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /data/postgres -w stop"
    echo "PostgreSQL initialized."
fi

# Ensure correct ownership
chown -R postgres:postgres /data/postgres

# --- Ensure SeaweedFS directories exist ---
mkdir -p /data/seaweedfs/master

# --- Generate SeaweedFS S3 config ---
mkdir -p /etc/seaweedfs
cat > /etc/seaweedfs/s3.json <<EOF
{
  "identities": [
    {
      "name": "admin",
      "credentials": [
        {
          "accessKey": "${S3_ACCESS_KEY}",
          "secretKey": "${S3_SECRET_KEY}"
        }
      ],
      "actions": [
        "Admin",
        "Read",
        "List",
        "Tagging",
        "Write"
      ]
    }
  ]
}
EOF

# --- Generate Trino configs from templates ---
TRINO_ETC=/etc/trino

envsubst < /opt/trino-templates/config.properties.template > "${TRINO_ETC}/config.properties"
envsubst < /opt/trino-templates/jvm.config.template > "${TRINO_ETC}/jvm.config"
envsubst < /opt/trino-templates/node.properties.template > "${TRINO_ETC}/node.properties"

mkdir -p "${TRINO_ETC}/catalog"
envsubst < /opt/trino-templates/catalog/iceberg.properties.template > "${TRINO_ETC}/catalog/${CATALOG_NAME}.properties"

# Ensure Trino data directory exists with correct ownership
mkdir -p /data/trino
chown -R trino:trino /data/trino
chown -R trino:trino "${TRINO_ETC}"

# --- Create warehouse bucket in the background after SeaweedFS starts ---
BUCKET_NAME="${WAREHOUSE_PATH#s3://}"
BUCKET_NAME="${BUCKET_NAME%%/*}"

(
    echo "Waiting for SeaweedFS S3 API to create bucket..."
    for i in $(seq 1 60); do
        if curl -s -o /dev/null -w '%{http_code}' http://localhost:8333/ 2>/dev/null | grep -q '[234]'; then
            echo "Creating bucket: ${BUCKET_NAME}"
            # Use SeaweedFS filer API to create the bucket directory (no auth needed)
            curl -sf -X POST "http://localhost:8888/buckets/${BUCKET_NAME}/" 2>/dev/null || echo "Bucket may already exist"
            echo "Warehouse bucket ready."
            exit 0
        fi
        sleep 1
    done
    echo "WARNING: Timed out waiting for SeaweedFS S3 API"
) &

# --- Start supervisord ---
echo "Starting all services via supervisord..."
exec /usr/bin/supervisord -c /etc/supervisord.conf
