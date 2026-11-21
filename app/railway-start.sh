#!/bin/sh
# Railway start script for WriteFreely.
# 1. Writes /data/config.ini on the first boot (settings you change later in the admin
#    panel are kept); on every boot it only refreshes the port, the database connection
#    and the public URL from the service variables.
# 2. Waits for MariaDB. On the first boot it creates the tables, the encryption keys and
#    the admin account; on later boots it runs the database migrations.
# 3. Runs WriteFreely. If it stops on its own, the container exits non-zero so Railway's
#    restart policy starts it again.
set -eu

DATA=/data
# Start as root only to hand the volume to the unprivileged "daemon" user, then re-run as daemon.
if [ "$(id -u)" = 0 ]; then
  mkdir -p "$DATA"
  chown -R daemon:daemon "$DATA"
  exec su -p -s /bin/sh daemon -c "exec $0"
fi
export HOME="$DATA"

: "${WRITEFREELY_BIN:=/go/cmd/writefreely/writefreely}"
: "${WRITEFREELY_ASSETS:=/go}"
: "${PORT:=8080}"
: "${WRITEFREELY_DB_PORT:=3306}"
: "${WRITEFREELY_DB_NAME:=writefreely}"
: "${WRITEFREELY_DB_USER:=writefreely}"
: "${WRITEFREELY_SITE_NAME:=WriteFreely}"
: "${WRITEFREELY_DB_HOST:?WRITEFREELY_DB_HOST is not set (it should reference the MariaDB service)}"
: "${WRITEFREELY_DB_PASSWORD:?WRITEFREELY_DB_PASSWORD is not set (it should reference the MariaDB service)}"
: "${WRITEFREELY_HOST:?WRITEFREELY_HOST is not set (the public URL, for example https://YOUR-DOMAIN)}"
case "$WRITEFREELY_HOST" in http://*|https://*) ;; *) WRITEFREELY_HOST="https://$WRITEFREELY_HOST" ;; esac
WRITEFREELY_HOST="${WRITEFREELY_HOST%/}"

CFG="$DATA/config.ini"
MARKER="$DATA/.railway-initialised"
WF="$WRITEFREELY_BIN -c $CFG"
cd "$DATA"
umask 077

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
templates_parent_dir = $WRITEFREELY_ASSETS
static_parent_dir    = $WRITEFREELY_ASSETS
pages_parent_dir     = $WRITEFREELY_ASSETS
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
ini_set server templates_parent_dir "$WRITEFREELY_ASSETS"
ini_set server static_parent_dir "$WRITEFREELY_ASSETS"
ini_set server pages_parent_dir "$WRITEFREELY_ASSETS"
ini_set database type mysql
ini_set database host "$WRITEFREELY_DB_HOST"
ini_set database port "$WRITEFREELY_DB_PORT"
ini_set database database "$WRITEFREELY_DB_NAME"
ini_set database username "$WRITEFREELY_DB_USER"
ini_set database password "$WRITEFREELY_DB_PASSWORD"
ini_set app host "$WRITEFREELY_HOST"

echo "railway: waiting for MariaDB at $WRITEFREELY_DB_HOST:$WRITEFREELY_DB_PORT"
i=0
# MariaDB sends its greeting as soon as a client connects.
until [ "$(timeout 5 nc -w 3 "$WRITEFREELY_DB_HOST" "$WRITEFREELY_DB_PORT" </dev/null 2>/dev/null | head -c 4 | wc -c)" -gt 0 ]; do
  i=$((i + 1))
  if [ "$i" -ge 60 ]; then
    echo "railway: MariaDB did not answer within 5 minutes" >&2
    exit 1
  fi
  sleep 3
done
# MariaDB's first boot restarts it once after creating the database; give it a moment.
[ -f "$MARKER" ] || sleep 10

if [ ! -s "$DATA/keys/email.aes256" ] || [ ! -s "$DATA/keys/cookies_auth.aes256" ] || \
   [ ! -s "$DATA/keys/cookies_enc.aes256" ] || [ ! -s "$DATA/keys/csrf.aes256" ]; then
  echo "railway: generating encryption keys in $DATA/keys"
  mkdir -p "$DATA/keys"
  $WF keys generate
fi

if [ ! -f "$MARKER" ]; then
  # Safe on a database that already has the tables: existing tables are left as they are.
  echo "railway: first boot: creating WriteFreely's tables"
  $WF db init
  if [ -z "${WRITEFREELY_ADMIN_USER:-}" ] || [ -z "${WRITEFREELY_ADMIN_PASSWORD:-}" ]; then
    echo "railway: WRITEFREELY_ADMIN_USER and WRITEFREELY_ADMIN_PASSWORD must be set to create the admin" >&2
    exit 1
  fi
  echo "railway: creating the admin account '$WRITEFREELY_ADMIN_USER'"
  if out=$($WF user create --admin "$WRITEFREELY_ADMIN_USER:$WRITEFREELY_ADMIN_PASSWORD" 2>&1); then
    echo "railway: admin account created"
  else
    case "$out" in
      *"Admin user already exists"*) echo "railway: an admin account already exists; keeping it" ;;
      *) printf '%s\n' "$out" | sed "s/$WRITEFREELY_ADMIN_PASSWORD/***/g" >&2; exit 1 ;;
    esac
  fi
  date -u +%FT%TZ > "$MARKER"
else
  $WF db migrate
fi

echo "railway: starting WriteFreely on port $PORT"
# Run WriteFreely as a child so a redeploy's SIGTERM reaches it, and so an unexpected
# stop (even with exit status 0) ends the container with a non-zero status.
stopping=0
$WF &
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
