---
title: SSH Keys
summary: Tambahkan SSH public key kamu supaya git push bisa deploy, dan pakai key terpisah kalau kamu push ke lebih dari satu akun Wokku.
last_updated: 2026-11-07
---

Kamu akan menambahkan public key supaya `git push wokku main` sampai ke app kamu. Cukup sekali per mesin, sebelum push pertama.

## Tambahkan key

Belum punya key? Buat dengan `ssh-keygen -t ed25519`. Perintah itu membuat `~/.ssh/id_ed25519` (private) dan `~/.ssh/id_ed25519.pub` (public).

:::tabs
::web-ui
Buka **Settings → SSH Keys** dan tempel isi dari `~/.ssh/id_ed25519.pub`.

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
Minta ke Claude: *"Tambahkan SSH public key saya dari ~/.ssh/id_ed25519.pub ke Wokku dengan nama laptop."*
:::

Lalu push seperti biasa:

```bash
git remote add wokku git@git.wokku.cloud:my-app
git push wokku main
```

## Satu key, satu akun

Setiap SSH key hanya bisa dimiliki satu akun Wokku. Server git memakai key itu untuk menentukan app milik siapa yang sedang kamu push. Kalau sebuah key sudah terdaftar di akun mana pun, upload ulang key itu akan ditolak.

## Push ke beberapa akun dari satu mesin

Misalnya kamu punya akun utama dan akun test. Beri akun kedua key sendiri, lalu beri tahu SSH key mana yang dipakai untuk akun mana.

### 1. Buat key kedua

```bash
ssh-keygen -t ed25519 -f ~/.ssh/wokku_test -N "" -C "wokku-test"
```

### 2. Tambahkan ke akun kedua

Login ke akun kedua, buka **Settings → SSH Keys**, dan tempel isi dari `~/.ssh/wokku_test.pub`.

### 3. Tambahkan host alias ke `~/.ssh/config`

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

Jangan lewatkan `IdentitiesOnly yes`. Tanpa itu, SSH menawarkan semua key di agent kamu, dan key pertama yang dikenali Wokku yang menang. Biasanya itu key akun utama kamu.

### 4. Arahkan tiap repo ke alias-nya

```bash
# in a repo whose app belongs to the main account
git remote set-url wokku git@wokku-main:my-app

# in a repo whose app belongs to the test account
git remote set-url wokku git@wokku-test:my-app
```

### Cek

```bash
git ls-remote wokku
```

Kalau berjalan tanpa error, key-nya diterima untuk app tersebut. Kalau kamu dapat `access denied`, remote-nya memakai key akun yang lain. Cek `IdentitiesOnly yes` dan path `IdentityFile`.

## Hapus key

Hapus di **Settings → SSH Keys**, atau jalankan `wokku ssh-keys:remove laptop`. Key yang dihapus langsung tidak bisa dipakai untuk push baru.
