---
title: Invoice
summary: "Siklus invoice bulanan: email pre-invoice → due date → grace 7 hari → suspend. Bayar via iPaymu. Perubahan mid-cycle prorata. Refund via credit di tagihan berikutnya."
eyebrow: billing
last_updated: 2026-05-29
---

# Invoice

Plan paid Wokku pakai model **invoice bulanan**. Nggak ada metering, nggak ada saldo deposit, nggak ada line item per-resource — cuma satu invoice flat per workspace per bulan, plus optional line add-on (extra seat di Team, proration mid-cycle di switch plan).

Halaman ini bahas lifecycle invoice lengkap.

## Siklusnya

```text
hari 0     subscribe (atau upgrade)         → free trial 7 hari mulai
hari 7     trial selesai                    → invoice pertama dibuat
hari +N    tanggal billing (anchor day)     → invoice mulai bisa dibayar
hari +N+7  due date                         → belum bayar? grace period mulai
hari +N+14 grace period selesai             → app di-suspend kalau masih belum bayar
hari +N+30 tanggal billing berikutnya       → siklus ulang
```

**Tanggal billing** kamu nge-anchor ke tanggal pertama kali subscribe. Kalau signup tanggal 15, tiap invoice bulanan landed tanggal 15.

## Apa yang ada di invoice

Invoice renewal standar punya satu line:

```text
Wokku Pro · 2026-06-15 → 2026-07-15      Rp 225.000
                            Total:        Rp 225.000
```

Di plan Team dengan extra seat, kamu liat line kedua:

```text
Wokku Team · 2026-06-15 → 2026-07-15           Rp 750.000
Extra seat × 2 · 2026-06-15 → 2026-07-15       Rp  90.000
                                Total:         Rp 840.000
```

Pas upgrade mid-cycle, kamu liat line proration:

```text
Pro → Team upgrade · prorata 18 dari 30 hari   Rp 315.000
                            Total:             Rp 315.000
```

## Kapan invoice di-generate

— **Invoice pertama** — di akhir trial 7 hari
— **Invoice renewal** — 7 hari sebelum tiap tanggal billing (via `Billing::IssueUpcomingInvoicesJob`, harian)
— **Invoice proration** — seketika pas upgrade mid-cycle

Kamu dapat email pas invoice di-generate, dengan jumlah dan link pembayaran iPaymu.

## Bayar

iPaymu handle semua metode pembayaran:

— **QRIS** — QR Indonesia universal — jalan sama e-wallet mana aja
— **Virtual Account** — BCA, Mandiri, BNI, BRI, Permata
— **E-wallet direct** — GoPay, OVO, DANA, LinkAja
— **Kartu** — Visa, Mastercard, Amex (3DS kalau didukung)

Kamu bisa bayar dari link email atau dari `/dashboard/billing`. Webhook iPaymu update status invoice ke `paid` dalam hitungan detik konfirmasi bank.

## Grace period & suspend

Kalau invoice nggak dibayar lewat **due date**, kamu masuk grace period 7 hari. Nggak ada yang keliatan — app kamu tetap jalan, tim kamu tetap kerja. Kami email reminder di hari 1, 3, dan 6.

Kalau invoice masih belum dibayar di **7 hari past due**, `Billing::SuspendOverdueJob` jalan dan:

— Set `billing_status` workspace ke `suspended`
— Stop semua container app paid (data tetap di disk; database masih jalan)
— Email owner workspace

Bayar invoice → app bangun otomatis (dalam ~30 detik webhook landed). Nggak perlu redeploy, nggak ada data hilang.

## Perubahan mid-cycle

### Upgrade

Switch dari Solo ke Pro di hari 18 dari 30-hari siklus:

— Invoice proration di-issue **seketika** buat selisih, prorata buat sisa hari: `(harga_Pro - harga_Solo) × (sisa_hari / total_hari)`
— Plan flip begitu invoice proration dibayar (atau langsung kalau kamu masih di trial)
— Renewal regular berikutnya landed di tanggal billing original dengan harga plan baru penuh

### Downgrade

Switch dari Pro ke Solo di hari 18:

— Nggak ada invoice seketika — kamu udah bayar Pro sampai akhir siklus
— Perubahan plan **dijadwal** di tanggal billing berikutnya
— Sampai itu, kamu tetap Pro
— Invoice renewal berikutnya di harga Solo

Ini sengaja: kamu nggak rugi apa yang udah dibayar.

### Cancel

Cancel plan dari `/dashboard/plan`:

— Kayak downgrade: dijadwal di akhir siklus
— Pas tanggal billing, kamu turun ke plan Free
— Resource paid kamu (Postgres di atas 100 MB, Redis kedua, box lebih besar) di-restrict graceful: data tetap, tapi read/write yang lewat batas Free tier dapat 503 dengan pesan "upgrade to continue"

## Refund

Invoice yang udah dibayar **nggak refundable** secara default. Kalau ada masalah di sisi kami (insiden hosting, bug billing, kehilangan data karena kami), email [billing@wokku.cloud](mailto:billing@wokku.cloud) dengan nomor invoice — kami selesain case-by-case.

## API

```bash
curl https://wokku.cloud/api/v1/invoices \
  -H "Authorization: Bearer $TOKEN"
```

Return tiap invoice buat workspace aktif, urut terbaru pertama. Tiap row include `status` (`pending` / `paid` / `failed` / `expired` / `refunded`), `amount_idr`, `period_start`, `period_end`, dan URL pembayaran iPaymu kalau masih belum dibayar.

## Self-hosted

Community Edition **nggak punya flow invoice**. Kamu jalanin platform sendiri; nggak ada yang ditagih.

## Lihat juga

— [Plan & Harga](/docs/billing/plans) — harga dan isi tiap plan
— [Usage](/docs/billing/usage) — view live plan + seat + utilization bundle
— [Plan Bundle](/docs/billing/plan-bundles) — cap DB / Redis / MinIO yang ship sama tiap plan
