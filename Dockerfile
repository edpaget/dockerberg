FROM ubuntu:24.04

ARG TRINO_VERSION=476
ARG TARGETARCH
ARG PG_JDBC_VERSION=42.7.7

ENV DEBIAN_FRONTEND=noninteractive

# --- Install system packages + Adoptium Temurin Java 24 ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gettext-base \
    gnupg2 \
    lsb-release \
    postgresql-16 \
    supervisor \
    && curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor -o /usr/share/keyrings/adoptium.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb noble main" \
        > /etc/apt/sources.list.d/adoptium.list \
    && apt-get update && apt-get install -y --no-install-recommends temurin-24-jre \
    && rm -rf /var/lib/apt/lists/*

# --- Install SeaweedFS (arch-aware) ---
RUN SEAWEED_ARCH=$(case "${TARGETARCH}" in arm64) echo "linux_arm64";; *) echo "linux_amd64";; esac) \
    && curl -fSL "https://github.com/seaweedfs/seaweedfs/releases/latest/download/${SEAWEED_ARCH}.tar.gz" -o /tmp/seaweedfs.tar.gz \
    && tar -xzf /tmp/seaweedfs.tar.gz -C /usr/local/bin/ \
    && chmod +x /usr/local/bin/weed \
    && rm /tmp/seaweedfs.tar.gz

# --- Install Trino ---
RUN curl -fSL "https://repo1.maven.org/maven2/io/trino/trino-server/${TRINO_VERSION}/trino-server-${TRINO_VERSION}.tar.gz" \
        -o /tmp/trino-server.tar.gz \
    && tar -xzf /tmp/trino-server.tar.gz -C /opt \
    && mv /opt/trino-server-${TRINO_VERSION} /opt/trino \
    && rm /tmp/trino-server.tar.gz

# --- Install Trino CLI ---
RUN curl -fSL "https://repo1.maven.org/maven2/io/trino/trino-cli/${TRINO_VERSION}/trino-cli-${TRINO_VERSION}-executable.jar" \
        -o /usr/local/bin/trino \
    && chmod +x /usr/local/bin/trino

# --- Install PostgreSQL JDBC driver into Trino Iceberg plugin ---
RUN curl -fSL "https://repo1.maven.org/maven2/org/postgresql/postgresql/${PG_JDBC_VERSION}/postgresql-${PG_JDBC_VERSION}.jar" \
        -o /opt/trino/plugin/iceberg/postgresql-${PG_JDBC_VERSION}.jar

# --- Create trino user and data directories ---
RUN useradd -r -s /bin/false trino \
    && mkdir -p /data/postgres /data/seaweedfs /data/trino /etc/trino/catalog /etc/seaweedfs \
    && chown postgres:postgres /data/postgres \
    && chown trino:trino /data/trino /etc/trino

# --- Symlink Trino etc ---
RUN ln -sf /etc/trino /opt/trino/etc

# --- Copy Trino config templates ---
COPY trino/ /opt/trino-templates/

# --- Copy supervisord config ---
COPY supervisord.conf /etc/supervisord.conf

# --- Copy entrypoint ---
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080 8333 5432

VOLUME ["/data/postgres", "/data/seaweedfs", "/data/trino"]

ENTRYPOINT ["/entrypoint.sh"]
