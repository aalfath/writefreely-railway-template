[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/writefreely-2?utm_medium=integration&utm_source=button&utm_campaign=writefreely)

# Deploy and Host WriteFreely on Railway

WriteFreely is open-source software for minimalist, federated blogging. Writers get a clean Markdown editor, one or more blogs per account, and posts that people can follow from Mastodon and other ActivityPub servers. This template deploys WriteFreely 0.17.3, the latest stable release, as a multi-user instance with your admin account already created.

## About Hosting WriteFreely

WriteFreely is a single Go program that keeps its posts and accounts in a MySQL-compatible database and its config file and encryption keys on disk. This template runs two services on Railway's private network: WriteFreely (the public web service, with config and keys on a volume) and MariaDB 11.8 LTS (on its own volume). On the first boot the start script writes the config, creates the tables and keys, and creates your admin account from generated credentials, so nobody else can claim the instance. Later boots run database migrations. The public URL is wired in automatically. Both services fit in 0.5 GB of RAM.

## Common Use Cases

* A personal blog with a distraction-free editor that Mastodon users can follow
* A small writing community, team journal or class blog with invite-only accounts
* An internal knowledge or announcements blog with private or members-only posts

## Dependencies for WriteFreely Hosting

* MariaDB 11.8 (bundled, own volume)

### Deployment Dependencies

* [WriteFreely documentation](https://writefreely.org/docs)
* [WriteFreely 0.17.3 release](https://github.com/writefreely/writefreely/releases/tag/v0.17.3)
* [Official container image](https://github.com/writefreely/writefreely/pkgs/container/writefreely)
* [Template source](https://github.com/aalfath/writefreely-railway-template)

### Implementation Details

**After you deploy:** open the WriteFreely service's variables and copy `WRITEFREELY_ADMIN_PASSWORD` (generated) and `WRITEFREELY_ADMIN_USER` (default `owner`). Open the public URL, choose "Log in" and sign in. Your first blog has the admin's username. Then open Admin → Settings to set the site name and description, and choose whether people may sign up: registration is closed by default and only the admin can send invites. Change your password under your account's settings; the variable is only used to create the account on the first boot.

**Services:**

* **WriteFreely**: port 8080, health check `/api/nodeinfo` (answers without login, also when the instance is set to private). The volume at `/data` holds `config.ini`, the encryption keys (`/data/keys`) and a first-boot marker. Settings you save in the admin panel are kept across redeploys; only the port, database connection and public URL are refreshed from variables on each start.
* **MariaDB**: WriteFreely's database (posts, accounts, blogs), data on the volume at `/var/lib/mysql`. Tuned to fit 0.5 GB of RAM.

**Options:** email (password reset, newsletters) needs SMTP or Mailgun settings in the `[email]` section of `/data/config.ini`; see the [config reference](https://writefreely.org/docs/latest/admin/config). Single-user mode and other settings are in the admin panel. To use your own domain, add it to the WriteFreely service in Railway and set `WRITEFREELY_HOST` to `https://YOUR-DOMAIN` before you start federating, because ActivityPub followers are tied to that address.

**Updates:** both services build from this template's GitHub repo, which pins each image by version and digest. When we release a new version, Railway shows an update in your project; read [CHANGELOG.md](https://github.com/aalfath/writefreely-railway-template/blob/main/CHANGELOG.md) first, then apply it. WriteFreely runs its database migrations on the next start.

## Why Deploy WriteFreely on Railway?

<!-- Recommended: Keep this section as shown below -->
Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying WriteFreely on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
<!-- End recommended section -->

## Template details

| Service | Built from | Volume |
|---|---|---|
| WriteFreely | [`app/Dockerfile`](app/Dockerfile): `ghcr.io/writefreely/writefreely:v0.17.3@sha256:cf82aaddd1de1618c3a6c6804810b88d7799977f763671ac877b67e47502c784` plus [`railway-start.sh`](app/railway-start.sh) | `/data` |
| MariaDB | [`mariadb/Dockerfile`](mariadb/Dockerfile): `mariadb:11.8.9@sha256:e1d5495f445654134f226f55a41ce0da227116f6f27f283101f405c794d841fc` plus [`railway.cnf`](mariadb/railway.cnf) | `/var/lib/mysql` |

### Variables

| Service | Variable | Value |
|---|---|---|
| WriteFreely | `WRITEFREELY_HOST` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` (change it if you add a custom domain) |
| WriteFreely | `WRITEFREELY_DB_HOST`, `WRITEFREELY_DB_PASSWORD` | references to the MariaDB service |
| WriteFreely | `WRITEFREELY_ADMIN_USER` | `owner` (used once, on the first boot) |
| WriteFreely | `WRITEFREELY_ADMIN_PASSWORD` | generated (used once, on the first boot) |
| WriteFreely | `PORT` | `8080` |
| MariaDB | `MARIADB_PASSWORD`, `MARIADB_ROOT_PASSWORD` | generated |
| MariaDB | `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `60` (clean shutdown on redeploy) |

Fixed settings (database name and user `writefreely`, `GOMAXPROCS=1`, `GOMEMLIMIT=384MiB`) are set in the Dockerfiles; override any of them with a service variable.

### What the wrapper does

`app/railway-start.sh` gives the volume to the image's unprivileged `daemon` user and drops to it, writes `/data/config.ini` on the first boot (multi-user, closed registration, admin-only invites, federation on), refreshes the port, database and public URL on every boot, waits for MariaDB, then on the first boot runs `writefreely db init`, `keys generate` and `user create --admin`, and on later boots `db migrate`. It runs WriteFreely in the foreground; if WriteFreely stops on its own, the container exits non-zero so Railway restarts it.

### Updating this template

Bump the tag and digest in the Dockerfile, test on a scratch Railway project, add a `CHANGELOG.md` entry (breaking changes first) and merge to `main`. Deployers then see the update in Railway.
