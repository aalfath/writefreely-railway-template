#!/bin/sh
# Railway start script for WriteFreely.
# 1. Writes /data/config.ini on the first boot (settings you change later in the admin
#    panel are kept); on every boot it only refreshes the port, the database connection
#    and the public URL from the service variables.
# 2. Waits for MariaDB, then (under a database lock) creates the tables, runs migrations,
#    generates the encryption keys and creates the admin account on the first boot.
# 3. Runs WriteFreely in the foreground. If it stops, the container exits non-zero so
#    Railway restarts it.
set -eu

DATA=/data
CFG="$DATA/config.ini"
: "${PORT:=8080}"
: "${WRITEFREELY_DB_HOST:?WRITEFREELY_DB_HOST is not set (it should reference the MariaDB service)}"
: "${WRITEFREELY_DB_PASSWORD:?WRITEFREELY_DB_PASSWORD is not set (it should reference the MariaDB service)}"
: "${WRITEFREELY_HOST:?WRITEFREELY_HOST is not set (the public URL, for example https://YOUR-DOMAIN)}"
case "$WRITEFREELY_HOST" in http://*|https://*) ;; *) WRITEFREELY_HOST="https://$WRITEFREELY_HOST" ;; esac
WRITEFREELY_HOST="${WRITEFREELY_HOST%/}"
export WRITEFREELY_HOST

mkdir -p "$DATA"
cd "$DATA"

if [ ! -s "$CFG" ]; then
  echo "railway: writing $CFG (first boot)"
  cat > "$CFG.tmp" <<CFGEOF
[server]
hidden_host          =
port                 = $PORT
bind                 = 0.0.0.0
tls_cert_path        =
tls_key_path         =
autocert             = false
templates_parent_dir = /usr/share/writefreely
static_parent_dir    = /usr/share/writefreely
pages_parent_dir     = /usr/share/writefreely
keys_parent_dir      = $DATA
hash_seed            =
gopher_port          = 0

[database]
type     = mysql
filename =
username = $WRITEFREELY_DB_USER
password = $WRITEFREELY_DB_PASSWORD
database = $WRITEFREELY_DB_NAME
host     = $WRITEFREELY_DB_HOST
port     = $WRITEFREELY_DB_PORT
tls      = false

[app]
site_name             = $WRITEFREELY_SITE_NAME
site_description      =
host                  = $WRITEFREELY_HOST
theme                 = write
editor                =
disable_js            = false
webfonts              = true
landing               =
simple_nav            = false
wf_modesty            = false
chorus                = false
forest                = false
disable_drafts        = false
single_user           = false
open_registration     = false
open_deletion         = false
min_username_len      = 3
max_blogs             = 5
federation            = true
public_stats          = false
monetization          = false
notes_only            = false
private               = false
local_timeline        = false
user_invites          = admin
default_visibility    = public
update_checks         = false
disable_password_auth = false
CFGEOF
  mv "$CFG.tmp" "$CFG"
fi

# Set one key inside one [section] of the INI file, adding it if it is missing.
ini_set() {
  awk -v sec="$1" -v key="$2" -v val="$3" '
    function flush() { if (insec && !done) { print key " = " val; done = 1 } }
    /^\[/ { flush(); insec = ($0 == "[" sec "]"); print; next }
    insec && $0 ~ "^[ \t]*" key "[ \t]*=" { print key " = " val; done = 1; next }
    { print }
    END { flush() }
  ' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
}
ini_set server port "$PORT"
ini_set server bind 0.0.0.0
ini_set server keys_parent_dir "$DATA"
ini_set server templates_parent_dir /usr/share/writefreely
ini_set server static_parent_dir /usr/share/writefreely
ini_set server pages_parent_dir /usr/share/writefreely
ini_set database type mysql
ini_set database host "$WRITEFREELY_DB_HOST"
ini_set database port "$WRITEFREELY_DB_PORT"
ini_set database database "$WRITEFREELY_DB_NAME"
ini_set database username "$WRITEFREELY_DB_USER"
ini_set database password "$WRITEFREELY_DB_PASSWORD"
ini_set app host "$WRITEFREELY_HOST"
chmod 600 "$CFG"

# Credentials for the mariadb client, kept out of the process list.
MYCNF=/tmp/railway-my.cnf
umask 077
cat > "$MYCNF" <<MYEOF
[client]
host=$WRITEFREELY_DB_HOST
port=$WRITEFREELY_DB_PORT
user=$WRITEFREELY_DB_USER
password=$WRITEFREELY_DB_PASSWORD
database=$WRITEFREELY_DB_NAME
connect-timeout=5
skip-ssl
MYEOF
umask 022
export MYCNF

echo "railway: waiting for MariaDB at $WRITEFREELY_DB_HOST:$WRITEFREELY_DB_PORT"
i=0
until mariadb --defaults-file="$MYCNF" -N -e 'SELECT 1' >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -ge 90 ]; then
    echo "railway: MariaDB did not answer within 3 minutes" >&2
    mariadb --defaults-file="$MYCNF" -N -e 'SELECT 1' >&2 || true
    exit 1
  fi
  sleep 2
done

# First-boot setup and migrations, under a MariaDB named lock so that two overlapping
# deploys never set the database up at the same time. railway-init.sh writes its exit
# status to a file because the client's "system" command does not pass it back.
rm -f /tmp/railway-init.status
mariadb --defaults-file="$MYCNF" -N -e "
  SELECT IF(GET_LOCK('writefreely_railway_init', 600) = 1, 'railway: init lock taken', 'railway: init lock timed out');
  system /usr/local/bin/railway-init.sh
  DO RELEASE_LOCK('writefreely_railway_init');"
status=$(cat /tmp/railway-init.status 2>/dev/null || echo 1)
if [ "$status" != 0 ]; then
  echo "railway: first-boot setup failed (status $status)" >&2
  exit 1
fi

echo "railway: starting WriteFreely on port $PORT"
# Run WriteFreely as a child so a redeploy's SIGTERM reaches it, and so an unexpected
# stop (even with exit status 0) ends the container with a non-zero status: Railway's
# ON_FAILURE restart policy then starts it again.
stopping=0
/usr/bin/writefreely -c "$CFG" &
pid=$!
trap 'stopping=1; kill -TERM "$pid" 2>/dev/null' TERM INT
code=0
wait "$pid" || code=$?
if [ "$stopping" = 1 ]; then
  wait "$pid" 2>/dev/null || true
  echo "railway: stopped on request"
  exit 0
fi
echo "railway: WriteFreely stopped unexpectedly (exit $code)" >&2
[ "$code" -ne 0 ] && exit "$code"
exit 1
