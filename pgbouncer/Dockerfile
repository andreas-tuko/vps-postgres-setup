FROM alpine:3.21
RUN set -eux; \
    apk add --no-cache pgbouncer openssl bash; \
    getent group pgbouncer >/dev/null || addgroup -S pgbouncer; \
    getent passwd pgbouncer >/dev/null || adduser -S -D -H -G pgbouncer -s /sbin/nologin pgbouncer; \
    pgbouncer --version
COPY entrypoint.sh /usr/local/bin/pgbouncer-entrypoint
RUN chmod 0755 /usr/local/bin/pgbouncer-entrypoint
USER pgbouncer
EXPOSE 6432
ENTRYPOINT ["/usr/local/bin/pgbouncer-entrypoint"]
