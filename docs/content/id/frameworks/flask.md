---
title: Flask
summary: Jalankan app Flask di Wokku dengan Gunicorn.
last_updated: 2026-11-07
---

Tambahkan Gunicorn, push, dan app-mu langsung live. Mau repo yang sudah jalan dulu? Deploy starter `flask` dari [Templates](/docs/templates/browse).

## Dependency

```text
# requirements.txt
flask
gunicorn
```

## Perintah start

Dengan asumsi objek app-mu bernama `app` di `app.py`:

```procfile
web: gunicorn app:app --bind 0.0.0.0:$PORT
```

## Config dan database

```bash
wokku apps:create my-app
wokku config:set my-app SECRET_KEY="$(python -c 'import secrets; print(secrets.token_urlsafe(32))')"
wokku addons:shared:enable my-app postgres   # optional
```

Add-on ini mengisi `DATABASE_URL`; baca di config SQLAlchemy-mu. Lihat [Membuat & Menautkan Database](/docs/databases/create-link).

## Deploy dan migrate

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
wokku run my-app -- flask db upgrade   # if you use Flask-Migrate
```

Live di `https://my-app.wokku.app`. Baru pertama deploy? Lihat [Quickstart](/docs/getting-started/first-deploy).

## Troubleshooting

- **`ModuleNotFoundError`** — tambahkan package-nya ke `requirements.txt`.
- **Objek app tidak ditemukan** — `gunicorn app:app` artinya `module:variable`; samakan dengan nama file dan variabelmu.
- **Tidak bisa konek ke database** — cek apakah `wokku config my-app` menampilkan `DATABASE_URL`.
