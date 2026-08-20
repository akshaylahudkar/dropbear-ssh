# dropbear-ssh

A [KPM](https://github.com/KindleModding/KPM) package that gives you on-demand
SSH/SFTP access to a jailbroken Kindle over its existing WiFi connection — no
USB networking, no rebuilding anything from source. It's a repackaging of the
`dropbearmulti`/`sftp-server` binaries from
[notmarek/kindle-usbnetlite](https://github.com/notmarek/kindle-usbnetlite),
wrapped as a KPM hook package instead of that project's original
OTA/`mrpackages` installer, since the OTA installer writes to rootfs (symlinks
in `/usr/bin`) and sets up USB-tethered networking that most people with a
Kindle already on WiFi don't need.

## Install

Requires [KPM](https://kindlemodding.org/kindle-dev/kpm/index.html) already
installed on the device.

From the Kindle's search bar, or a terminal (e.g. `kterm`):

```
kpm add-repo https://raw.githubusercontent.com/akshaylahudkar/dropbear-ssh/main/manifest.json
kpm update
kpm install dropbear-ssh
kpm launch dropbear-ssh
```

The install log prints a randomly-generated password — that's what you log
in with:

```
ssh -p 2022 root@<kindle-ip>
```

To set your own password instead: edit
`/mnt/us/usbnetlite/etc/ssh_password` (plain text, one line) on the device,
then kill any running `dropbearmulti dropbear` process and `kpm launch
dropbear-ssh` again — a running server has already loaded the old password
into memory, so editing the file alone doesn't take effect until it restarts.

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
notmarek/kindle-usbnetlite's own signed releases via `kindletool extract` —
not built from source here. See that project for the dropbear/openssh source
and patches used.
