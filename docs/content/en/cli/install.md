---
title: CLI Installation
summary: "Install the Wokku CLI to drive apps from the terminal. Cloud-only — the OSS edition ships the web UI only."
eyebrow: cli
last_updated: 2026-05-29
---

# Installation

Install the Wokku CLI to manage apps from your terminal.

:::callout warn
The CLI is a **Wokku Cloud** feature. The open-source edition is web UI only — see [Open Source Edition](/docs/oss/overview) for the full surface comparison.
:::

## Homebrew (recommended — macOS / Linux)

```bash
brew install johannesdwicahyo/tap/wokku
```

Homebrew handles `brew upgrade wokku` and `brew uninstall wokku` out of
the box, including Ruby as a dependency. This is the recommended path.

## Shell script (fallback)

For minimal environments without Homebrew:

```bash
curl -sL https://wokku.cloud/cli/install.sh | bash
```

Downloads the standalone CLI to `/usr/local/bin/wokku`. Requires Ruby
3.1+ already installed on the system.

## Login

```bash
wokku auth:login
```

Opens your browser for authentication. Session is saved locally.

## Verify

```bash
wokku apps
```

## Update

```bash
# Homebrew
brew upgrade wokku

# Shell script
curl -sL https://wokku.cloud/cli/install.sh | bash
```

## Uninstall

```bash
# Homebrew
brew uninstall wokku

# Shell script
sudo rm /usr/local/bin/wokku
```
