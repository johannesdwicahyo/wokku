---
title: SSH Keys
summary: Add your SSH public key so git push can deploy, and use separate keys when you push to more than one Wokku account.
last_updated: 2026-11-07
---

You'll add your public key so `git push wokku main` reaches your apps. You need it once per machine, before your first push.

## Add a key

No key yet? Create one with `ssh-keygen -t ed25519`. That makes `~/.ssh/id_ed25519` (private) and `~/.ssh/id_ed25519.pub` (public).

:::tabs
::web-ui
Go to **Settings → SSH Keys** and paste the contents of `~/.ssh/id_ed25519.pub`.

::cli
```bash
wokku ssh-keys:add --name laptop                       # uploads ~/.ssh/id_ed25519.pub
wokku ssh-keys:add ~/.ssh/work.pub --name work-laptop  # or pass another public key
wokku ssh-keys                                         # list your keys
```

::api
```bash
curl -X POST https://wokku.cloud/api/v1/ssh_keys \
  -H "Authorization: Bearer $WOKKU_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"laptop\", \"public_key\": \"$(cat ~/.ssh/id_ed25519.pub)\"}"
```

::mcp
Ask Claude: *"Add my SSH public key from ~/.ssh/id_ed25519.pub to Wokku as laptop."*
:::

Then push as usual:

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

## One key, one account

Each SSH key can belong to only one Wokku account. The git server uses the key to decide whose apps you're pushing to. If a key is already registered to any account, uploading it again is refused.

## Push to several accounts from one machine

Say you have a main account and a test account. Give the second account its own key and tell SSH which key to use for which account.

### 1. Make a second key

```bash
ssh-keygen -t ed25519 -f ~/.ssh/wokku_test -N "" -C "wokku-test"
```

### 2. Add it to the second account

Sign in to the second account, go to **Settings → SSH Keys**, and paste the contents of `~/.ssh/wokku_test.pub`.

### 3. Add host aliases to `~/.ssh/config`

```sshconfig
# Main account
Host wokku-main
  HostName git.wokku.cloud
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes

# Test account
Host wokku-test
  HostName git.wokku.cloud
  User git
  IdentityFile ~/.ssh/wokku_test
  IdentitiesOnly yes
```

Don't skip `IdentitiesOnly yes`. Without it, SSH offers every key in your agent, and the first one Wokku recognises wins. That's usually your main account's key.

### 4. Point each repo at its alias

```bash
# in a repo whose app belongs to the main account
git remote set-url wokku git@wokku-main:my-app

# in a repo whose app belongs to the test account
git remote set-url wokku git@wokku-test:my-app
```

### Check it

```bash
git ls-remote wokku
```

If it runs without an error, the key is accepted for that app. If you get `access denied`, the remote is using the other account's key. Check `IdentitiesOnly yes` and the `IdentityFile` paths.

## Remove a key

Delete it under **Settings → SSH Keys**, or run `wokku ssh-keys:remove laptop`. A removed key stops working for new pushes right away.
