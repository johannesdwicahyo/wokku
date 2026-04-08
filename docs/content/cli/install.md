# Installation

Install the Wokku CLI to manage apps from your terminal.

## Install

### Homebrew (macOS / Linux)

```bash
brew install johannesdwicahyo/tap/wokku
```

### Shell script

```bash
curl -sL https://wokku.dev/cli/install.sh | bash
```

This downloads the standalone CLI to `/usr/local/bin/wokku`.

### RubyGems

```bash
gem install wokku-cli
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
# Homebrew
brew upgrade wokku

# Shell script
curl -sL https://wokku.dev/cli/install.sh | bash

# RubyGems
gem update wokku-cli
```

## Uninstall

```bash
# Homebrew
brew uninstall wokku

# Shell script
sudo rm /usr/local/bin/wokku

# RubyGems
gem uninstall wokku-cli
```
