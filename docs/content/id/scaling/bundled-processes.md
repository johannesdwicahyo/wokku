---
title: Bundling Process
summary: "Jalanin web + worker + scheduler dalam satu container, cuma pakai satu box. Harga plan tetap sama, lebih banyak ruang."
eyebrow: scaling
last_updated: 2026-05-29
---

# Bundling Process dalam Satu Container

Hemat box dengan ngejalanin banyak process di dalam satu container.

## Kapan ini penting

Wokku ngitung **box per container**: 1 container = 1 box, terlepas dari berapa process di dalamnya. Pattern Procfile default spawn satu container per process type:

```
web: bundle exec rails server
worker: bundle exec sidekiq
```

Itu dua container, **dua box terpakai**. Di Pro (3 small + 2 medium) kamu udah habisin 2-dari-5 box sebelum scaling apa-apa.

Buat app kecil dimana process crash bukan masalah kritis, kamu bisa **bundle** process-nya jadi satu container dan cuma pakai **satu box total**. Harga plan tetap, ruang lebih banyak.

## Pattern-nya

Pakai process manager (`foreman`, `honcho`, `supervisor`, `s6-overlay`) di dalam container.

### Contoh Rails + Sidekiq

`Gemfile`:
```ruby
gem "foreman"
gem "sidekiq"
```

`Procfile` (yang dibaca Wokku):
```
web: foreman start -f Procfile.bundled
```

`Procfile.bundled` (yang dibaca foreman):
```
rails: bundle exec rails server -p $PORT
sidekiq: bundle exec sidekiq
```

Deploy. Wokku liat satu process type (`web`), jalanin satu container. Di dalamnya, foreman supervise Rails + Sidekiq berdampingan.

### Contoh Django + Celery

```
web: honcho start -f Procfile.bundled
```

`Procfile.bundled`:
```
django: gunicorn myproject.wsgi --bind 0.0.0.0:$PORT
celery: celery -A myproject worker --loglevel=info
```

### Contoh Node + worker

```
web: npx concurrently "npm:start" "npm:worker"
```

## Kapan bundle vs split

| | Bundled (1 container) | Split (N container) |
|---|---|---|
| **Biaya box** | 1 | N |
| **Isolasi process** | ✗ — crash di satu mematikan container | ✓ — masing-masing restart independen |
| **Scaling** | All-or-nothing — `ps:scale web=2` doubling semua process | ✓ — `web=3 worker=1` independen |
| **Deploy** | Semua restart bareng | ✓ — rolling per process type |
| **Log** | Berbaur (pakai logger dengan prefix) | ✓ — stream bersih per-process |
| **Memory** | Cap dibagi — size untuk total peak + 20% | Masing-masing dapat alokasi tier penuh |

### Pakai bundled kalau

— App kecil / hobby / side-project
— Background worker traffic rendah (Sidekiq dengan workload mostly-cron)
— Bisa size container buat kombinasi RAM peak dengan nyaman
— Isolasi crash bukan requirement keras

### Pakai split kalau

— Production scale — scaling tidak merata penting (3× web, 1× worker)
— Satu process yang lambat atau crash tidak boleh nge-affect SLO process lain
— Mau log stream bersih per process
— Worker-nya berat memory (image processing, ML inference) dan bisa spike independen

## Sizing memory buat bundled

Pilih container tier yang:

```
container_memory >= sum(per-process peak RSS) + 20% headroom
```

Sizing kasar Rails + Sidekiq di tier small ↔ medium:

| Workload | Tier yang disarankan |
|---|---|
| Rails dev/staging + Sidekiq volume rendah | **Small** (512 MB) |
| Production Rails (~50-200 req/s) + Sidekiq job ringan | **Medium** (2 GB) |
| Sidekiq job berat (image processing, generate PDF) | Split — kasih Sidekiq box sendiri |

## Routing internal (kalau butuh banyak HTTP server)

Kalau process yang kamu bundle dua-duanya ngomong HTTP (mis. Rails di `$PORT` + sidecar FastAPI di `5001`), tambah nginx internal yang route by path:

`nginx.conf`:
```
server {
  listen $PORT;
  location /api/ { proxy_pass http://127.0.0.1:5001; }
  location /     { proxy_pass http://127.0.0.1:3000; }
}
```

Lalu `Procfile.bundled`:
```
nginx: nginx -g "daemon off;"
rails: bundle exec rails server -p 3000
api: uvicorn api.main:app --port 5001 --host 127.0.0.1
```

Wokku tetap liat satu container `web`.

## Starter template

— [Rails + Sidekiq bundled starter](/templates) — production Rails 8 dengan Sidekiq di-supervise foreman dalam satu container. Deploy langsung satu klik.

## Lihat juga

— [Process Types & Dynos](/docs/scaling/dynos) — model split-process default
— [Box Tiers](/docs/scaling/tiers) — pilih size yang pas buat container bundled kamu
