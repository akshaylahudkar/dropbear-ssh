# dropbear-ssh — project context

KPM package giving on-demand SSH/SFTP over WiFi to a jailbroken Kindle,
repackaging `notmarek/kindle-usbnetlite`'s dropbear binaries instead of
upstream's OTA/`mrpackages` installer (confirmed broken on modern
jailbreaks — depends on a no-longer-bundled `MRInstaller` extension).

Full user-facing details are in `README.md` — this file is for picking
Claude Code back up quickly in this repo, not a duplicate of the README.

## Layout

- `manifest.json` / `packages/dropbear-ssh/artifacts/*.kpkg` — the actual
  KPM repo index + built package, this is what `kpm add-repo` fetches.
- `source/` — the package source (`install.sh`, `launch.sh`,
  `uninstall.sh`, `manifest.json`, `bin_khf/`, `bin_11thgenplus/`) that
  gets packed into the `.kpkg`. **Edit here, then repack** — the files
  under `packages/` are a build artifact, not the source of truth.

## Non-obvious facts worth knowing before touching this again

- **Two bundled binaries, picked by kernel version.** `install.sh` checks
  `uname -r`: `4.1.*` → `bin_khf` (tested end-to-end on the dev's own PW4);
  anything else → `bin_11thgenplus` (same ELF arch/ABI, only confirmed to
  *execute* — a real connection test crashed mid-SSH-handshake on the
  tested kernel, so it's execute-verified only, not connection-verified).
- **`kpm` is never on `PATH`** — confirmed from KPM's own official
  `install.sh`. Use `/var/local/kmc/bin/kpm` from a terminal; the search
  bar's `;kpm` wiring resolves it internally, no full path needed there.
- **`uninstall.sh` must never `rm -rf` the shared base dir**
  (`/mnt/us/usbnetlite`) — an earlier version did, and it silently wiped
  `authorized_keys`/host keys/password on *every single upgrade* (KPM runs
  the old version's `uninstall.sh` before the new version's `install.sh`).
  Fixed to only remove the binaries it owns. If touching uninstall logic
  again, re-verify this doesn't regress — it's easy to reintroduce.
- **Password**: random per-install, written to
  `/mnt/us/usbnetlite/etc/ssh_password`, only regenerated if that file is
  missing. Can be preset via a `dropbear_password.txt` file at the Kindle
  drive's root before installing (USB or kterm) — the installer consumes
  and deletes it.
- **Port 2022, not 22 or 2222.** KOReader bundles its own dropbear on 2222;
  2022 avoids the collision.
- **`dropbear.nealing.net`** is a Cloudflare Worker
  (`/Users/apple/Documents/Projects/dropbear-ssh-worker.js`, source not in
  this repo) that proxies this repo's `manifest.json`/`.kpkg` from GitHub.
  It exists because the dev's home router specifically blocks/throttles
  their Kindle's traffic to GitHub's raw-content CDN IP range
  (`185.199.108-111.x`) — confirmed thoroughly (DNS/ping/routing/firewall
  all fine, works from their Mac on the same network, survives a full
  Kindle reboot, still fails). Not a bug in this package or in KPM.

## Testing

There's no CI. "Tested" in the README means actually installed/launched/
connected-to on the dev's real PW4 over SSH, verified live, not just
code-reviewed. If you change `install.sh`/`launch.sh`/`uninstall.sh`, the
real bar is: rebuild the `.kpkg`, get it onto the device, and confirm a
real `ssh` connection works — not just that the script reads correctly.

## Device access

`ssh kindle` (configured in `~/.ssh/config` on the dev's Mac) connects to
the dev's own test Kindle. Password auth also works if needed (password
lives in `/mnt/us/usbnetlite/etc/ssh_password` on the device). The Kindle
sleeps aggressively and suspends WiFi when asleep — a hung SSH connection
often just means it's asleep, not a real problem.
