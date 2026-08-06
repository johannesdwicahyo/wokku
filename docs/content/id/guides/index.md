# Panduan How-To

Resep berfokus-tugas untuk pekerjaan deployment umum. Setiap resep bersifat
end-to-end — ikuti dari atas ke bawah dan tugasmu selesai.

Baru di Wokku? Mulai dari [Deploy Pertama](/docs/getting-started/first-deploy)
atau [panduan framework](/docs/frameworks/index) dulu.

## Resep

- **[Jalankan background worker](/docs/guides/background-workers)** — queue, consumer, proses non-web apa pun
- **[Jadwalkan tugas (cron)](/docs/guides/scheduled-tasks)** — jalankan perintah sesuai jadwal
- **[Tambah Postgres + Redis](/docs/guides/postgres-redis)** — wire database dan cache ke satu aplikasi
- **[Deploy dengan Dockerfile](/docs/guides/dockerfile)** — kontrol penuh atas build
- **[Deploy dari monorepo](/docs/guides/monorepo)** — kirim satu aplikasi dari subdirektori
- **[Rollback deploy yang gagal](/docs/guides/rollback)** — kembali instan ke release sebelumnya
- **[Preview deploy untuk pull request](/docs/guides/preview-deploys)** — URL live per PR
- **[Deploy dengan Claude (MCP)](/docs/guides/deploy-with-claude)** — provisioning + deploy dari editor

## Lihat juga

- **Environment variable & secret** → [Config](/docs/apps/config)
- **Domain kustom & SSL** → [Domain Kustom](/docs/domains-ssl/custom-domains) · [SSL](/docs/domains-ssl/ssl)
- **Logs** → [Logs](/docs/apps/logs)
