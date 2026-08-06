# Deploy FastAPI

Deploy aplikasi FastAPI ke Wokku dengan worker Uvicorn dan Postgres.

## Prasyarat

- [Akun Wokku](/docs/getting-started/sign-up) dan [server yang terhubung](/docs/getting-started/connect-server)
- [SSH key terdaftar](/docs/apps/ssh-keys) untuk `git push`
- Aplikasi FastAPI dengan `requirements.txt`

## 1. Buat aplikasi

:::tabs
::web-ui
**Apps → New App** → server, nama `my-fastapi-app`, ukuran box, **Create**.

::cli
```bash
wokku apps:create my-fastapi-app --server my-server
```
:::

## 2. Siapkan aplikasi FastAPI-mu

```text
# requirements.txt
fastapi
uvicorn[standard]
gunicorn
psycopg[binary]
```

Tambahkan `Procfile` (asumsi `app` adalah instance FastAPI di `main.py`):

```procfile
web: gunicorn main:app -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:$PORT
```

:::callout note
Gunicorn + worker Uvicorn memberimu banyak proses untuk production. Untuk satu
worker, `uvicorn main:app --host 0.0.0.0 --port $PORT` juga bisa.
:::

## 3. Set environment variable

:::tabs
::web-ui
Aplikasi → **Config** → tambahkan secret/config yang dibaca aplikasimu dari env.

::cli
```bash
wokku config:set my-fastapi-app ENV=production
```
:::

## 4. Tambahkan database (opsional)

```bash
wokku addons:create postgres my-fastapi-app
```

Baca `os.environ["DATABASE_URL"]` (SQLAlchemy/SQLModel/asyncpg). Lihat
[Buat & Link Database](/docs/databases/create-link).

## 5. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-fastapi-app
git push wokku main
```

::github
Hubungkan di **Apps → Connect GitHub** untuk push-to-deploy —
lihat [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-fastapi-app
git push wokku main
```
:::

Live di `https://my-fastapi-app.wokku.app` — dokumentasi di `/docs` (Swagger UI).

## Domain kustom

[Domain Kustom](/docs/domains-ssl/custom-domains) — SSL otomatis.

## Troubleshooting

- **502 / tidak ada respons** — pastikan bind pakai `$PORT`, bukan port tetap.
- **`UvicornWorker` tidak ketemu** — tambahkan `uvicorn[standard]` ke `requirements.txt`.
- **Driver DB async** — pakai `asyncpg` (bukan `psycopg`) untuk SQLAlchemy async.

## Langkah berikutnya

- [Logs](/docs/apps/logs) · [Kesiapan Production](/docs/apps/best-practices)
