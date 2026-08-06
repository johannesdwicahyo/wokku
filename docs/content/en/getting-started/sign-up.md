---
title: Sign Up
summary: "Create your Wokku account and land on your dashboard ready to deploy. Sign in with GitHub, Google, or email — all three end up in the same account."
eyebrow: getting started
last_updated: 2026-05-29
---

# Sign Up

Create your Wokku account to start deploying apps in minutes. You can sign up through any of the channels below.

## Create Your Account

:::tabs
::web-ui

Visit [wokku.cloud](https://wokku.cloud) and click **Get Started**. You can sign up with:

- **GitHub** — recommended for developers, enables one-click repo connections
- **Google** — sign in with your Google workspace or personal account
- **Email & password** — classic registration with email verification

After signing up, you'll land on your dashboard ready to deploy your first app.

::cli

Install the Wokku CLI and run the signup command:

```bash
# Install via Homebrew
brew install johannesdwicahyo/tap/wokku

# Sign up for a new account
wokku auth:signup
```

This opens your browser to complete registration, then stores your API token locally.

::api

Create an account by calling the signup endpoint:

```bash
curl -X POST https://wokku.cloud/api/v1/auth/signup \
  -H "Content-Type: application/json" \
  -d '{
    "email": "you@example.com",
    "password": "your-secure-password"
  }'
```

You'll receive an API token in the response:

```json
{
  "token": "wk_live_abc123...",
  "user": { "email": "you@example.com" }
}
```

::mcp

First sign up at [wokku.cloud](https://wokku.cloud), then install the Claude Code plugin:

```bash
claude plugin marketplace add johannesdwicahyo/wokku-plugin
claude plugin install wokku@wokku
```

You'll be prompted for your API token (create one at **Settings → API Tokens** in the dashboard). Restart Claude Code, then ask:

> "List my Wokku apps"

See [Claude Code Setup](/docs/mcp/setup) for the full guide.

::mobile

Download the Wokku app from the App Store or Google Play:

- [App Store](https://apps.apple.com/app/wokku)
- [Google Play](https://play.google.com/store/apps/details?id=dev.wokku.app)

Open the app, tap **Create Account**, and sign up with GitHub, Google, or email.
:::

## What's Next

Once you're signed up, you're ready to deploy. Head to [Your First Deploy](/docs/getting-started/first-deploy) to launch your first app.

## Two-Factor Authentication

We strongly recommend enabling 2FA on your account. Go to **Profile > Security** and follow the prompts to set up TOTP-based two-factor authentication with your authenticator app of choice.
