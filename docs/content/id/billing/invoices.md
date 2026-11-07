---
title: Invoice & Pembayaran
summary: Bagaimana invoice bulanan kamu disusun, cara membayarnya, dan apa yang terjadi kalau tidak dibayar.
last_updated: 2026-11-07
---

Di sini kamu akan membaca invoice, membayarnya, dan mengecek pemakaian di halaman Billing.

## Siklusnya

**Tanggal billing** kamu adalah tanggal di bulan saat kamu pertama kali menjalankan sesuatu yang berbayar. Kalau itu tanggal 15, setiap invoice jatuh pada tanggal 15.

| Kapan | Yang terjadi |
|---|---|
| 7 hari sebelum tanggal billing | Invoice diterbitkan dan dikirim lewat email (PDF terlampir, dengan link pembayaran) |
| Tanggal billing | Invoice jatuh tempo |
| 7 hari setelah jatuh tempo, masih belum dibayar | Akun di-suspend (lihat di bawah) |

Akun yang hanya memakai layanan gratis tidak pernah mendapat invoice. Kalau tidak ada yang perlu ditagih, tidak ada invoice yang diterbitkan.

## Isi invoice

Setiap process app, volume, dan dedicated database punya baris masing-masing:

| Baris | Arti |
|---|---|
| **Advance** | Bulan berikutnya untuk setiap resource, sesuai ukurannya saat ini |
| **Usage** | Biaya sebenarnya setiap resource per hari sejak invoice terakhir (tanggal ditampilkan) |
| **Already paid in advance for these days** | Mengurangi yang sudah dibayar lewat advance sebelumnya |
| **Credit carried from last invoice** | Mengurangi sisa kredit, misalnya setelah downsize |

Jadi kamu membayar bulan berikutnya di depan, dan invoice berikutnya menyelesaikan selisihnya dengan apa yang benar-benar kamu jalankan. Kalau kredit lebih besar dari tagihan, kamu bayar Rp0 dan sisanya dibawa ke invoice berikutnya.

Invoice pertama kamu tidak punya advance sebelumnya untuk dikurangi: isinya pemakaian kamu sejauh ini plus bulan berikutnya.

## Bayar invoice

1. Buka email invoice dan klik link pembayaran, atau buka **Settings** → **Billing** lalu klik **Pay now**.
2. Di halaman iPaymu, bayar dengan QRIS (e-wallet atau aplikasi banking apa pun), transfer bank (BCA, BNI, BRI, Mandiri, dan lainnya), atau kartu (Visa, Mastercard).
3. Invoice berubah menjadi **paid** setelah iPaymu mengonfirmasi pembayaran.

Pembayaran selalu dilakukan di dashboard. CLI, API, dan MCP bisa menampilkan daftar invoice dan memberikan link pembayaran.

## Kalau invoice tidak dibayar

Tujuh hari setelah jatuh tempo, akun kamu di-suspend:

- App berbayar yang sedang berjalan akan dihentikan. App sleeping gratis tetap berjalan.
- Kamu tidak bisa start, restart, atau deploy app sampai kamu membayar.
- Kamu menerima email berisi daftar app yang dihentikan.

Data kamu tetap disimpan. Bayar semua invoice yang lewat jatuh tempo dan app kamu akan berjalan lagi secara otomatis; kamu akan menerima email saat app sudah kembali.

## Halaman Billing

Buka **Settings** → **Billing**:

- **Upcoming invoice** dengan tombol **Pay now**, dan invoice **last paid** kamu.
- **This month so far** dan **Projected next invoice** (dengan tanggalnya), plus **Credit** kalau ada.
- Setiap process app dan dedicated database beserta ukuran dan harga bulanannya.
- Invoice terbaru kamu, dengan **view all** dan ekspor **csv**.

## Lihat daftar invoice

:::tabs
::web-ui
**Settings** → **Billing** → **view all**.

::cli
```bash
wokku billing:invoices
```
Invoice yang belum dibayar menampilkan link pembayarannya.

::api
```bash
curl https://wokku.cloud/api/v1/billing/invoices \
  -H "Authorization: Bearer $TOKEN"
```
Setiap invoice punya `reference`, `period`, `amount_idr`, `status` (`pending`, `paid`, `failed`, `expired`, `refunded`, `void`), `due_date`, `paid_at`, dan `pay_url` selama belum dibayar.

::mcp
Minta ke Claude: *"Tampilkan daftar invoice Wokku saya"*
:::

## Lihat juga

- [Harga](/docs/billing/pricing)
- [Resource & Ukuran](/docs/scaling/resources)
