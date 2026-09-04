# dropbear-ssh

SSH and SFTP access to a jailbroken Kindle over WiFi, started and stopped
from an on-device app. Packaged for [KPM](https://github.com/KindleModding/KPM),
so there is nothing to build and no USB cable needed after install.

## Requirements

A jailbroken Kindle with KPM. Modern jailbreaks ship KPM pre-installed; check
for `/var/local/kmc/bin/kpm` if you are unsure, or just try the install below
and see whether it works.

| Device | Kernel | Binary build | Status |
| --- | --- | --- | --- |
| Paperwhite 4 | `4.1.x` | `bin_khf` | Tested end to end |
| Paperwhite 5 | `4.9.77` | `bin_11thgenplus` | Tested end to end |
| Paperwhite 6 (Véra) | `5.15.41` | `bin_11thgenplus` | Tested end to end |
| Basic 3/4, Oasis 3, Scribe | `4.1.x` | `bin_khf` | Untested, same build |
| Touch through Scribe 2 / ColorSoft | other | `bin_11thgenplus` | Untested, same build |

The package ships both binary builds and picks one by kernel version at
install time. If yours is not on this list, install it anyway and
[open an issue](../../issues) with your device model and `uname -r` if it
fails.

## Install

### Option A — USB, no terminal

1. Download [`dropbear-ssh.sh`](dropbear-ssh.sh).
2. Copy it into the Kindle's `documents` folder over USB, the same
   drag-and-drop as sideloading a book.
3. Eject, then tap **Dropbear SSH** in the Library. Reboot if it does not
   appear; the Home screen index does not always pick up new files right away.

That one file is both the installer and the permanent launcher. The first tap
installs and launches, every tap after that only launches. Nothing else needs
to be copied over later.

Because it installs only once, tapping the icon will not pull in a newer
version. See [Updating](#updating).

### Option B — from a terminal on the Kindle

Requires `kterm`, or any other shell, already on the device. If you do not have
one, use Option A, which needs no terminal at all.

Useful if you want to see the install output instead of a silent tap. These
commands run on the Kindle itself:

```text
KPM=/var/local/kmc/bin/kpm
$KPM add-repo https://nealing.net/manifest.json
$KPM install dropbear-ssh
$KPM launch dropbear-ssh
```

KPM's installer does not put `kpm` on `PATH`, hence the full path. This adds
the same Library icon as Option A, so later launches do not need `kterm`.

## Using it

Launching opens a status app with:

- **Start Server** / **Stop Server**
- **Set Password**, which restarts the server if it is running
- **Check for Update**
- **Keep reachable while Kindle sleeps**

While the server is running, the app shows the Kindle's current IP address and
password. Connect from any computer on the same network:

```console
$ ssh -p 2022 root@<kindle-ip>
$ sftp -P 2022 root@<kindle-ip>
```

Both use the same password. Note the capital `-P` for `sftp`.

The server keeps running after you close the app. The buttons talk to a small
HTTP bridge on the device (`nc` plus a shell handler) bound to
`127.0.0.1:18022`, so nothing is exposed beyond loopback.

### Keep reachable while Kindle sleeps

A Kindle suspends WiFi when the screen sleeps. The server process survives,
but nothing can reach it until the device wakes. This checkbox defers the
suspend cycle for as long as it is on.

It costs battery, since the radio and CPU stay up instead of suspending. The
e-ink screen itself draws power only while redrawing, so it is not a factor
either way. Stopping the server also turns this off.

## Updating

The app's **Check for Update** button installs whatever is currently latest and
reports either "Already up to date" or "Updated to vX.Y.Z" based on the
installed version before and after, not on the button having been tapped. It
restarts the server if it was running and reloads the app page.

The equivalent from `kterm` on the Kindle:

```text
KPM=/var/local/kmc/bin/kpm
$KPM install dropbear-ssh
```

This always hits the network, and does not need the repo re-added.

## Uninstalling

From `kterm` on the Kindle:

```text
/var/local/kmc/bin/kpm uninstall dropbear-ssh
```

That stops the server, removes the binaries, and unregisters the app. Two
things are left in place deliberately:

- **The Library launcher**, `documents/dropbear-ssh.sh`. Delete it over USB if
  you want the icon gone. KPM runs the uninstall hooks during every upgrade
  too, so removing it automatically would make the icon disappear after the
  first tap.
- **Your password and host keys**, under `/mnt/us/usbnetlite/etc`, so an
  upgrade never invalidates a working setup. Delete `/mnt/us/usbnetlite` for a
  clean slate.

## Password

Auth is dropbear's compiled-in master password, stored in plain text at
`/mnt/us/usbnetlite/etc/ssh_password` and readable over USB or from `kterm`.

- **Default**: random, generated at install and printed in the KPM log.
- **Choose your own before installing**: put a plain text file named
  `dropbear_password.txt` at the root of the Kindle drive. The installer reads
  it and deletes it.
- **Change it later**: use the app's **Set Password** field, or edit the
  password file and restart the server. A running server has the old password
  in memory, so editing the file alone changes nothing until it restarts.
- **Back to random**: delete the password file; the next launch generates a
  new one.

## Security

- The server binds to the WiFi interface, so it is reachable by anything on
  the same network but not from the internet unless you have forwarded a port.
- Stock firmware's `iptables` INPUT chain default-drops inbound connections.
  Starting the server re-opens port 2022 in runtime kernel state, not
  persisted across reboots.
- The master password gets a root shell. There are no user accounts. Treat it
  like the root password it is.
- The loopback bridge has no auth of its own, so any local process can toggle
  the server or read the password back. This matches the device's existing
  trust model, `lipc` included, but is worth knowing.
- [`source/`](source/) contains the exact scripts and binaries bundled in the
  `.kpkg`, worth reading before installing anything that grants root over SSH.

## Troubleshooting

**`error while loading shared libraries: libcrypt.so.1`** — some 2024-era
firmware does not ship `libcrypt.so.1` at all, which `dropbearmulti` needs for
the master-password `crypt()` call. Same root cause as a
[known KOReader issue](https://github.com/koreader/koreader/issues/14389).
Fixed since `0.1.8`, which bundles a copy in `bin_11thgenplus` and points
`LD_LIBRARY_PATH` at it. Report it if you still hit this on `0.1.8` or later.

**Search-bar `;` commands do not work.** Neither upstream's `;...mrpi` nor
`;kpm install ...` does anything useful on current jailbreaks. In the MRPI
case, `dispatch.sh` looks for a no-longer-bundled
`/mnt/us/extensions/MRInstaller/bin/mrinstaller.sh` and just flashes "MRPI is
not installed." Use Option A or Option B instead; there is no search-bar path
to installing this package.

**Why not upstream's own installer?** Beyond the above, its OTA installer
writes to rootfs and sets up USB-tethered networking, neither of which a KPM
hook package does or needs.

## Package repository

`https://nealing.net/manifest.json` is a Cloudflare Worker that proxies this
author's KPM manifests and `.kpkg` files from GitHub. It is shorter to type,
and it reaches devices whose network can talk to Cloudflare but not to
GitHub's raw-content CDN. It also serves
[sysmon](https://github.com/akshaylahudkar/sysmon). The older
`dropbear.nealing.net/manifest.json` redirects here.

If you would rather point at GitHub directly:

```text
https://raw.githubusercontent.com/akshaylahudkar/dropbear-ssh/main/manifest.json
```

## Credit

The `dropbearmulti` and `sftp-server` binaries come from
[notmarek/kindle-usbnetlite](https://github.com/notmarek/kindle-usbnetlite),
extracted unmodified from that project's signed releases with `kindletool
extract` rather than built here. Credit for the SSH server and the
Kindle-specific patches, including `dropbear_be_cool.patch` and the hardcoded
paths this package depends on, goes to
[notmarek](https://github.com/notmarek) and the kindle-usbnetlite
contributors, and to [Dropbear SSH](https://matt.ucc.asn.au/dropbear/dropbear.html)
by Matt Johnston underneath that.
