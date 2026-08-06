# Deploy Flask

Deploy aplikasi Flask ke Wokku dengan Gunicorn dan Postgres.

## Prasyarat

- [Akun Wokku](/docs/getting-started/sign-up) dan [server yang terhubung](/docs/getting-started/connect-server)
- [SSH key terdaftar](/docs/apps/ssh-keys) untuk `git push`
- Aplikasi Flask dengan `requirements.txt`

## 1. Buat aplikasi

:::tabs
::web-ui
**Apps → New App** → server, nama `my-flask-app`, ukuran box, **Create**.

::cli
```bash
wokku apps:create my-flask-app --server my-server
```
:::

## 2. Siapkan aplikasi Flask-mu

Sertakan `gunicorn` di `requirements.txt`:

```text
flask
gunicorn
psycopg[binary]
```

Tambahkan `Procfile` (asumsi objek app-mu bernama `app` di `app.py`):

```procfile
web: gunicorn app:app
```

Jika kamu pakai Flask-Migrate, tambahkan langkah release:

```procfile
release: flask db upgrade
```

## 3. Set environment variable

:::tabs
::web-ui
Aplikasi → **Config** → tambahkan `SECRET_KEY` dan config yang dibaca dari env.

::cli
```bash
wokku config:set my-flask-app SECRET_KEY="$(python -c 'import secrets;print(secrets.token_urlsafe(32))')"
```
:::

## 4. Tambahkan database (opsional)

```bash
wokku addons:create postgres my-flask-app
```

Baca `os.environ["DATABASE_URL"]` di config SQLAlchemy-mu. Lihat
[Buat & Link Database](/docs/databases/create-link).

## 5. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-flask-app
git push wokku main
```

::github
Hubungkan di **Apps → Connect GitHub** untuk push-to-deploy —
lihat [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-flask-app
git push wokku main
```
:::

Live di `https://my-flask-app.wokku.app`.

## Domain kustom

[Domain Kustom](/docs/domains-ssl/custom-domains) — SSL otomatis.

## Troubleshooting

- **`ModuleNotFoundError`** — pastikan dependency ada di `requirements.txt`.
- **Objek app tidak ketemu** — cocokkan `gunicorn app:app` dengan nama modul & variabelmu.
- **Koneksi DB ditolak** — pastikan add-on Postgres ter-link dan `DATABASE_URL` ter-set.

## Langkah berikutnya

- [Background worker](/docs/scaling/bundled-processes) · [Logs](/docs/apps/logs) · [Kesiapan Production](/docs/apps/best-practices)
