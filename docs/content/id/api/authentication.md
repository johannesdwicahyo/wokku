---
title: Autentikasi API
summary: Buat API token dan kirim sebagai header Bearer di setiap request.
eyebrow: api
last_updated: 2026-11-07
---

Ambil API token, lalu kirim di header `Authorization` pada setiap request ke `https://wokku.cloud/api/v1`.

## Buat token

:::tabs
::web-ui
1. Buka **Profile** di dashboard.
2. Di bagian **API Tokens**, isi nama lalu buat token.
3. Salin sekarang — token hanya ditampilkan sekali.
::cli
```bash
wokku tokens:create ci
```
Token hanya dicetak sekali. Salin sekarang.
::api
Dengan token yang sudah ada:

```bash
curl -X POST https://wokku.cloud/api/v1/auth/tokens \
  -H "Authorization: Bearer $WOKKU_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "ci"}'
```

```json
{"id": "…", "token": "…", "name": "ci"}
```

Tambahkan `"expires_at"` (waktu ISO 8601) supaya token kedaluwarsa.
::mcp
*"Create a Wokku API token called ci"*
:::

## Pakai token

```bash
curl https://wokku.cloud/api/v1/apps \
  -H "Authorization: Bearer $WOKKU_API_TOKEN"
```

Cek token ini milik siapa:

```bash
curl https://wokku.cloud/api/v1/auth/whoami \
  -H "Authorization: Bearer $WOKKU_API_TOKEN"
```

Token bisa melakukan apa pun yang bisa dilakukan user-nya, di setiap tim tempat user itu bergabung.

## Sign in tool lewat browser (device flow)

Kalau kamu membuat tool yang jalan di mesin orang lain, biarkan mereka menyetujuinya di browser alih-alih menempel token. Begini cara kerja `wokku auth:login`.

1. Minta kode:
   ```bash
   curl -X POST https://wokku.cloud/api/v1/auth/device/code
   ```
   Response-nya berisi `device_code`, `user_code`, link `verification_uri_complete`, `expires_in`, dan `interval` (detik).
2. Tampilkan link dan kode ke user. Mereka membukanya, sign in, lalu menyetujui.
3. Poll setiap `interval` detik:
   ```bash
   curl -X POST https://wokku.cloud/api/v1/auth/device/token \
     -H "Content-Type: application/json" \
     -d '{"device_code": "…"}'
   ```
   Selama menunggu kamu akan dapat `{"error": "authorization_pending"}`. Setelah disetujui kamu dapat `{"token": "…", "user": {…}}` — hanya saat ini token dikembalikan. `slow_down` artinya poll lebih jarang; `access_denied` atau `expired_token` artinya mulai lagi dari awal.

## Cabut token

:::tabs
::web-ui
**Profile → API Tokens**, lalu cabut token-nya.
::cli
```bash
wokku tokens            # find the ID
wokku tokens:revoke TOKEN_ID
```
::api
```bash
curl -X DELETE https://wokku.cloud/api/v1/auth/tokens/TOKEN_ID \
  -H "Authorization: Bearer $WOKKU_API_TOKEN"
```
::mcp
*"Revoke my Wokku API token called ci"*
:::

Apa pun yang memakai token yang sudah dicabut langsung berhenti bekerja.

## Error dan batasan

Request yang gagal mengembalikan JSON dengan satu format:

```json
{"error": "Invalid or expired token", "error_code": "invalid_token", "hint": "…", "retryable": false}
```

Request dibatasi 60 per menit per alamat IP.

## Selanjutnya

- [Endpoint](/docs/api/endpoints)
- Referensi lengkap: [`/api/v1/openapi.yaml`](https://wokku.cloud/api/v1/openapi.yaml)
