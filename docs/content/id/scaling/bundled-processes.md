---
title: Menggabungkan Process
summary: Jalankan web dan worker dalam satu container, jadi kamu cukup bayar satu ukuran, bukan dua.
last_updated: 2026-11-09
---

Di sini kamu akan menjalankan beberapa process dalam satu container dengan process manager.

## Kenapa digabung

Setiap process type di `Procfile` kamu berjalan di container sendiri, dan setiap container ditagih untuk CPU dan RAM-nya. Ini menjalankan dua container:

```
web: bundle exec rails server
worker: bundle exec sidekiq
```

Dua container Starter (masing-masing 0.25 vCPU, 512 MB) biayanya Rp48.000/bulan. Satu container dengan 0.25 vCPU dan 1 GB bisa menampung kedua process seharga Rp42.000/bulan, karena keduanya berbagi CPU. Makin banyak process tambahan, makin besar hematnya.

## Polanya

Buat `web` menjalankan process manager (`foreman`, `honcho`, `concurrently`, `supervisor`) yang menjalankan semua process lainnya.

### Rails + Sidekiq

`Gemfile`:
```ruby
gem "foreman"
gem "sidekiq"
```

`Procfile` (yang dibaca Wokku):
```
web: bundle exec foreman start -f Procfile.bundled
```

`Procfile.bundled` (yang dibaca foreman):
```
rails: bundle exec rails server -p $PORT
sidekiq: bundle exec sidekiq
```

Wokku hanya melihat satu process type (`web`) dan menjalankan satu container. Di dalamnya, Foreman menjalankan Rails dan Sidekiq berdampingan.

### Django + Celery

`Procfile`:
```
web: honcho start -f Procfile.bundled
```

`Procfile.bundled`:
```
django: gunicorn myproject.wsgi --bind 0.0.0.0:$PORT
celery: celery -A myproject worker --loglevel=info
```

### Node + worker

```
web: npx concurrently "npm:start" "npm:worker"
```

## Gabung atau pisah?

| | Digabung (1 container) | Dipisah (satu per process) |
|---|---|---|
| **Biaya** | Satu ukuran | Satu ukuran per process |
| **Isolasi crash** | Satu crash me-restart semuanya | Masing-masing restart sendiri |
| **Scaling** | `web=2` menggandakan semua process | Scale masing-masing secara terpisah |
| **Log** | Bercampur | Satu stream per process |
| **Memori** | Dipakai bersama | Masing-masing punya sendiri |

Gabungkan untuk app hobi, staging, dan app dengan traffic rendah. Pisahkan kalau kamu perlu men-scale web dan worker secara terpisah, atau kalau worker-nya boros memori (pemrosesan gambar, PDF, ML).

## Menentukan ukuran container gabungan

Beri container RAM yang cukup untuk semua process saat beban puncak, ditambah sekitar 20%:

| Workload | Preset yang disarankan |
|---|---|
| Staging Rails + Sidekiq ringan | Starter (512 MB) atau Standard (1 GB) |
| Production Rails + Sidekiq dengan job ringan | Large (2 GB) |
| Job berat (gambar, PDF) | Pisahkan — beri worker container sendiri |

Ubah ukurannya di **Runtime** → **Scaling**. Lihat [Resource & Ukuran](/docs/scaling/resources).

## Lihat juga

- [Scaling Process](/docs/scaling/dynos)
- [Background worker](/docs/guides/background-workers)
