# dropbear-ssh

A [KPM](https://github.com/KindleModding/KPM) package that gives you on-demand
SSH/SFTP access to a jailbroken Kindle over its existing WiFi connection — no
USB networking, no rebuilding anything from source. It's a repackaging of the
`dropbearmulti`/`sftp-server` binaries from
[notmarek/kindle-usbnetlite](https://github.com/notmarek/kindle-usbnetlite)
(themselves built on [Dropbear SSH](https://matt.ucc.asn.au/dropbear/dropbear.html)
by Matt Johnston, with Kindle-specific patches from that project), wrapped as
a KPM hook package instead of that project's original OTA/`mrpackages`
installer, since the OTA installer writes to rootfs (symlinks in `/usr/bin`)
and sets up USB-tethered networking that most people with a Kindle already on
WiFi don't need.

All credit for the actual SSH server and the Kindle-specific patches
(`dropbear_be_cool.patch` — the hardcoded paths this package relies on) goes
to [notmarek](https://github.com/notmarek) and the
[kindle-usbnetlite](https://github.com/notmarek/kindle-usbnetlite)
contributors. This repo only repackages their compiled release binaries as a
KPM hook package.

## Prerequisites

You need [KPM](https://github.com/KindleModding/KPM), the
[Kindle Package Manager](https://kindlemodding.org/kindle-dev/kpm/index.html),
already on the device. **Modern Kindle jailbreaks ship with KPM pre-installed**
— if you jailbroke recently following
[KindleModding's guide](https://kindlemodding.org/jailbreaking/), you almost
certainly already have it; try `;kpm update` from the search bar to check.
If you're on an older jailbreak without it, see the
[KPM project page](https://github.com/KindleModding/KPM) for current install
instructions — this README won't duplicate those, since they're liable to
change and KPM's own docs are the source of truth.

## Install

From the Kindle's search bar, or (recommended — see the password note below)
a terminal like [kterm](https://kindlemodding.org):

```
kpm add-repo https://raw.githubusercontent.com/akshaylahudkar/dropbear-ssh/main/manifest.json
kpm update
kpm install dropbear-ssh
kpm launch dropbear-ssh
```

`kpm launch` prints the exact command to connect with, using the Kindle's
actual WiFi IP:

```
ssh -p 2022 root@<kindle-ip>
```

### About the password

By default, a random password is generated the first time you install, and
printed in the install log — no setup needed, just read it off the log (see
"seeing the password" below) and connect.

**How reliably you actually see that install-log output depends on how you
ran the install:**

- **Search bar** (`;kpm install dropbear-ssh`): the output is shown via a
  transient on-screen overlay that the next screen refresh wipes out —
  in practice this can flash and vanish before you can read it. (This isn't
  theoretical — it's the exact failure mode hit while building this package.)
- **kterm or any real terminal**: output stays on screen / scrolls normally,
  fully readable.

Either way, the password is always saved in plain text at
`/mnt/us/usbnetlite/etc/ssh_password` — if you missed it on screen, connect
the Kindle over USB and read that file directly, or read it via `cat` from
kterm.

#### Setting your own password before you ever install

Create a plain text file named **`dropbear_password.txt`** at the **root**
of the Kindle's drive (not inside any folder) containing your password —
`install.sh` picks it up automatically, uses it instead of generating a
random one, and deletes the staging file afterward. No exact-filename-without-
an-extension footgun (a `.txt` file is what any editor produces by default)
and no folder-creation required — just the top level of the drive, the first
thing you see when it's plugged in.

- **With a computer** (the common case — you'll want one to actually connect
  over SSH anyway): plug the Kindle in via USB the same way you'd sideload a
  book, and save the file at the top level of the drive with any plain text
  editor (Notepad, TextEdit, etc.).
- **Without a computer handy**, from `kterm` on the device itself:
  ```
  echo "yourpassword" > /mnt/us/dropbear_password.txt
  kpm install dropbear-ssh
  ```

Both paths were tested end-to-end, including saving from Windows Notepad
(`\r\n` line endings) — `install.sh` strips those automatically.

#### Changing or resetting the password later

Edit `/mnt/us/usbnetlite/etc/ssh_password` directly (plain text, one line —
via USB or kterm), **then restart the server**: kill any running
`dropbearmulti dropbear` process and run `kpm launch dropbear-ssh` again. A
running server has already loaded the old password into memory, so editing
the file alone doesn't take effect until it restarts.

To go back to a random generated password instead of picking a new one
yourself, just delete that file instead of editing it — `launch.sh`
generates a fresh random password automatically if it ever finds the file
missing (restart the server the same way afterward for it to take effect).

## What's verified, what isn't

This has been tested end-to-end (install → launch → real SSH session →
survives an upgrade) on a **Kindle PaperWhite 4, kernel `4.1.x`**
(2018–2022-era hardware — PW4, Basic3, Oasis3, PW5, Basic4, Scribe, per
upstream's own release device list).

The package also bundles a second binary build (`bin_11thgenplus`) covering
upstream's broader device list — 2011-era Kindle Touch through 2024 PaperWhite
6 / Scribe 2 / ColorSoft. `install.sh` picks between the two automatically
based on kernel version (`4.1.x` → the tested build; anything else → this
one). **This second build is only confirmed to execute** (same ELF
architecture/ABI, ran standalone via `dropbearmulti dropbear -h`) — a real
end-to-end test on the one device available crashed with `Connection reset by
peer` during the SSH key exchange, on that specific kernel. If you install
this on a device outside the `4.1.x` family and it doesn't work, that's the
known-unverified path — please open an issue with your device model and
`uname -r`.

## Security notes

- The SSH server only binds to your Kindle's WiFi interface — reachable by
  anything on the same network, not the internet, unless you've separately
  configured port forwarding.
- Stock Kindle firmware's `iptables` INPUT chain default-drops inbound
  connections; `launch.sh` opens the specific port each time it starts (this
  is runtime kernel state, not persisted — it's reapplied on every launch,
  not just once at install).
- Auth is dropbear's compiled-in master-password mechanism (`-Y`), not real
  user accounts — anyone with the password gets a root shell. Treat it like
  the root password it is.
- `source/` in this repo contains the exact `install.sh`/`launch.sh`/
  `uninstall.sh` and binaries bundled in the `.kpkg` — worth reading before
  installing anything that gets you root over SSH.

## License / origin

`bin_khf/` and `bin_11thgenplus/` are unmodified binaries extracted from
[notmarek/kindle-usbnetlite](https://github.com/notmarek/kindle-usbnetlite)'s
own signed releases via `kindletool extract` — not built from source here.
See that project for the dropbear/openssh source and Kindle-specific patches
used, and [Dropbear SSH](https://matt.ucc.asn.au/dropbear/dropbear.html) by
Matt Johnston for the underlying SSH server itself.
