# Preview Deploy untuk Pull Request

Dapatkan URL live yang terisolasi untuk tiap pull request — review kode yang
benar-benar berjalan sebelum di-merge. Wokku membuatnya saat PR dibuka dan
menghancurkannya saat ditutup.

:::callout note
PR preview adalah fitur **Pro** dan butuh [GitHub Auto-Deploy](/docs/apps/github-autodeploy)
terhubung ke aplikasimu. Lihat [Plan](/docs/billing/plans).
:::

## Cara kerja

Saat kamu membuka PR terhadap deploy branch-mu, Wokku mem-build branch itu jadi
**aplikasi preview sementara** di URL-nya sendiri (mis. `my-app-pr-42.wokku.app`).
Wokku meng-comment URL-nya di PR. Saat PR di-merge atau ditutup, preview
dihancurkan otomatis.

## Aktifkan preview

1. Hubungkan repo via [GitHub Auto-Deploy](/docs/apps/github-autodeploy)
2. Aplikasi → **Settings** → aktifkan **PR Previews**
3. Buka pull request — Wokku build dan comment URL live-nya

## Yang didapat preview

- Container-nya sendiri yang dibuild dari branch PR
- Salinan **config var** aplikasi induk (supaya boot dengan cara sama)
- Subdomain-nya sendiri dengan SSL otomatis

:::callout warn
Preview berbagi **add-on** dengan aplikasi induk secara default (sama `DATABASE_URL`).
Jangan jalankan migration destruktif atau seed script dari preview terhadap
database production — arahkan preview ke database sekali-pakai jika alurmu menulis data.
:::

## Bersih-bersih

Preview menghancurkan diri saat PR ditutup. Untuk menghapus manual:

:::tabs
::cli
```bash
wokku previews my-app                       # list preview aktif
wokku previews:destroy my-app --pr 42       # hancurkan satu
```
:::

## Troubleshooting

- **Tidak ada preview muncul** — pastikan aplikasi Pro, GitHub terhubung, dan preview aktif.
- **Tidak ada comment PR** — Wokku butuh izin meng-comment; cek ulang koneksi GitHub.
- **Preview tidak bisa akses data** — ia mewarisi config/add-on induk; verifikasi itu ter-set.

## Langkah berikutnya

- [GitHub Auto-Deploy](/docs/apps/github-autodeploy) · [Rollback deploy yang gagal](/docs/guides/rollback)
