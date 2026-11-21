# WriteFreely 0.17.3: the official image from the WriteFreely project (GitHub Container Registry),
# pinned by version and digest. Bump the tag and digest together and add a CHANGELOG.md entry.
FROM ghcr.io/writefreely/writefreely:v0.17.3@sha256:cf82aaddd1de1618c3a6c6804810b88d7799977f763671ac877b67e47502c784

# mariadb-client: the start script waits for the database, checks whether it is set up yet,
# and holds a database lock while it sets it up, so two deploys never initialise it at once.
RUN apk add --no-cache mariadb-client

COPY railway-start.sh /usr/local/bin/railway-start.sh
COPY railway-init.sh /usr/local/bin/railway-init.sh
RUN chmod 755 /usr/local/bin/railway-start.sh /usr/local/bin/railway-init.sh

# Fixed settings (override any of them with a service variable).
# The config file, the encryption keys and the uploaded pages all live on the volume at /data.
ENV PORT=8080 \
    WRITEFREELY_DB_PORT=3306 \
    WRITEFREELY_DB_NAME=writefreely \
    WRITEFREELY_DB_USER=writefreely \
    WRITEFREELY_SITE_NAME=WriteFreely \
    GOMEMLIMIT=384MiB

WORKDIR /data
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/railway-start.sh"]
