# dropbear-ssh

On-demand SSH/SFTP access to a jailbroken Kindle over its existing WiFi
connection — a [KPM](https://github.com/KindleModding/KPM) package, nothing
to build, no USB cable required once it's installed.

## Install

Requires KPM on the device — modern jailbreaks ship with it pre-installed
(try `;kpm update` from the search bar to check; see the
[KPM project](https://github.com/KindleModding/KPM) if you don't have it).

**From `kterm` or any real terminal** — KPM's own installer never puts `kpm`
on your `PATH` (confirmed straight from its `install.sh`), so bare `kpm`
fails with `not found`; use the full path:

```
KPM=/var/local/kmc/bin/kpm
$KPM add-repo https://bit.ly/dropbear-ssh
$KPM -y update
$KPM -y install dropbear-ssh
$KPM launch dropbear-ssh
```

**From the search bar**, type each line separately — the search bar's own
`;kpm` wiring resolves the path for you, so no full path needed there:

```
;kpm add-repo https://bit.ly/dropbear-ssh
;kpm update
;kpm install dropbear-ssh
;kpm launch dropbear-ssh
```

`https://bit.ly/dropbear-ssh` is a shortlink to this repo's manifest —
easier to type on-device than the full URL. If you'd rather see exactly
where you're pointing before typing it, that's
`https://raw.githubusercontent.com/akshaylahudkar/dropbear-ssh/main/manifest.json`
— either works with `add-repo`.

`kpm launch` prints the exact command to connect with, using the Kindle's
real WiFi IP:

```
ssh -p 2022 root@<kindle-ip>
```

A random password is generated on install and printed right there in the
log — that's it, you're in. (Installing from the search bar? That log can
flash and disappear before you can read it — see [Password](#password)
below for how to still get it.)

## Password

- **Default**: random, printed in the install log, always readable
  afterward at `/mnt/us/usbnetlite/etc/ssh_password` (via USB or `kterm`)
  even if you missed it on screen.
- **Pick your own before installing**: save a plain text file named
  `dropbear_password.txt` at the root of the Kindle's drive — drag-and-drop
  it on via USB the same way you'd sideload a book, or from `kterm`:
  `echo "yourpassword" > /mnt/us/dropbear_password.txt`. The installer uses
  it and deletes the staging file.
- **Change it later**: edit `/mnt/us/usbnetlite/etc/ssh_password`, then kill
  any running `dropbearmulti dropbear` process and `kpm launch dropbear-ssh`
  again (a running server already has the old one loaded in memory).
- **Back to random**: delete that file instead of editing it — the next
  launch generates a fresh one automatically.

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

Tested end-to-end (install → launch → real SSH session → survives an
upgrade/downgrade) on a **Kindle PaperWhite 4, kernel `4.1.x`**
(2018–2022-era hardware — PW4, Basic3, Oasis3, PW5, Basic4, Scribe, per
upstream's own release device list).

The package also bundles a second binary build (`bin_11thgenplus`) covering
upstream's broader device list — 2011-era Kindle Touch through 2024
PaperWhite 6 / Scribe 2 / ColorSoft — auto-selected by kernel version at
install time (`4.1.x` → the tested build; anything else → this one). **That
second build is only confirmed to execute** (same ELF architecture/ABI); a
real end-to-end test crashed with `Connection reset by peer` during the SSH
key exchange on the one device available. If it doesn't work for you outside
the `4.1.x` family, that's the known-unverified path — open an issue with
your device model and `uname -r`.
</details>

<details>
<summary><strong>Security notes</strong></summary>

- The server only binds to the Kindle's WiFi interface — reachable by
  anything on the same network, not the internet, unless you've separately
  set up port forwarding.
- Stock firmware's `iptables` INPUT chain default-drops inbound connections;
  `launch.sh` re-opens the port on every launch (runtime kernel state, not
  persisted).
- Auth is dropbear's compiled-in master-password mechanism, not real user
  accounts — anyone with the password gets a root shell. Treat it like the
  root password it is.
- `source/` in this repo has the exact `install.sh`/`launch.sh`/
  `uninstall.sh` and binaries bundled in the `.kpkg` — worth a read before
  installing anything that gets you root over SSH.
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
