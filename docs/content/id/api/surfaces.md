---
title: Semua Antarmuka
summary: "Apa saja yang bisa kamu lakukan dari dashboard, REST API, CLI, Claude Code, dan app iOS. Setiap aksi di dashboard punya endpoint API, dan CLI serta Claude Code mencakup hampir semuanya."
eyebrow: api
last_updated: 2026-11-07
---

Wokku itu API-first: setiap aksi di dashboard berjalan lewat [REST API](/docs/api/endpoints) yang sama dan bisa kamu panggil sendiri. [CLI](/docs/cli/commands) dan [Claude Code](/docs/mcp/tools) dibangun di atas API itu, jadi keduanya bisa melakukan hampir semua yang bisa dilakukan dashboard. [App iPhone](https://apps.apple.com/app/wokku/id6826866287) dan [app menu bar Mac](https://apps.apple.com/app/wokku/id6826866287?platform=mac) dibuat untuk on call: cek status, baca log, restart, rollback, dan menangani insiden.

✅ tersedia · — tidak tersedia

## App

| Yang bisa kamu lakukan | Dashboard | API | CLI | Claude Code | iOS |
|---|---|---|---|---|---|
| Daftar app dan lihat status | ✅ | ✅ | ✅ | ✅ | ✅ |
| Buat, ganti nama, clone, transfer, lock, atau hapus app | ✅ | ✅ | ✅ | ✅ | — |
| Environment variable | ✅ | ✅ | ✅ | ✅ | — |
| Domain dan SSL | ✅ | ✅ | ✅ | ✅ | — |
| HTTPS, CDN, dan maintenance mode | ✅ | ✅ | ✅ | ✅ | — |
| Auto-deploy GitHub dan preview app | ✅ | ✅ | ✅ | ✅ | — |
| Lihat health check | ✅ | ✅ | ✅ | ✅ | — |
| Scheduled task | ✅ | ✅ | ✅ | ✅ | — |
| Command sekali jalan dan terminal | ✅ | ✅ | ✅ | ✅ | — |

## Menjalankan app

| Yang bisa kamu lakukan | Dashboard | API | CLI | Claude Code | iOS |
|---|---|---|---|---|---|
| Start, stop, dan restart | ✅ | ✅ | ✅ | ✅ | ✅ |
| Scale proses | ✅ | ✅ | ✅ | ✅ | ✅ |
| Resize (CPU dan RAM) | ✅ | ✅ | ✅ | ✅ | — |
| Log | ✅ | ✅ | ✅ | ✅ | ✅ |
| Riwayat deploy dan release | ✅ | ✅ | ✅ | ✅ | ✅ |
| Rollback release | ✅ | ✅ | ✅ | ✅ | ✅ |
| Deploy atau redeploy | ✅ | ✅ | ✅ | ✅ | ✅ |
| Metrik dan feed aktivitas | ✅ | ✅ | ✅ | ✅ | — |
| Insiden | ✅ | ✅ | ✅ | ✅ | ✅ |
| Mute alert | ✅ | ✅ | ✅ | ✅ | ✅ |
| Diagnosis AI | ✅ | ✅ | ✅ | ✅ | — |
| Doctor (self-check) | — | ✅ | ✅ | ✅ | — |

## Database

| Yang bisa kamu lakukan | Dashboard | API | CLI | Claude Code | iOS |
|---|---|---|---|---|---|
| Buat, hubungkan, putuskan, dan hapus database | ✅ | ✅ | ✅ | ✅ | — |
| Add-on shared gratis dan upgrade ke dedicated | ✅ | ✅ | ✅ | ✅ | — |
| Monitor database | ✅ | ✅ | ✅ | ✅ | — |
| Import dump | ✅ | ✅ | ✅ | ✅ | — |
| Backup: buat, download, restore | ✅ | ✅ | ✅ | ✅ | — |

## Akun dan tim

| Yang bisa kamu lakukan | Dashboard | API | CLI | Claude Code | iOS |
|---|---|---|---|---|---|
| API token dan SSH key | ✅ | ✅ | ✅ | ✅ | — |
| Tim dan anggota | ✅ | ✅ | ✅ | ✅ | — |
| Channel notifikasi | ✅ | ✅ | ✅ | ✅ | — |
| Push alert di HP | — | ✅ | — | — | ✅ |
| Template satu klik | ✅ | ✅ | ✅ | ✅ | — |
| Plan saat ini | ✅ | ✅ | ✅ | ✅ | — |
| Top up saldo | ✅ | ✅ | — | — | — |

## Development lokal

| Yang bisa kamu lakukan | Dashboard | API | CLI | Claude Code | iOS |
|---|---|---|---|---|---|
| Tunnel (bagikan port lokal) | ✅ | ✅ | ✅ | — | — |
| Sesi dev (kode lokal, env production) | — | ✅ | ✅ | — | — |

Tunnel dan sesi dev butuh proses yang jalan di mesinmu, jadi fiturnya ada di CLI, bukan di Claude Code. Pembayaran selalu diselesaikan di browser.
