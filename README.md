# dropbear-ssh

On-demand SSH/SFTP access to a jailbroken Kindle over its existing WiFi
connection — a [KPM](https://github.com/KindleModding/KPM) package, nothing
to build, no USB cable required once it's installed.

## Install

Requires KPM (modern jailbreaks ship with it pre-installed). Two ways to
install:

**Option A — USB, no terminal needed (recommended for a first install):**

1. Download [`dropbear-ssh.sh`](dropbear-ssh.sh) from this repo.
2. Copy it onto the Kindle via USB, into the `documents` folder — same
   drag-and-drop as sideloading a book.
3. Eject, then tap **Dropbear SSH** on the Home screen/Library. If it
   doesn't show up immediately, reboot the Kindle — the file's there but
   the Home screen's content index doesn't always pick it up until the next
   rescan.

This one file is both the installer and the permanent launcher — the first
tap adds the repo, installs, and launches; every tap after that just
launches (re-affirming the install along the way, harmlessly). There's
nothing else to copy over later, and no separate entry gets added — this
stays the one icon for this package.

**Option B — `kterm` or any terminal over SSH**, useful if you already have
SSH access another way, or want to see real output instead of a silent tap.
If you don't have `kterm` yet, install it from the search bar first (no
`add-repo` needed — it's on KPM's official default repo):

```text
;kpm install kterm
```

Then open **Kterm** from the Home screen/Library and run:

```text
KPM=/var/local/kmc/bin/kpm
$KPM add-repo https://nealing.net/manifest.json
$KPM install dropbear-ssh
$KPM launch dropbear-ssh
```

(KPM's own installer never puts `kpm` on `PATH`, so the full path is
required here.)

This also adds the same Home-screen icon as Option A, if one doesn't
already exist — so future launches don't need `kterm` at all unless you
want it.

(`https://nealing.net/manifest.json` also has
[sysmon](https://github.com/akshaylahudkar/sysmon) — the old
`dropbear.nealing.net/manifest.json` URL still works too, it just redirects
here now.)

Launching (the `dropbear-ssh.sh` scriptlet or the kterm command) opens a
small status app showing whether the server is currently running, plus a
**Start Server** / **Stop Server** button — tap it to toggle. When running,
the screen shows your connect command with the Kindle's real IP and the
current password:

```
ssh -p 2022 root@<kindle-ip>
```

The button updates the same screen immediately, no need to relaunch —
it's backed by a small on-device HTTP bridge (`nc` + a shell handler
listening on loopback only, port `18022`) that the app's own button talks
to; nothing is exposed beyond `127.0.0.1`.

## Password

- **Default**: random, printed in the install log, always readable
  afterward at `/mnt/us/usbnetlite/etc/ssh_password` (via USB or `kterm`)
  even if you missed it on screen.
- **Pick your own before installing**: save a plain text file named
  `dropbear_password.txt` at the root of the Kindle's drive — drag-and-drop
  it on via USB the same way you'd sideload a book, or from `kterm`:
  `echo "yourpassword" > /mnt/us/dropbear_password.txt`. The installer uses
  it and deletes the staging file.
- **Change it later**: edit `/mnt/us/usbnetlite/etc/ssh_password`, then use
  the app's Stop/Start button to restart the server (a running server has
  already loaded the old password into memory, so editing the file alone
  won't take effect until it restarts).
- **Back to random**: delete that file instead of editing it — the next
  launch generates a fresh one automatically.

<details>
<summary><strong id="install-details">Install details</strong></summary>

