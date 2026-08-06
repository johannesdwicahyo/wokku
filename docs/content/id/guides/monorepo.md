# Deploy dari Monorepo

Aplikasimu ada di subdirektori (`apps/api`, `packages/web`) dari repo besar.
Berikut cara men-deploy hanya subtree itu ke sebuah aplikasi Wokku.

## Opsi A — push subtree (bekerja di mana saja)

`git subtree` mengirim hanya satu subdirektori sebagai root repo dari push-mu.
Tanpa config server.

```bash
# dari root repo, push apps/api ke branch main aplikasi Wokku
git subtree push --prefix apps/api wokku main
```

Jika history membuat `subtree push` lambat atau menolak non-fast-forward, split
dulu lalu force branch-nya:

```bash
git subtree split --prefix apps/api -b deploy-api
git push wokku deploy-api:main --force
```

`Procfile`, `Dockerfile`, dan manifest dependency-mu harus berada di root
subdirektori itu (`apps/api/Procfile`, dst.) — setelah subtree split, itu menjadi
root repo yang dilihat Wokku.

## Opsi B — build dari subdirektori (GitHub auto-deploy)

Saat deploy via [GitHub Auto-Deploy](/docs/apps/github-autodeploy), set **build
directory** supaya Wokku build dari subfolder-mu di tiap push:

:::tabs
::web-ui
Aplikasi → **Settings** → set **Build directory** ke `apps/api`.

::cli
```bash
wokku config:set my-api BUILD_DIR=apps/api
```
:::

Tiap push ke branch terhubung mem-build `apps/api` dan men-deploy-nya — tanpa
ribet subtree.

## Banyak aplikasi dari satu repo

Buat satu aplikasi Wokku per deployable, masing-masing diarahkan ke subdirektorinya:

```bash
wokku apps:create my-api --server my-server     # build dir apps/api
wokku apps:create my-web --server my-server     # build dir apps/web
```

## Troubleshooting

- **"Updates were rejected"** saat subtree push — pakai bentuk split + `--force` di atas.
- **Buildpack mendeteksi bahasa yang salah** — pastikan manifest (`package.json`, dst.) ada di root subtree/build-dir.
- **Shared package tidak ketemu** — `git subtree` push hanya membawa subfolder; vendor kode bersama ke build dir atau pakai Dockerfile yang meng-copy yang dibutuhkan.

## Langkah berikutnya

- [Deploy dengan Dockerfile](/docs/guides/dockerfile) · [GitHub Auto-Deploy](/docs/apps/github-autodeploy)
