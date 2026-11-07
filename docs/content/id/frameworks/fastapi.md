---
title: FastAPI
summary: Jalankan app FastAPI di Wokku dengan Gunicorn dan worker Uvicorn.
last_updated: 2026-11-07
---

Tambahkan perintah start Gunicorn yang bind ke `$PORT`, push, dan API-mu langsung live. Mau repo yang sudah jalan dulu? Deploy starter `fastapi` dari [Templates](/docs/templates/browse).

## Dependency

```text
# requirements.txt
fastapi
uvicorn[standard]
gunicorn
```

## Perintah start

Dengan asumsi objek app-mu bernama `app` di `main.py`:

```procfile
web: gunicorn main:app -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:$PORT
```

Untuk satu proses saja, `web: uvicorn main:app --host 0.0.0.0 --port $PORT` juga bisa.

## Database (opsional)

```bash
wokku addons:shared:enable my-app postgres
```

Baca `os.environ["DATABASE_URL"]` di SQLAlchemy atau SQLModel. Driver async butuh skema URL yang diganti (`postgresql+asyncpg://`). Lihat [Membuat & Menautkan Database](/docs/databases/create-link).

## Deploy

```bash
wokku apps:create my-app
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

Live di `https://my-app.wokku.app`, dengan dokumentasi API interaktif di `/docs`. Baru pertama deploy? Lihat [Quickstart](/docs/getting-started/first-deploy).

## Troubleshooting

- **502 / tidak ada respons** — bind harus memakai `$PORT`, bukan port tetap.
- **`UvicornWorker` tidak ditemukan** — tambahkan `uvicorn[standard]` ke `requirements.txt`.
- **Migration (Alembic)** — jalankan setelah deploy: `wokku run my-app -- alembic upgrade head`.
