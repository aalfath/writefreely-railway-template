#!/bin/sh
# Called by railway-start.sh while it holds the MariaDB lock 'writefreely_railway_init'.
set -u
STATUS=/tmp/railway-init.status
echo 1 > "$STATUS"
cd /data
CFG=/data/config.ini
WF="/usr/bin/writefreely -c $CFG"
q() { mariadb --defaults-file="$MYCNF" -N -e "$1"; }

run() {
  tables=$(q "SHOW TABLES LIKE 'users'") || return 1
  if [ -z "$tables" ]; then
    echo "railway: empty database, creating WriteFreely's tables"
    $WF db init || return 1
  else
    $WF db migrate || return 1
  fi

  if [ ! -s /data/keys/email.aes256 ] || [ ! -s /data/keys/cookies_auth.aes256 ] || \
     [ ! -s /data/keys/cookies_enc.aes256 ] || [ ! -s /data/keys/csrf.aes256 ]; then
    echo "railway: generating encryption keys in /data/keys"
    mkdir -p /data/keys
    $WF keys generate || return 1
  fi

  admins=$(q "SELECT COUNT(*) FROM users WHERE id = 1") || return 1
  if [ "$admins" = 0 ]; then
    if [ -z "${WRITEFREELY_ADMIN_USER:-}" ] || [ -z "${WRITEFREELY_ADMIN_PASSWORD:-}" ]; then
      echo "railway: WRITEFREELY_ADMIN_USER and WRITEFREELY_ADMIN_PASSWORD must be set to create the admin" >&2
      return 1
    fi
    echo "railway: creating the admin account '$WRITEFREELY_ADMIN_USER'"
    $WF user create --admin "$WRITEFREELY_ADMIN_USER:$WRITEFREELY_ADMIN_PASSWORD" || return 1
  fi
  return 0
}

if run; then echo 0 > "$STATUS"; else echo 1 > "$STATUS"; fi
