---
title: Usage
summary: "Lihat sekali pandang apa yang kamu bayar: plan, quota box yang kepakai, pemakaian addon bundle, sisa seat. Update live."
eyebrow: billing
last_updated: 2026-05-29
---

# Usage

Page **Usage** di dashboard itu satu layar buat liat apa yang plan kamu cover vs apa yang sebenernya kamu pakai. Buka **Settings → Usage** (atau `/dashboard/usage`).

## Apa yang ditampilin

### Plan summary

Section atas nampilin:

— Nama plan kamu sekarang dan harga bulanannya
— Status trial dan sisa hari (kalau kamu masih di dalam trial)
— Tanggal invoice berikutnya dan jumlahnya

### Quota box

Empat tile yang nampilin **kepakai / termasuk** buat tiap ukuran box di plan kamu: Small / Medium / Large / Sleeping. Angkanya mencerminkan semua container yang lagi jalan, termasuk container bundled-process (yang dihitung satu box meski jalanin banyak process).

Kalau lewat quota, tile-nya nampilin "over quota" merah. Deploy baru di ukuran itu bakal di-block sampai kamu scale down atau upgrade plan.

### Addon bundle

Tiga tile buat resource yang bundled sama plan kamu:

— **Postgres** — jumlah database vs 1-termasuk; cap-nya adalah batas size per-tenant (mis. 100 MB di Free, 1 GB di Solo, 10 GB di Team)
— **Redis** — bentuk sama; cap-nya adalah batas memory
— **Object Storage** — jumlah bucket MinIO + cap size bucket

### Tabel app

Tiap app yang kamu punya, dengan status (running / sleeping / crashed / stopped), tier box yang dia jalanin, dan jumlah container. Klik baris mana aja buat lompat ke overview app.

## Cara kerja billing

Wokku pakai model **invoice bulanan** — nggak ada metering per jam, nggak ada saldo deposit. Lihat [Plan & Harga](/docs/billing/plans#cara-kerja-billing) buat siklus lengkapnya: email pre-invoice → due date → grace 7 hari → suspend. Buat penjelasan mendalam tentang generate invoice, proration, dan refund lihat [Invoice](/docs/billing/invoices).

## Upgrade / downgrade

Dua tempat buat ganti plan:

— **Plan switcher** di `/dashboard/plan` — pilih plan, konfirmasi. Upgrade mid-cycle nerbitin invoice prorata seketika; downgrade dijadwal ke tanggal billing berikutnya.
— **Box scaling** di `/dashboard/apps/<app>/scaling` — ganti ukuran container individual tanpa nyentuh plan. Berguna kalau kamu masih ada ruang di quota box tapi pengen container lebih gede buat satu app.

## Metode pembayaran

iPaymu handle semua:

— **QRIS** — bayar pakai e-wallet Indonesia mana aja (GoPay, OVO, DANA, ShopeePay, BCA mobile, Mandiri, BRImo, dll.)
— **Virtual Account** — BCA, Mandiri, BNI, BRI, Permata
— **E-wallet direct** — GoPay, OVO, DANA, LinkAja
— **Kartu** — Visa, Mastercard, Amex (3DS kalau didukung)

Invoice yang dikirim 7 hari sebelum tanggal billing udah termasuk URL pembayaran iPaymu. Billing page di dashboard selalu ada tombol "Bayar sekarang" buat invoice yang belum dibayar.

## Pemakaian seat (plan Team)

Kalau kamu di Team:

— Seat termasuk plan: 3
— Seat tambahan: Rp 45.000 per seat / bulan, diprorata buat siklus parsial
— Banner kecil muncul di atas `/dashboard/team` waktu kamu lewat jumlah seat yang termasuk — overage-nya otomatis masuk ke invoice berikutnya

## Self-hosted

Community Edition nggak punya billing surface. Page usage di CE nampilin jumlah resource aja, nggak ada biaya.
