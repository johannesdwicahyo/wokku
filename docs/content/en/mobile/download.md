---
title: iOS & Mac App
summary: The Wokku app for iPhone and the Mac menu bar — check your apps, read logs, fix things and get alerts while away from your desk.
eyebrow: mobile
last_updated: 2026-11-14
---

Use the Wokku app to stay on call for your apps from your iPhone or Mac menu bar.

**[Download Wokku for iPhone on the App Store](https://apps.apple.com/app/wokku/id6826866287)**

**[Download Wokku for Mac on the Mac App Store](https://apps.apple.com/app/wokku/id6826866287?platform=mac)**

## Requirements

| Platform | Minimum |
|---|---|
| iPhone | iOS 17 |
| Mac (menu bar app) | macOS 14 |

Sign in with Apple, with your email, or with **Continue with wokku.cloud**.

## On iPhone

The app has four tabs: **Apps**, **Incidents**, **Databases** and **Settings**.

- **Apps** — see each app's status, then restart, stop, start or scale it. From the **⋯** menu you can redeploy, turn maintenance mode on or off, and lock or unlock deploys.
- **Deploys and releases** — open a deploy to read its log, or roll back to an earlier release.
- **Logs** — read and live-stream an app's logs.
- **Config** — view environment variables (read-only; values are hidden if you are a viewer on the team).
- **Incidents** — see which apps are down and when they recovered.
- **Databases** — check a database's status and back it up now.

To change config, domains, databases or billing, use the [dashboard](https://wokku.cloud/dashboard), the [CLI](/docs/cli/commands) or [Claude Code](/docs/mcp/tools).

## On Mac

The Mac app lives in your menu bar and shows your apps' health at a glance. It refreshes every minute and when an alert arrives, and shows the last known status if you go offline.

From the menu you can open an app's logs, start, stop or restart it, and see open incidents. **Open dashboard** takes you to wokku.cloud.

## Push alerts

The first time you sign in, tap **Turn on notifications** and allow them. If you said no earlier, go to **Settings → Notifications → Open Settings** and allow them in iOS Settings.

You get an alert when:

| Alert | When |
|---|---|
| App down | An app stops responding |
| App recovered | It is back up |
| App crashed | An app's process crashes |
| Deploy failed | A deploy did not finish |
| Backup failed | A database backup did not finish |

Tap an alert to open the app it is about.

### Mute alerts

To pause alerts for a while, go to **Settings → Alert mutes → Add mute…**:

1. Pick an app, an alert type, or both.
2. Pick how long: **1 hour**, **8 hours**, **1 day** or **Indefinitely**.
3. Tap **Add**.

To remove a mute, long-press it and tap **Delete**. Mutes only affect phone alerts — email and other [notification channels](/docs/monitoring/notifications) keep working. You can also mute from the CLI with `wokku alerts:mute`.

## Delete your account

**Settings → Delete account…** (on Mac, in the menu). Type your email to confirm.
