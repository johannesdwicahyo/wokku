---
title: Django
summary: Jalankan app Django di Wokku dengan Gunicorn, Postgres, dan WhiteNoise untuk file statis.
last_updated: 2026-11-07
---

Tambahkan Gunicorn dan WhiteNoise, baca settings dari environment, push, lalu jalankan migration. Mau repo yang sudah jalan dulu? Deploy starter `django` dari [Templates](/docs/templates/browse).

## Dependency

```text
# requirements.txt
django
gunicorn
psycopg[binary]
whitenoise
dj-database-url
```

## Settings

```python
# settings.py
import os
import dj_database_url

SECRET_KEY = os.environ["SECRET_KEY"]
DEBUG = os.environ.get("DEBUG") == "True"
ALLOWED_HOSTS = os.environ.get("ALLOWED_HOSTS", "").split(",")
CSRF_TRUSTED_ORIGINS = [f"https://{h}" for h in ALLOWED_HOSTS if h]
DATABASES = {"default": dj_database_url.config(conn_max_age=600)}

MIDDLEWARE.insert(1, "whitenoise.middleware.WhiteNoiseMiddleware")  # right after SecurityMiddleware
STATIC_ROOT = BASE_DIR / "staticfiles"
```

## Perintah start

Kumpulkan file statis saat boot, lalu jalankan Gunicorn. Baris Procfile yang berisi `&&` berjalan tanpa shell, jadi taruh kedua langkah di sebuah script:

```bash
#!/usr/bin/env bash
# bin/start  (chmod +x bin/start)
set -e
python manage.py collectstatic --noinput
exec gunicorn myproject.wsgi --bind 0.0.0.0:$PORT --log-file -
```

```procfile
web: bin/start
```

## Config dan database

```bash
wokku apps:create my-app --shared postgres
wokku config:set my-app \
  SECRET_KEY="$(python -c 'import secrets; print(secrets.token_urlsafe(50))')" \
  DJANGO_SETTINGS_MODULE=myproject.settings \
  ALLOWED_HOSTS=my-app.wokku.app
```

Add-on Postgres mengisi `DATABASE_URL`, yang dibaca oleh `dj-database-url`. Lihat [Membuat & Menautkan Database](/docs/databases/create-link).

## Deploy dan migrate

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
wokku run my-app -- python manage.py migrate --noinput
```

Jalankan perintah migrate setiap kali deploy yang menambahkan migration. Live di `https://my-app.wokku.app`. Baru pertama deploy? Lihat [Quickstart](/docs/getting-started/first-deploy).

## Domain kustom

Setelah kamu menambahkan [domain kustom](/docs/domains-ssl/custom-domains), tambahkan domain itu ke `ALLOWED_HOSTS` (dipisah koma) lalu restart: `wokku ps:restart my-app`.

## Troubleshooting

- **Error `DisallowedHost` atau CSRF** — hostname belum ada di `ALLOWED_HOSTS`.
- **CSS/JS 404** — cek middleware WhiteNoise dan `STATIC_ROOT`, dan pastikan `collectstatic` berhasil di [log](/docs/monitoring/logs).
- **Celery** — tambahkan `worker: celery -A myproject worker` ke Procfile lalu scale. Lihat [Background Worker](/docs/guides/background-workers).
