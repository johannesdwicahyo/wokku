---
title: Object Storage
summary: S3-compatible storage for uploads and files, with credentials injected into your app as environment variables.
last_updated: 2026-11-15
---

Object storage is available as an app add-on. Enable it on an app's Resources tab and Wokku creates a private bucket and sets the connection variables on the app.

## Connection details

| Setting | Value |
|---|---|
| Endpoint | `https://s3.wokku.cloud` |
| Region | `us-east-1` |
| Addressing | **Path-style is required** (`https://s3.wokku.cloud/<bucket>/<key>`) |

## Environment variables

Your app receives `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` and `S3_FORCE_PATH_STYLE`. For SDKs that read the standard AWS names it also gets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` and `AWS_ENDPOINT_URL_S3`.

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

## Pricing and quota

- Rp 400 per GB per month, after 1 GB free per team. Downloads are free.
- Free teams have a fixed 1 GB quota. Paid teams default to a 10 GB cap, which you can change up to 1024 GB.
- You get an email when a bucket reaches 80% of its quota.

## Backups

Buckets are copied off-site nightly (encrypted).
