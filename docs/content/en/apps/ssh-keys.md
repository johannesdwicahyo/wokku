# SSH Keys & Multiple Accounts

Wokku identifies you at `git push` time by the SSH key you authenticate with. Add your public key under **Dashboard → Settings → SSH Keys**, then clone/push using:

```bash
git remote add wokku git@git.wokku.cloud:myapp.git
git push wokku main
```

## One key = one account

Each SSH key can belong to exactly one Wokku account. This is a safety property: the git gateway maps the presenting key to one account and sends the push there. If two accounts tried to share a key, pushes would silently land in the wrong tenant.

If you try to add a key that's already registered anywhere on wokku.cloud, the key upload is refused.

## Managing multiple accounts from one machine

Common case: you have a personal account and a test/team account and want to push to both from the same laptop. Instead of juggling one key, generate a second keypair and use SSH host aliasing.

### 1. Generate a second keypair

```bash
ssh-keygen -t ed25519 -f ~/.ssh/wokku_test -N "" -C "wokku-test"
```

This creates `~/.ssh/wokku_test` (private) and `~/.ssh/wokku_test.pub` (public).

### 2. Upload the new `.pub` to the second account

Sign in to your second account → **Settings → SSH Keys** → paste the contents of `~/.ssh/wokku_test.pub`.

### 3. Teach SSH which key goes with which account

Add this to `~/.ssh/config` (create the file if it doesn't exist):

```sshconfig
# Default (main) account — whatever key you normally use
Host wokku-main
  HostName git.wokku.cloud
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes

# Second account
Host wokku-test
  HostName git.wokku.cloud
  User git
  IdentityFile ~/.ssh/wokku_test
  IdentitiesOnly yes
```

`IdentitiesOnly yes` is important — without it, SSH will offer every key in your agent, and the gateway will accept the first one it recognises (usually your main account's key).

### 4. Point each repo's git remote at the matching alias

For an app on your main account:

```bash
git remote set-url wokku git@wokku-main:myapp.git
```

For an app on the test account:

```bash
git remote set-url wokku git@wokku-test:myapp.git
```

Now `git push wokku main` routes to the right tenant based on the host alias, and each account uses its own key.

### Verify

```bash
ssh -T git@wokku-main    # should greet you as your main-account user
ssh -T git@wokku-test    # should greet you as your test-account user
```

If both greet you as the same user, double-check `IdentitiesOnly yes` and the `IdentityFile` paths.

## Rotating or removing a key

Remove keys you no longer use from **Settings → SSH Keys**. A removed key stops working on new git pushes immediately; already-connected SSH sessions are not killed.
