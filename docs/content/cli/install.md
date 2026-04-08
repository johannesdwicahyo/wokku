# Installation

Install the Wokku CLI to manage apps from your terminal.

## Install

```bash
curl -sL https://wokku.dev/cli/install.sh | bash
```

Or install via RubyGems:

```bash
gem install wokku
```

## Login

```bash
wokku auth:login
```

This opens your browser for authentication. Once logged in, your session is saved locally.

## Verify

```bash
wokku apps
```

If you see your app list, you're all set.

## Update

```bash
gem update wokku
```

## Uninstall

```bash
gem uninstall wokku
```
