# PostgreSQL 17 + pgBackRest (WAL archiving / PITR) + pgaudit, scheduled backups via supercronic.
FROM postgres:17-bookworm

ARG TARGETARCH
ARG SUPERCRONIC_VERSION=v0.2.33
ARG SUPERCRONIC_SHA1_AMD64=71b0d58cc53f6bd72cf2f293e09e294b79c666d8
ARG SUPERCRONIC_SHA1_ARM64=e0f0c06ebc5627e43b25475711e694450489ab00

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl openssl pgbackrest postgresql-17-pgaudit; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "${arch}" in \
        amd64) sha="${SUPERCRONIC_SHA1_AMD64}" ;; \
        arm64) sha="${SUPERCRONIC_SHA1_ARM64}" ;; \
        *) echo "unsupported arch: ${arch}" >&2; exit 1 ;; \
    esac; \
    curl -fsSLo /usr/local/bin/supercronic \
        "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-${arch}"; \
    echo "${sha}  /usr/local/bin/supercronic" | sha1sum -c -; \
    chmod 0755 /usr/local/bin/supercronic; \
    apt-get purge -y --auto-remove curl; \
    rm -rf /var/lib/apt/lists/*; \
    install -d -m 0750 -o postgres -g postgres \
        /etc/postgresql /etc/postgresql/conf.d /etc/pgbackrest \
        /var/lib/pgbackrest /var/log/pgbackrest /var/spool/pgbackrest

COPY postgresql.conf /etc/postgresql/postgresql.conf
COPY bin/ /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/pg-entrypoint
COPY initdb.d/ /docker-entrypoint-initdb.d/
RUN chmod 0755 /usr/local/bin/* /docker-entrypoint-initdb.d/*.sh \
    && chown -R postgres:postgres /etc/postgresql

ENV TZ=UTC \
    POSTGRES_INITDB_ARGS="--data-checksums" \
    PG_ROLE=primary

ENTRYPOINT ["/usr/local/bin/pg-entrypoint"]
CMD ["postgres"]
