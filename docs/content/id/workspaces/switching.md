---
title: Switch Workspace
summary: "Switcher topbar buat pindah antara personal workspace dan org yang kamu ikut. Persisten lewat session cookie, friendly buat deep-link."
eyebrow: workspaces
last_updated: 2026-05-29
---

# Switch Workspace

Saat kamu jadi member di lebih dari satu workspace — personal plus org mana aja yang kamu bikin atau gabung — **switcher workspace** di kiri-atas tiap page dashboard itu cara kamu pindah antar workspace.

## Switcher-nya

Letaknya tepat setelah logo Wokku di topbar. Klik buka dropdown:

— **Workspace sekarang** di-highlight di atas
— **Workspace lain yang kamu ikut** di bawahnya — klik buat switch
— **+ new workspace** di bawah — bikin org workspace (cuma plan paid)
— **manage →** link ke `/dashboard/workspaces` (list lengkap dengan action per-workspace)

Dropdown nampilin sampai 8 workspace inline; lebih dari itu via `manage →`.

## Gimana "current" ditentuin

Workspace sekarang di-resolve per-request urutannya:

1. **Session cookie explicit** — `session[:current_team_id]` di-set sama switch terakhir
2. **Personal workspace kamu** — fallback kalau nggak ada session cookie

Jadi sekali kamu switch, pilihan-nya nempel lintas page load (dan tab, browser, dll. yang share session) sampai kamu switch lagi.

## Deep-linking

Kadang kamu mau share URL dashboard yang nge-landing penerima di workspace *spesifik*, bukan default mereka. Action switcher — URL pattern `POST /dashboard/workspaces/<id>/switch` — nerima param `return_to`:

```text
POST /dashboard/workspaces/abc123/switch?return_to=/dashboard/apps/myapp
```

Setelah switch, user di-redirect ke `return_to`. Membership di-validasi ulang di server, jadi kalau penerima bukan member workspace itu, switch-nya gagal dengan 404 dan dia tetap di workspace sebelumnya.

## Apa scope yang berubah pas switch

Semua di dashboard re-render buat workspace baru:

— **List app** — nampilin app di workspace baru
— **Database, cache, object storage** — scope sama
— **Billing & invoice** — pindah ke plan dan history tagihan workspace baru
— **Audit log** — nampilin event workspace baru
— **Team / member page** — member workspace baru

Yang tetap sama:

— **Akun kamu** — login, 2FA, provider OAuth
— **CLI / API token kamu** — token sama, mereka beroperasi di workspace mana yang lagi aktif
— **Profile kamu** — nama, email, avatar, preferensi notifikasi

## Dari CLI

```bash
wokku workspaces:list             # nampilin workspace yang kamu ikut
wokku workspaces:switch <slug>    # switch context
wokku workspaces:current          # print workspace aktif
```

Sekali switch, command CLI lain (`wokku deploy`, `wokku logs`, `wokku databases:list`) beroperasi di workspace itu.

## Dari API

API token di-scope ke user. Tambah `X-Wokku-Workspace: <slug>` buat scope request ke workspace spesifik:

```bash
curl https://wokku.cloud/api/v1/apps \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Wokku-Workspace: acme-co"
```

Tanpa header, API default ke personal workspace kamu.

## Kapan switcher nggak muncul

Kalau kamu cuma ada di satu workspace (kasus umum buat akun baru), switcher render sebagai label statis — nggak ada yang bisa di-switch. Begitu kamu bikin org workspace atau diundang ke satu, dropdown-nya nyala.

## Gotcha umum

— **"Aku deploy ke workspace yang salah"** — switch context dan pakai [app transfer](/docs/apps/lifecycle) buat mindahin
— **"CLI-ku terus pakai workspace yang salah"** — `wokku workspaces:switch <slug>` persist di `~/.wokku/config`; cek `wokku workspaces:current`
— **"Session reset dan aku balik ke personal"** — cookie expired atau browser bersihin; switch lagi aja

## Lihat juga

— [Personal vs Org workspace](/docs/workspaces/personal-vs-org) — kapan bikin org workspace
— [Member & Role](/docs/teams/members) — manage siapa di workspace
