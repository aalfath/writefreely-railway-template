# WriteFreely 0.17.3: the official image from the WriteFreely project (GitHub Container Registry),
# pinned by version and digest. Bump the tag and digest together and add a CHANGELOG.md entry.
FROM ghcr.io/writefreely/writefreely:v0.17.3@sha256:cf82aaddd1de1618c3a6c6804810b88d7799977f763671ac877b67e47502c784

# The image runs as the unprivileged user "daemon". The start script starts as root only to
# give the Railway volume (/data, mounted root-owned) to daemon, then drops to daemon.
# It only uses the image's own tools (busybox), so the build downloads nothing else.
USER root
COPY railway-start.sh /usr/local/bin/railway-start.sh
RUN chmod 755 /usr/local/bin/railway-start.sh

# Fixed settings (override any of them with a service variable).
# The config file, the encryption keys and the first-boot marker live on the volume at /data.
ENV WRITEFREELY_BIN=/go/cmd/writefreely/writefreely \
    WRITEFREELY_ASSETS=/go \
    PORT=8080 \
    WRITEFREELY_DB_PORT=3306 \
    WRITEFREELY_DB_NAME=writefreely \
    WRITEFREELY_DB_USER=writefreely \
    WRITEFREELY_SITE_NAME=WriteFreely \
    GOMAXPROCS=1 \
    GOMEMLIMIT=384MiB

WORKDIR /data
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/railway-start.sh"]
