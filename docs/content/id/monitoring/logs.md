---
title: Log
summary: Baca, cari, dan live-tail stdout dan stderr app kamu dari dashboard, CLI, API, atau Claude.
last_updated: 2026-11-07
---

Di sini kamu akan membaca log app kamu. Wokku mengumpulkan semua yang ditulis container kamu ke stdout dan stderr — print ke stdout dan hasilnya muncul di sini.

## Melihat log

:::tabs
::web-ui
Buka app kamu → **Runtime** → **Logs**.

- **Search** dan dropdown **level** mencari di riwayat yang tersimpan.
- **Live tail** mengalirkan baris baru begitu masuk; **follow** me-refresh tampilan secara otomatis.
- **Filter visible logs** dan pill Errors / Warnings mempersempit yang sudah tampil di layar.

::cli
```bash
wokku logs my-app              # last 100 lines
wokku logs my-app --lines 500  # last 500 lines
wokku logs my-app -f           # live tail (also --follow)
```

::api
```bash
curl -G https://wokku.cloud/api/v1/apps/my-app/logs \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode "lines=200" \
  --data-urlencode "level=error" \
  --data-urlencode "q=timeout"
```

| Param | Arti |
|---|---|
| `lines` | Jumlah baris, 1–1000 (default 100) |
| `since`, `until` | Waktu ISO 8601 (default: 24 jam terakhir) |
| `level` | `error`, `warn`, `info`, atau `debug` |
| `q` | Teks yang dicari |
| `follow=1` | Stream baris live sebagai plain text |

::mcp
Tanya Claude: *"Tampilkan 200 baris error terakhir untuk my-app."*
:::

## Level log

Setiap baris mendapat level berdasarkan kata di dalamnya:

| Level | Cocok dengan |
|---|---|
| error | `ERROR`, `FATAL`, `CRITICAL`, `exception`, `panic`, `traceback` |
| warn | `WARN`, `WARNING` |
| info | `INFO`, `NOTICE`, dan apa pun yang tidak cocok dengan yang lain |
| debug | `DEBUG`, `TRACE`, `VERBOSE` |

Pencocokan tidak peduli huruf besar/kecil, jadi baris JSON seperti `{"level":"error",...}` dihitung sebagai error.

## Batasan

- Baris di atas 16 KB dipotong jadi 16 KB.
- Output build tidak ada di sini — baca di deploy-nya pada tab **Deploy**.
- Log disimpan dalam jangka waktu terbatas. Kirim apa pun yang harus kamu simpan jangka panjang dari app kamu ke layanan log milikmu sendiri.
- Tidak ada log drain. Untuk meneruskan log, kirim dari app kamu.

## Lihat juga

- [Metrics](/docs/monitoring/metrics) — CPU, memory, request, dan Web Vitals
- [Audit log](/docs/monitoring/audit-log) — siapa mengubah apa di workspace kamu