- **KPM itself**: modern jailbreaks ship with it pre-installed — check for
  `/var/local/kmc/bin/kpm` via kterm, or just try Option A above and see if
  it works. If you're on an older jailbreak without it, see the
  [KPM project](https://github.com/KindleModding/KPM) for current install
  instructions (not duplicated here since they're liable to change).
- **What `nealing.net` is**: a Cloudflare Worker that transparently proxies
  this author's repos' `manifest.json`/`.kpkg` files straight from GitHub —
  shorter to type than the raw GitHub URL, and (confirmed on real hardware)
  it also routes around cases where a Kindle's network can reach Cloudflare
  but not GitHub's raw-content CDN directly. The full URL,
  `https://raw.githubusercontent.com/akshaylahudkar/dropbear-ssh/main/manifest.json`,
  still works too if you'd rather see exactly where you're pointing before
  typing a domain you don't recognize.
- **Official KPM repo**: working on getting this added there too, so
  eventually `kpm install dropbear-ssh` will work with no `add-repo` step
  at all — not there yet.
</details>

<details>
<summary><strong>Why not just use upstream's own installer?</strong></summary>

Two reasons:

1. **It doesn't actually work on a modern jailbreak out of the box.**
   Upstream's install method is the classic `;...mrpi` search-bar command,
   handled on current jailbreaks by `dispatch.sh` — which looks for a
   separate, no-longer-bundled extension at
   `/mnt/us/extensions/MRInstaller/bin/mrinstaller.sh`. Missing that file
   (confirmed missing on a modern KPM-based jailbreak), the command just
   flashes **"MRPI is not installed."** and does nothing. Modern jailbreaks
   ship KPM as the actual homebrew mechanism instead.
2. Even setting that aside, the OTA installer writes to rootfs (symlinks in
   `/usr/bin`, upstart jobs in `/etc/upstart`) and sets up USB-tethered
   networking most people with a Kindle already on WiFi don't need — neither
   of which a KPM hook package is allowed or needs to do.
</details>

<details>
<summary><strong>What's verified, what isn't</strong></summary>

Tested end-to-end (install via both the USB scriptlet and `kterm` → launch
→ real SSH session → survives an upgrade/downgrade/reinstall) on a
**Kindle PaperWhite 4, kernel `4.1.x`** (2018–2022-era hardware — Basic3,
Oasis3, Basic4, and Scribe also ship this kernel per upstream's own release
device list; **Paperwhite 5 does not** — see below, despite being on the
same upstream device list).

The package also bundles a second binary build (`bin_11thgenplus`) covering
upstream's broader device list — 2011-era Kindle Touch through 2024
PaperWhite 6 / Scribe 2 / ColorSoft — auto-selected by kernel version at
install time (`4.1.x` → the tested build; anything else → this one).

That second build is now **confirmed working end-to-end** (install → launch
→ real SSH session) on a **Kindle Paperwhite 5, kernel `4.9.77`**. It's
still only confirmed on that one device — an earlier test on a different,
unspecified device in this same kernel branch crashed with
`Connection reset by peer` during the SSH key exchange, so this path may
still be device-specific rather than universally working across the whole
11thgenplus device list. If it doesn't work for you outside the `4.1.x`
family, open an issue with your device model and `uname -r`.
</details>

<details>
<summary><strong>Security notes</strong></summary>

- The server only binds to the Kindle's WiFi interface — reachable by
  anything on the same network, not the internet, unless you've separately
  set up port forwarding.
- Stock firmware's `iptables` INPUT chain default-drops inbound connections;
  `bridge_handler.sh` re-opens the port each time the server is started via
  the button (runtime kernel state, not persisted).
- Auth is dropbear's compiled-in master-password mechanism, not real user
  accounts — anyone with the password gets a root shell. Treat it like the
  root password it is.
- The Start/Stop button talks to a small HTTP bridge (`nc` + a shell script)
  bound to `127.0.0.1:18022` only — not reachable from the network, only
  from processes running on the device itself. It has no auth of its own
  (anything local can toggle the server or read the password back), which
  is in line with this device's existing trust model — `lipc` itself is
  the same way — but worth knowing if you're thinking about the threat
  model closely.
- `source/` in this repo has the exact `install.sh`/`launch.sh`/
  `bridge_handler.sh`/`uninstall.sh` and binaries bundled in the `.kpkg` —
  worth a read before installing anything that gets you root over SSH.
</details>

<details>
<summary><strong>Credit / origin</strong></summary>

Repackages the `dropbearmulti`/`sftp-server` binaries from
[notmarek/kindle-usbnetlite](https://github.com/notmarek/kindle-usbnetlite)
as a KPM hook package. `bin_khf/` and `bin_11thgenplus/` are unmodified,
extracted from that project's own signed releases via `kindletool extract`
— not built from source here. All credit for the SSH server itself and the
Kindle-specific patches (`dropbear_be_cool.patch`, which the hardcoded paths
this package relies on come from) goes to
[notmarek](https://github.com/notmarek) and the kindle-usbnetlite
contributors, and to [Dropbear SSH](https://matt.ucc.asn.au/dropbear/dropbear.html)
by Matt Johnston underneath that.
</details>
