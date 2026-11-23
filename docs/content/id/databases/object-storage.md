---
title: Object Storage
summary: Penyimpanan kompatibel S3 untuk upload dan file, dengan kredensial otomatis masuk ke app kamu sebagai environment variable.
last_updated: 2026-11-15
---

Object storage tersedia sebagai add-on app. Aktifkan di tab Resources app dan Wokku membuat bucket privat serta mengatur variabel koneksinya di app.

## Detail koneksi

| Pengaturan | Nilai |
|---|---|
| Endpoint | `https://s3.wokku.cloud` |
| Region | `us-east-1` |
| Addressing | **Path-style wajib** (`https://s3.wokku.cloud/<bucket>/<key>`) |

## Environment variable

App kamu menerima `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` dan `S3_FORCE_PATH_STYLE`. Untuk SDK yang membaca nama AWS standar, app juga menerima `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` dan `AWS_ENDPOINT_URL_S3`.

## Rails (Active Storage)

```yaml
# config/storage.yml
wokku:
  service: S3
  endpoint: <%= ENV["S3_ENDPOINT"] %>
  region: <%= ENV["S3_REGION"] %>
  bucket: <%= ENV["S3_BUCKET"] %>
  access_key_id: <%= ENV["S3_ACCESS_KEY_ID"] %>
  secret_access_key: <%= ENV["S3_SECRET_ACCESS_KEY"] %>
  force_path_style: true
  request_checksum_calculation: when_required
  response_checksum_validation: when_required
```

## Laravel

```php
// config/filesystems.php
's3' => [
    'driver' => 's3',
    'key' => env('S3_ACCESS_KEY_ID'),
    'secret' => env('S3_SECRET_ACCESS_KEY'),
    'region' => env('S3_REGION'),
    'bucket' => env('S3_BUCKET'),
    'endpoint' => env('S3_ENDPOINT'),
    'use_path_style_endpoint' => true,
],
```

## Node

```js
import { S3Client } from "@aws-sdk/client-s3";

const s3 = new S3Client({
  endpoint: process.env.S3_ENDPOINT,
  region: process.env.S3_REGION,
  forcePathStyle: true,
  credentials: {
    accessKeyId: process.env.S3_ACCESS_KEY_ID,
    secretAccessKey: process.env.S3_SECRET_ACCESS_KEY,
  },
});
```

## Python (boto3)

```python
import os, boto3
from botocore.config import Config

s3 = boto3.client(
    "s3",
    endpoint_url=os.environ["S3_ENDPOINT"],
    region_name=os.environ["S3_REGION"],
    aws_access_key_id=os.environ["S3_ACCESS_KEY_ID"],
    aws_secret_access_key=os.environ["S3_SECRET_ACCESS_KEY"],
    config=Config(s3={"addressing_style": "path"}),
)
```

## Harga dan kuota

- Setiap akun mendapat 1 GB gratis, dipakai bersama semua app-nya. Download gratis. Lihat paketmu untuk harga di atas itu.
- Di paket gratis, satu app per akun bisa memakai object storage, dengan kuota tetap 1 GB. Team berbayar default 10 GB, bisa diubah sampai 1024 GB.
- Kamu menerima email saat bucket mencapai 80% kuota.

## Backup

Bucket disalin ke luar lokasi setiap malam (terenkripsi).
