# Deploy Phoenix (Elixir)

Deploy aplikasi Phoenix ke Wokku dengan Postgres dan migration Ecto saat release.

## Prasyarat

- [Akun Wokku](/docs/getting-started/sign-up) dan [server yang terhubung](/docs/getting-started/connect-server)
- [SSH key terdaftar](/docs/apps/ssh-keys) untuk `git push`
- Aplikasi Phoenix dengan `mix.exs`

## 1. Buat aplikasi

:::tabs
::web-ui
**Apps → New App** → server, nama `my-phoenix-app`, ukuran box, **Create**.

::cli
```bash
wokku apps:create my-phoenix-app --server my-server
```
:::

## 2. Siapkan aplikasi Phoenix-mu

Elixir buildpack mendeteksi `mix.exs`, mengambil deps, dan mem-build aset.
Tambahkan `Procfile`:

```procfile
web: mix phx.server
release: mix ecto.migrate
```

Di `config/runtime.exs`, baca port dan database dari environment:

```elixir
config :my_app, MyAppWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")],
  server: true
config :my_app, MyApp.Repo, url: System.get_env("DATABASE_URL")
```

## 3. Set environment variable

:::tabs
::web-ui
Aplikasi → **Config**:

| Key | Value |
|---|---|
| `SECRET_KEY_BASE` | output `mix phx.gen.secret` |
| `MIX_ENV` | `prod` |
| `PHX_HOST` | `my-phoenix-app.wokku.app` |

::cli
```bash
wokku config:set my-phoenix-app \
  SECRET_KEY_BASE="$(mix phx.gen.secret)" MIX_ENV=prod \
  PHX_HOST=my-phoenix-app.wokku.app
```
:::

## 4. Tambahkan database

```bash
wokku addons:create postgres my-phoenix-app
```

Wokku menyuntikkan `DATABASE_URL`; wire di `runtime.exs` (di atas). Lihat
[Buat & Link Database](/docs/databases/create-link).

## 5. Deploy

:::tabs
::web-ui
```bash
git remote add wokku git@git.wokku.cloud:my-phoenix-app
git push wokku main
```

::github
Hubungkan di **Apps → Connect GitHub** untuk push-to-deploy —
lihat [GitHub Auto-Deploy](/docs/apps/github-autodeploy).

::cli
```bash
git remote add wokku git@git.wokku.cloud:my-phoenix-app
git push wokku main
```
:::

Live di `https://my-phoenix-app.wokku.app`.

## Domain kustom

[Domain Kustom](/docs/domains-ssl/custom-domains) — sesuaikan `PHX_HOST` lalu deploy ulang.

## Troubleshooting

- **Endpoint tidak menyajikan** — set `server: true` di `runtime.exs` dan bind ke `{0,0,0,0}` + `$PORT`.
- **`SECRET_KEY_BASE` kosong** — generate dengan `mix phx.gen.secret` lalu set.
- **Migration tidak jalan** — pastikan baris `release:`; cek deploy logs.

## Langkah berikutnya

- [Logs](/docs/apps/logs) · [Kesiapan Production](/docs/apps/best-practices)
