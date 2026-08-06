---
title: Personal vs Org Workspace
summary: "Tiap akun Wokku dimulai dengan satu personal workspace. Org workspace buat kerja bareng — cuma plan paid, ditagih ke owner workspace."
eyebrow: workspaces
last_updated: 2026-05-29
---

# Personal vs Org Workspace

Wokku nge-scope semua hal (app, resource, billing, audit log) ke **workspace**. Ada dua jenis:

— **Personal** — tiap akun dapat satu pas signup. Gratis selamanya, jalan bareng membership org mana aja.
— **Org** — dibuat on-demand buat kerja bareng orang lain. Butuh plan paid; yang bikin jadi owner-nya.

Kamu selalu di dalam *satu* workspace pada satu waktu. [Switcher](/docs/workspaces/switching) di topbar nampilin kamu lagi di mana dan kasih kamu ganti workspace.

## Personal workspace

Tiap signup dapat personal workspace, gratis. Itu punya kamu, nggak bisa di-leave atau dihapus — terikat ke akun kamu.

Yang ada di sini:

— App yang kamu deploy tanpa explicitly switch workspace
— Resource free-tier kamu (1 box ukuran apa aja, 1 Postgres, 1 Redis, 1 bucket MinIO)
— Billing dan invoice personal kamu (kalau upgrade)
— Seat personal kamu — nggak ada orang lain yang bisa gabung personal workspace kamu

Yang nggak ada:

— Nggak bisa add member
— Nggak bisa undang kolaborator
— Nggak bisa transfer app dari org workspace masuk ke sini (pakai [app transfer](/docs/apps/lifecycle) buat itu)

Anggap aja dev sandbox kamu: side project, prototype, demo yang kamu ship buat client sebelum mereka bayar.

## Org workspace

Buat semua hal lain — kerja agency buat client, app startup kamu, kolaborasi co-founder — kamu bikin **org workspace**.

Syarat:

— Plan paid (Solo, Pro, atau Team — lihat [Plan](/docs/billing/plans))
— Kamu jadi **owner** workspace; owner nggak bisa di-remove
— Kamu bisa add member (cuma plan Team — Solo dan Pro hard-cap di 1 seat)

Buat bikin: buka [switcher workspace](/docs/workspaces/switching) → **+ new workspace** → kasih nama, pilih plan, konfirmasi. Switcher langsung lompat ke workspace baru.

Yang ada di org workspace:

— App, database, cache, bucket object storage — di-scope ke workspace
— Plan + billing + invoice workspace itu sendiri (dibayar owner)
— Audit log buat semua yang dilakuin di dalamnya
— Member list dan role assignment

## Workspace mana yang bayar?

Workspace yang **own** resource yang bayar. Owner workspace itu yang dapat invoice.

— Resource dibikin di dalam personal workspace kamu → ditagih ke akun Wokku personal kamu
— Resource dibikin di dalam org workspace → ditagih ke akun **owner org workspace**
— Member yang deploy app ke org → owner org yang bayar, bukan member-nya

Billing personal workspace member nggak tersentuh. Member bisa punya personal workspace Free dan tetap jadi admin di Team org paid — keduanya independen.

## Switch context

Switcher topbar (kiri atas, setelah logo) nampilin kamu lagi di workspace mana. Klik buat:

— Switch ke workspace lain yang kamu ikut
— Bikin org workspace baru (`+ new workspace`)
— Manage member workspace yang kamu own (`manage →`)

Lihat [Switch workspace](/docs/workspaces/switching) buat mekanika lengkapnya.

## Yang TIDAK di-share antar workspace

Tiap workspace adalah boundary billing + resource terpisah. Nggak ada yang bocor:

— **App** — kamu nggak bisa liat app workspace lain kecuali kamu member
— **Plan dan billing** — tiap workspace punya subscription sendiri
— **Audit log** — di-scope ke workspace; owner liat action admin di workspace-nya, member liat action mereka sendiri
— **API token** — token-nya punya kamu, tapi dia beroperasi di workspace mana yang lagi aktif

Yang DI-share (karena ke akun, bukan workspace):

— Auth kamu (login, 2FA, OAuth)
— Email / nama / avatar personal kamu
— Install `wokku CLI` kamu
— Notifikasi dan page `/dashboard/profile` personal

## Pattern umum

| Skenario | Setup |
|---|---|
| Solo dev dengan plan paid | Personal workspace di-upgrade ke Solo. Selesai. |
| Solo dev + side gig | Personal workspace (Free) buat hobby; bikin org workspace per client paid. |
| Agency | Satu org workspace per client, di Pro atau Team. Undang client sebagai viewer. Tagih agency, invoice client terpisah. |
| Startup dengan co-founder | Satu org workspace di Team, dua-duanya jadi admin. Personal workspace tetap terpisah. |
| Tim internal 5 orang | Plan Team org workspace, 3 seat termasuk + 2 extra @ Rp 45.000. |

## Lihat juga

— [Switch workspace](/docs/workspaces/switching) — mekanika topbar switcher
— [Member & Role](/docs/teams/members) — manage siapa di workspace
— [Plan & Harga](/docs/billing/plans) — plan mana yang dukung ukuran workspace apa
