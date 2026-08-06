---
title: Member & Role
summary: "Undang orang ke workspace, kasih role, dan tagih seat over-quota dengan benar di plan Team."
eyebrow: teams
last_updated: 2026-05-29
---

# Member & Role

Wokku ngatur app dan resource ke dalam [workspace](/docs/workspaces/personal-vs-org). Tiap user punya satu **personal workspace** (akun gratis kamu) dan bisa jadi member di workspace **org** sebanyak yang dia mau (plan Team).

Halaman ini bahas cara manage member workspace — invite, kasih role, hapus, dan gimana seat billing Team jalan.

## Undang member

Buka workspace di `/dashboard/workspaces/<id>` (atau pakai [switcher](/docs/workspaces/switching) buat lompat ke sana dulu). Admin liat form **+ add member**:

1. Ketik email orangnya.
2. Pilih role: viewer / member / admin.
3. Submit.

**Orangnya harus udah punya akun Wokku** — kita belum email invite signup. Suruh dia signup di [wokku.cloud](https://wokku.cloud) pakai email yang sama, terus retry add-nya.

```text
> No user with that email — ask them to sign up first.
```

Itu error yang muncul kalau email-nya nggak match akun yang ada.

## Role

| Role | Apa yang bisa dilakuin |
|---|---|
| **Viewer** | Akses read-only ke app, log, metrics, dan audit log. Cocok buat stakeholder, designer, BizOps. |
| **Member** | Semua yang Viewer bisa, plus deploy, env var, custom domain, database management, dan CRUD addon. |
| **Admin** | Semua yang Member bisa, plus invite / remove member, ganti role, dan switch plan. **Owner** workspace selalu admin dan nggak bisa di-demote. |

Perubahan role berlaku di request berikutnya — nggak perlu reauth.

## Hapus member

Di tabel member workspace, klik **remove** di barisnya. Orangnya langsung kehilangan akses ke workspace:

— App yang dia deploy tetap (workspace yang punya app, bukan member-nya)
— API token yang dia bikin terhadap workspace di-revoke di call berikutnya
— Personal workspace dia nggak ke-affect

**Owner** workspace nggak bisa di-remove — buat transfer workspace ke orang lain, hubungi support.

## Seat billing (cuma plan Team)

Plan Team include **3 seat** di harganya (Rp 750.000 / bulan). Seat tambahan ditagih **Rp 45.000 per seat / bulan**.

Cara kerjanya:

— Kamu bisa add member sebanyak yang kamu mau — nggak ada cap keras di Team
— Dashboard nampilin banner kalau jumlah member lewat seat yang termasuk
— Di invoice berikutnya, overage-nya otomatis ditambah: `extra_seats × Rp 45.000`
— Remove member sebelum tanggal billing nge-drop dia dari invoice berikutnya — proration-nya by *count pas invoice time*, bukan by jam-di-workspace

> Plan paid lain (Solo, Pro) hard-cap di 1 seat — kamu nggak bisa undang member kedua tanpa upgrade ke Team.

## Apa yang member liat

Member di org workspace dapat [switcher workspace](/docs/workspaces/switching) di atas dashboard. Mereka bisa switch antara personal workspace dan org mana aja yang mereka ikut; data di-scope per workspace.

Saat switch workspace:

— Ganti app dan resource yang tampil di dashboard
— Ganti yang bayar resource baru (owner workspace, bukan member-nya)
— Nggak ngubah auth / 2FA / API token member-nya sendiri

## CLI

```bash
wokku members:add alice@example.com --workspace acme-co --role member
wokku members:remove alice@example.com --workspace acme-co
wokku members:list --workspace acme-co
```

CLI pakai aturan email-harus-ada yang sama.

## API

```bash
curl -X POST https://wokku.cloud/api/v1/workspaces/WORKSPACE_ID/members \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"email": "alice@example.com", "role": "member"}'
```

Lihat [API reference](/docs/api/endpoints) buat skema lengkapnya.

## Audit log

Tiap add / remove / ganti role muncul di [audit log](/docs/monitoring/audit-log) workspace dengan actor, target, dan role-nya. Berguna buat compliance dan buat mastiin pertanyaan "siapa yang remove Alice?" pas lagi telusur.

## Lihat juga

— [Permission](/docs/teams/permissions) — apa yang tiap role bisa, detail
— [Personal vs Org workspace](/docs/workspaces/personal-vs-org) — kapan bikin org workspace
— [Switch workspace](/docs/workspaces/switching) — gimana topbar switcher kerja
