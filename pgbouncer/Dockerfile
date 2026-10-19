FROM alpine:3.21
RUN apk add --no-cache pgbouncer openssl bash \
    && pgbouncer --version
COPY entrypoint.sh /usr/local/bin/pgbouncer-entrypoint
RUN chmod 0755 /usr/local/bin/pgbouncer-entrypoint
USER pgbouncer
EXPOSE 6432
ENTRYPOINT ["/usr/local/bin/pgbouncer-entrypoint"]
