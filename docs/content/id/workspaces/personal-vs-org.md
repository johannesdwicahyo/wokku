---
title: Workspace
summary: Workspace personal kamu, workspace org untuk kerja bersama, dan cara berpindah di antaranya.
last_updated: 2026-11-07
---

Semua yang kamu buat di Wokku — app, database, domain, audit log — dimiliki oleh sebuah **workspace**. Halaman ini menjelaskan dua jenisnya dan cara berpindah di antaranya.

## Workspace personal dan org

| | Personal | Org |
|---|---|---|
| Siapa yang dapat | Setiap akun, saat sign-up | Kamu buat sendiri saat butuh |
| Member | Hanya kamu | Kamu plus siapa pun yang kamu tambahkan |
| Bisa ditinggalkan atau dihapus | Tidak — terikat ke akun kamu | Kamu pemiliknya; pemilik tidak bisa dikeluarkan |
| Berapa banyak | Satu | Sebanyak yang kamu mau |

Pakai workspace personal untuk project kamu sendiri. Buat workspace org untuk kerja bersama — startup, klien, co-founder.

## Berpindah workspace

Workspace switcher ada di bagian atas sidebar.

1. Klik nama workspace.
2. Pilih workspace lain dari daftar.

Dashboard akan reload dengan app, database, billing, dan audit log workspace tersebut. Pilihan ini tetap tersimpan sampai kamu pindah lagi. Login, 2FA, profil, SSH key, dan API token kamu sama di setiap workspace.

**Manage →** di switcher membuka daftar lengkap workspace yang kamu ikuti.

## Membuat workspace org

1. Buka switcher di sidebar → **+ New workspace**.
2. Masukkan nama (nama harus unik di seluruh Wokku).
3. Pilih plan dan konfirmasi.

Kamu langsung dipindahkan ke workspace baru, sebagai pemilik sekaligus admin.

:::callout note
Form pembuatan hanya menawarkan **Solo**, **Pro**, atau **Team**. Plan yang kamu pilih menentukan berapa banyak member yang bisa ditampung workspace: Team tidak punya batas member, Solo dan Pro menampung satu. Halaman workspace menampilkan seat yang terpakai dan yang termasuk.
:::

## Siapa yang bayar

Setiap workspace punya batas billing sendiri. Resource yang dibuat di dalam workspace org ditagihkan ke workspace tersebut, bukan ke member yang membuatnya. Lihat [Harga](/docs/billing/pricing).

## CLI, API, dan MCP

Token milik kamu, bukan milik workspace. Perintah listing (`wokku apps`, `GET /api/v1/apps`) mengembalikan semua yang bisa kamu akses di semua workspace kamu.

Membuat app dari CLI, API, atau MCP akan menaruhnya di workspace default kamu — kamu belum bisa memilih workspace org dari sana. Untuk membuat app di workspace org, pindah ke workspace itu di dashboard dan buat app-nya di sana.

`wokku teams` menampilkan daftar workspace yang kamu ikuti, beserta ID-nya.

## Lihat juga

- [Member & Role](/docs/teams/members) — tambahkan orang dan atur apa yang bisa mereka lakukan
- [Audit log](/docs/monitoring/audit-log) — apa yang terjadi di sebuah workspace
