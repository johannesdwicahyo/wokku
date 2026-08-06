---
title: Audit Log
summary: "Siapa ngapain, dari mana, kapan. Tiap plan dapat audit log — Free pun include. Filter, export CSV, tamper-evidence via chain digest harian."
eyebrow: monitoring
last_updated: 2026-05-29
---

# Audit Log

Audit log record **tiap action penting** yang dilakuin di workspace — app dibikin, config diubah, deploy dimulai, member ditambah, plan di-switch — dengan actor, target, dan channel (Dashboard / CLI / API / MCP / git push / webhook).

Tersedia di **tiap plan, termasuk Free**. Bisa diakses di `/dashboard/activities` atau via sidebar workspace.

## Apa yang di-record

Tiap record punya:

— **Actor** — user yang ngelakuin (atau system, buat job kayak daily-debit)
— **Action** — di-namespace kayak `app.deployed`, `config.updated`, `team.member_added`
— **Target** — apa yang di-aksi (nama app, nama database, dll.)
— **Channel** — Dashboard / CLI / API / MCP / git_push / webhook
— **Timestamp** — sampai detik
— **Metadata** — JSON blob dengan context spesifik action

List lengkap action code ada di `Activity::ACTIONS` — cover lifecycle app, config, domain, SSH key, database, server, backup, integrasi GitHub, template, notification, membership team, dan event billing.

## Filter

Page nerima lima dropdown filter:

— **Action** — tiap namespace action distinct, alphabetical
— **Channel** — Dashboard / CLI / API / MCP / git push / Webhook
— **User** — tiap member workspace
— **Since** — input tanggal (awal hari)
— **Until** — input tanggal (akhir hari)

Semua filter AND. URL param survive refresh jadi view yang di-filter bisa di-share.

## Export CSV

Pakai link **export CSV** di kanan-atas audit log buat download set yang di-filter. Kolom:

```text
created_at, user_email, action, target_type, target_name, channel, metadata_json
```

Berguna buat report compliance, attach ke postmortem incident security, atau workflow bulk-grep.

## Tamper evidence

Tiap malam, job `ActivityDigest` hash activity hari itu jadi chain (`chain_hash = SHA256(prev_hash || min_id || max_id || row_count || row_hashes)`) dan persist satu row per hari. Page audit log nampilin banner **verified** hijau dengan tanggal digest terbaru, row count, dan 16 char awal chain hash:

```text
[verified] // chain hash verified through 2026-05-28 · 1.247 rows · hash a3f4b8…
```

Kalau job digest belum jalan (install baru), kamu dapat banner pending:

```text
// digest chain not yet built — ActivityDigestJob runs nightly
```

Chain nggak ngebuktiin row nggak *hilang* dari digest sebelumnya; dia ngebuktiin **row yang kamu liat nggak diubah** sejak digest landed. Buat audit row hilang, compare total `row_count` digest berturut sama baseline yang kamu expect.

## Pill channel

Tiap record nampilin pill kecil yang nunjukin action datang dari mana:

— **Dashboard** — session browser
— **API** — call dengan REST API token
— **CLI** — command `wokku <cmd>`
— **MCP** — invocation plugin Claude Code
— **git push** — hook deploy-via-push
— **Webhook** — auto-deploy GitHub atau webhook lain

Berguna buat narrow "apa yang `terraform-bot` API token lakuin hari ini" atau "apa yang siapa aja lakuin via CLI minggu lalu".

## API

```bash
curl https://wokku.cloud/api/v1/activities \
  -H "Authorization: Bearer $TOKEN" \
  -G --data-urlencode "action_eq=app.deployed" \
     --data-urlencode "since=2026-05-01"
```

Return shape JSON yang sama dengan yang dashboard render.

## Retensi

Retensi audit log **unlimited** — kita nggak pernah auto-delete record. Audit log kecil (puluhan KB per workspace per bulan), dan value audit retroaktif jauh lebih besar dari biaya storage.

Kalau butuh purge buat alasan compliance (GDPR right-to-be-forgotten di member yang di-remove), email [support@wokku.cloud](mailto:support@wokku.cloud).

## Self-hosted

Community Edition include tabel + page audit log. `ActivityDigestJob` butuh config recurring-jobs di `config/recurring.yml`; tanpa itu chain nggak ke-bangun otomatis.

## Lihat juga

— [Log](/docs/monitoring/logs) — log container runtime (surface beda)
— [Member & Role](/docs/teams/members) — event membership workspace muncul di sini
