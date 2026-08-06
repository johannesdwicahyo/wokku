# Rollback Deploy yang Gagal

Mengirim sesuatu yang rusak? Rollback ke release sebelumnya dalam hitungan detik.
Wokku menyimpan setiap release, jadi revert bersifat instan — tanpa rebuild.

## Lihat release-mu

:::tabs
::web-ui
Aplikasi → **Activity / Releases** menampilkan tiap deploy dengan versi dan commit-nya.

::cli
```bash
wokku releases my-app
```
:::

Tiap release adalah snapshot immutable dari image yang dibuild + config saat deploy.

## Rollback

:::tabs
::web-ui
Di daftar **Releases**, klik **Roll back** pada release yang ingin dikembalikan.

::cli
```bash
# rollback ke release tepat sebelumnya
wokku rollback my-app

# atau ke versi spesifik
wokku rollback my-app --version 42
```

::mcp
Tanya Claude: *"Rollback my-app ke release sebelumnya"*
:::

Rollback menjalankan ulang image release terpilih — **tanpa rebuild**, jadi cepat.

## Yang dilakukan & tidak oleh rollback

- ✅ Mengembalikan **kode aplikasi** dari release terpilih.
- ⚠️ **Tidak membatalkan migration database.** Jika deploy yang rusak menjalankan
  migration destruktif, rollback kode tidak mengembalikan skema/data — restore
  dari [backup](/docs/databases/backups) bila perlu.
- ✅ Mengembalikan config yang dikirim bersama release itu.

:::callout warn
Tulis migration agar **backward-compatible** (aditif dulu, destruktif belakangan)
supaya rollback kode tetap aman. Ini satu hal terbesar yang membuat rollback
tanpa rasa sakit.
:::

## Roll forward

Sudah menemukan dan memperbaiki bug? Tinggal deploy lagi — perbaikan jadi release
terbaru. Tidak ada langkah "un-rollback" khusus.

## Troubleshooting

- **Rollback tidak memperbaiki** — masalahnya mungkin data/migration, bukan kode. Cek restore backup.
- **Tidak menemukan release yang baik** — `wokku releases my-app` menampilkannya dengan versi; pilih yang terakhir baik.

## Langkah berikutnya

- [Backup](/docs/databases/backups) · [Kesiapan Production](/docs/apps/best-practices)
