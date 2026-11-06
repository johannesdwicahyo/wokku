# Connect a Server

On **wokku.cloud** you don't connect servers — Wokku runs the hosts for you.

If you **self-host** the Community Edition, servers join your control plane through the Wokku host agent (`wokkud`):

1. Install Wokku on your first box with the one-command `install.sh` (it sets up the control plane and the app runtime on the same machine).
2. To add more servers later, open **Admin → Servers** in the dashboard and run the one-line install command it shows on the new machine.
3. The server registers itself and shows up under **Servers** with a status indicator (green = healthy).

See the [Open Source Edition](/docs/oss/overview) page for setup details.
