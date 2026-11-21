# MariaDB 11.8 LTS: WriteFreely's database. Official image, pinned by version and digest.
# Bump both together and add a CHANGELOG.md entry.
FROM mariadb:11.8.9@sha256:e1d5495f445654134f226f55a41ce0da227116f6f27f283101f405c794d841fc

# Railway settings: data directory inside the volume, small memory footprint, no DNS lookups.
COPY railway.cnf /etc/mysql/conf.d/zz-railway.cnf

# Database and user that WriteFreely connects with. The passwords come from the template's
# generated secrets (MARIADB_PASSWORD, MARIADB_ROOT_PASSWORD).
# MARIADB_AUTO_UPGRADE runs mariadb-upgrade when a newer image starts on an older data directory.
ENV MARIADB_DATABASE=writefreely \
    MARIADB_USER=writefreely \
    MARIADB_AUTO_UPGRADE=1

EXPOSE 3306
CMD ["mariadbd"]
