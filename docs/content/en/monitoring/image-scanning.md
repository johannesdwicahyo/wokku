---
title: Image Scanning
summary: Check the image of every deploy for known vulnerabilities, see the results in the app's Security panel, and turn it on for a self-hosted install.
last_updated: 2026-11-27
---

Image scanning looks for publicly known vulnerabilities (CVEs) in the operating-system packages and libraries inside your app's built image. You'll see the result on the app **Overview** and under **Settings → Security**.

## What it does and doesn't do

- It scans the **image layers** of the image that is running, using Trivy. It does not read your source code.
- It finds **known** issues only. "No known vulnerabilities in the image" means the scanner found nothing in its database — it is not a claim that your app is secure. It doesn't check your own code, your configuration or your secrets.
- A scan never blocks or fails a deploy. If a scan fails or times out, the deploy is unaffected and it is retried that night.

## Turn it on (self-host)

Image scanning is off by default. To enable it:

1. In a Rails initializer, set `c.image_scans = true` inside `Wokku.configure`.
2. On each host, add `WOKKUD_IMAGE_SCAN=1` to `/etc/wokkud/env` and restart wokkud.

You need both: with only the first, apps on a host without `WOKKUD_IMAGE_SCAN=1` stay at "Scanning…", because nothing on that host picks their scans up.

Optional caps for the scanner container: `WOKKUD_SCAN_MEMORY` (default `2g`), `WOKKUD_SCAN_PIDS` (`512`) and `WOKKUD_SCAN_CPUS` (`2`).

## Resources, disk and bandwidth

- One scan runs at a time per host, never while a build is running, and each scan times out after 5 minutes.
- The scanner runs in its own throwaway container with no network, a read-only filesystem and all capabilities dropped.
- Vulnerability databases live in the `wokku-trivy-cache` Docker volume. The main database refreshes daily; the Java database refreshes weekly and takes about 1 GB. Refreshing is the only step that uses the network.
- If the host's disk is 85% or more used, or has less free space than the image size plus 2 GiB, the scan fails with `disk_full` instead of filling the disk. A database refresh is skipped below 1 GiB free (4 GiB for the Java database) and tried again later.
- After each deploy the image is scanned, and every night images whose last scan is older than 20 hours are scanned again.

## Read the Security panel

The panel counts findings by severity: Critical, High, Medium, Low and Unknown, plus how many have a fix available. It also shows when the image was scanned and the Trivy version.

Click **View findings** for the list: severity, ID (CVE IDs link to the advisory), package, installed → fixed version and title. Use **Fixable only** to see what an update would resolve. The list shows the 50 most severe findings. Fixing usually means rebuilding on a newer base image or updating the package, then deploying again.
