# Deploy Django

Deploy aplikasi Django ke Wokku dengan Postgres, migration otomatis, dan file
statis disajikan via WhiteNoise.

## Prasyarat

- [Akun Wokku](/docs/getting-started/sign-up) dan [server yang terhubung](/docs/getting-started/connect-server)
- [SSH key terdaftar](/docs/apps/ssh-keys) untuk `git push`
- Proyek Django dengan `requirements.txt`

## 1. Buat aplikasi

:::tabs
::web-ui
**Apps → New App** → server, nama `my-django-app`, ukuran box, **Create**.

::cli
```bash
wokku apps:create my-django-app --server my-server
```
:::

## 2. Siapkan aplikasi Django-mu

Python buildpack mendeteksi `requirements.txt`. Pastikan ini ada:

```text
# requirements.txt
django
gunicorn
psycopg[binary]
whitenoise
dj-database-url
```

Tambahkan `Procfile`:

```procfile
web: gunicorn myproject.wsgi --log-file -
release: python manage.py migrate --noinput
```

Di `settings.py`, baca database + host dari environment dan biarkan WhiteNoise
menyajikan file statis:

```python
import dj_database_url, os
DATABASES = {"default": dj_database_url.config(conn_max_age=600)}
ALLOWED_HOSTS = os.environ.get("ALLOWED_HOSTS", "").split(",")
MIDDLEWARE = ["whitenoise.middleware.WhiteNoiseMiddleware", *MIDDLEWARE]
STATIC_ROOT = BASE_DIR / "staticfiles"
```

:::callout note
`collectstatic` berjalan otomatis saat build Python. Proses `release:` menerapkan
migration setelah build, sebelum traffic dialihkan.
:::

## 3. Set environment variable

:::tabs
::web-ui
Aplikasi → **Config**:

| Key | Value |
|---|---|
| `SECRET_KEY` | string acak panjang |
| `DJANGO_SETTINGS_MODULE` | `myproject.settings` |
| `ALLOWED_HOSTS` | `my-django-app.wokku.app` |
| `DEBUG` | `False` |

::cli
```bash
wokku config:set my-django-app \
  SECRET_KEY="$(python -c 'import secrets;print(secrets.token_urlsafe(50))')" \
  DJANGO_SETTINGS_MODULE=myproject.settings \
  ALLOWED_HOSTS=my-django-app.wokku.app DEBUG=False
```
:::

## 4. Tambahkan database

```bash
wokku addons:create postgres my-django-app
```

Wokku menyuntikkan `DATABASE_URL`; `dj-database-url` membacanya otomatis. Lihat
[Buat & Link Database](/docs/databases/create-link).

## 5. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-django-app
git push wokku main
```

::github
Hubungkan di **Apps → Connect GitHub** untuk push-to-deploy —
lihat [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-django-app
git push wokku main
```
:::

Live di `https://my-django-app.wokku.app`.

## 6. Domain kustom

[Domain Kustom](/docs/domains-ssl/custom-domains) — ingat tambahkan hostname baru
ke `ALLOWED_HOSTS` lalu deploy ulang.

## Troubleshooting

- **`DisallowedHost`** — tambahkan domainmu ke `ALLOWED_HOSTS` lalu deploy ulang.
- **CSS/JS 404 di production** — pastikan middleware WhiteNoise + `STATIC_ROOT`; `collectstatic` harus sukses di build log.
- **Migration tidak jalan** — cek baris `release:` dan deploy logs.

## Langkah berikutnya

- [Background worker (Celery)](/docs/scaling/bundled-processes)
- [Logs](/docs/apps/logs) · [Kesiapan Production](/docs/apps/best-practices)
