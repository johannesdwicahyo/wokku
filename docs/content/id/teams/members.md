---
title: Member & Role
summary: Tambahkan orang ke workspace org, pilih role-nya, dan lihat persis apa yang bisa dilakukan tiap role.
last_updated: 2026-11-07
---

Tambahkan rekan tim ke [workspace](/docs/workspaces/personal-vs-org) org, beri mereka role, lalu ubah atau hapus nanti. Hanya admin yang bisa mengelola member.

## Menambahkan member

Orang tersebut harus punya akun Wokku dulu — undangan tidak dikirim lewat email. Kalau email-nya tidak cocok dengan akun mana pun, kamu akan melihat *"No user with that email — ask them to sign up first."*

:::tabs
::web-ui
1. Pindah ke workspace org, lalu buka switcher → **Manage →** dan pilih workspace-nya.
2. Di bagian **add by email**, masukkan email mereka.
3. Pilih role — viewer, member, atau admin — lalu klik **add member**.

::cli
```bash
wokku teams                       # find the workspace (team) ID
wokku teams:members:add TEAM_ID --email alice@example.com --role member
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/teams/TEAM_ID/members \
  -H "Authorization: Bearer $WOKKU_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"email": "alice@example.com", "role": "member"}'
```

Dapatkan `TEAM_ID` dari `GET /api/v1/teams`.

::mcp
Tanya Claude: *"Tambahkan alice@example.com ke tim saya sebagai member."* (memakai `wokku_add_team_member`)
:::

Kalau workspace sudah memakai semua seat-nya, penambahan gagal dengan pesan yang meminta kamu pindah ke plan Team.

## Mengubah role atau menghapus member

:::tabs
::web-ui
Di tabel member, ubah role dari dropdown, atau klik **remove**.

::cli
```bash
wokku teams:members TEAM_ID                                  # shows membership IDs
wokku teams:members:role TEAM_ID MEMBERSHIP_ID admin
wokku teams:members:remove TEAM_ID MEMBERSHIP_ID
```

::api
```bash
# change role
curl -X PATCH https://wokku.cloud/api/v1/teams/TEAM_ID/members/MEMBERSHIP_ID \
  -H "Authorization: Bearer $WOKKU_API_TOKEN" \
  -H "Content-Type: application/json" -d '{"role": "admin"}'

# remove
curl -X DELETE https://wokku.cloud/api/v1/teams/TEAM_ID/members/MEMBERSHIP_ID \
  -H "Authorization: Bearer $WOKKU_API_TOKEN"
```

::mcp
Tanya Claude: *"Jadikan alice admin"* atau *"Keluarkan alice dari tim saya."* (memakai `wokku_update_team_member` / `wokku_remove_team_member`)
:::

Aturan:

- **Pemilik** workspace tidak bisa dikeluarkan.
- Workspace selalu punya minimal satu admin — admin terakhir tidak bisa menurunkan role-nya sendiri.
- Mengeluarkan seseorang tidak menghapus app-nya: app dimiliki workspace.
- Workspace personal mereka tidak terpengaruh.

## Apa yang bisa dilakukan tiap role

| Aksi | Viewer | Member | Admin |
|---|:-:|:-:|:-:|
| Melihat app, log, metrics, config var | ✓ | ✓ | ✓ |
| Membuat dan deploy app | — | ✓ | ✓ |
| Mengubah config var, domain, scaling | — | ✓ | ✓ |
| Restart, stop, start, rollback | — | ✓ | ✓ |
| Resize, restore, atau retry database | — | ✓ | ✓ |
| Menghapus app | — | — | ✓ |
| Menghapus database | — | — | ✓ |
| Menambah, menghapus, dan mengubah member | — | — | ✓ |

Orang yang membuat database selalu bisa mengelola dan menghapusnya, apa pun role-nya.

Member yang ditambahkan atau dihapus dari dashboard tercatat di [audit log](/docs/monitoring/audit-log).
