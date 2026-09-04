#!/bin/sh
# Installs dropbearmulti/sftp-server (repackaged from notmarek/kindle-usbnetlite)
# to the exact paths those binaries were compiled to expect — see that
# project's dropbear_be_cool.patch: host keys and SFTPSERVER_PATH are
# hardcoded to /mnt/us/usbnetlite/..., so this layout is not arbitrary.
BASEDIR="/mnt/us/usbnetlite"
BINDIR="${BASEDIR}/bin"
DROPBEARDIR="${BASEDIR}/etc/dropbear"
PASSFILE="${BASEDIR}/etc/ssh_password"

# Resolve paths to bin_khf/bin_11thgenplus relative to this script's own
# location, not the caller's cwd. KPM always chdirs into the package
# directory before running install.sh, so a bare "./bin_khf" happened to
# work there — but it silently breaks (cp fails, script keeps going with
# no error, binary just never gets installed) when run directly, e.g.
# `sh /path/to/install.sh` from kterm without cd-ing there first.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

mkdir -p "${BINDIR}" "${DROPBEARDIR}"

# Upstream ships two binary builds with overlapping-but-different device
# whitelists (see kindle-usbnetlite's two release assets). Testing found the
# newer "11thgenplus" build crashes during the SSH key exchange specifically
# on kernel 4.1.x (2018-2022-era hardware) despite matching ELF architecture
# — so route by actual kernel version rather than trust the device list.
# Only the 4.1.x path has been confirmed to work end-to-end; the other path
# is included for broader coverage per upstream's own release, but is only
# confirmed to execute, not confirmed to correctly serve a session on its
# target hardware.
KVER=$(uname -r)
case "${KVER}" in
    4.1.*)
        SRC="${SCRIPT_DIR}/bin_khf"
        ;;
    *)
        SRC="${SCRIPT_DIR}/bin_11thgenplus"
        ;;
esac
echo "Kernel ${KVER} -> using ${SRC}"

cp -f "${SRC}/dropbearmulti" "${BINDIR}/dropbearmulti" || { echo "ERROR: failed to copy ${SRC}/dropbearmulti — aborting install."; exit 1; }
cp -f "${SRC}/sftp-server" "${BINDIR}/sftp-server" || { echo "ERROR: failed to copy ${SRC}/sftp-server — aborting install."; exit 1; }
chmod +x "${BINDIR}/dropbearmulti" "${BINDIR}/sftp-server"

# bin_11thgenplus only: newer Kindle firmware (confirmed on a 2024-era
# Paperwhite 6, kernel 5.15.x) doesn't ship libcrypt.so.1 in its system
# library path at all, which dropbearmulti needs for the -Y master-password
# flag's crypt() call — it fails to even start with "error while loading
# shared libraries: libcrypt.so.1". Same root cause as a known KOReader
# issue on the same device class (github.com/koreader/koreader/issues/14389).
# Extracted from a working device (Paperwhite 5, kernel 4.9.x, armhf —
# confirmed same ELF architecture as these binaries) rather than trusting a
# random third-party binary. bin_khf/PW4 never hits this, so it's not
# bundled there. launch.sh/bridge_handler.sh point LD_LIBRARY_PATH at
# BINDIR so this gets picked up when present; harmless no-op copy on
# devices whose system library is already there.
if [ -f "${SRC}/libcrypt.so.1" ]; then
    cp -f "${SRC}/libcrypt.so.1" "${BINDIR}/libcrypt.so.1"
fi

# Random per-install password for the master-password auth flag (-Y) — a
# fixed default (e.g. "kindle") would make every install of this package
# guessable, so generate one instead. 6 bytes of /dev/urandom as hex (12
# chars) is plenty for a LAN-only on-demand server; falls back to a
# timestamp/pid mix if urandom or od are somehow unavailable.
#
# Before installing, anyone can drop a plain text file named
# dropbear_password.txt at the root of the Kindle drive (via USB — no
# folder-creation, no exact-filename-without-an-extension footgun that a
# path under etc/ would require) to pick their own password instead of a
# random one. head -n1 + tr strips Windows line endings in case it was
# saved from Notepad.
STAGED_PASSFILE="/mnt/us/dropbear_password.txt"
if [ ! -f "${PASSFILE}" ]; then
    if [ -f "${STAGED_PASSFILE}" ]; then
        head -n1 "${STAGED_PASSFILE}" | tr -d '\r\n' > "${PASSFILE}"
        rm -f "${STAGED_PASSFILE}"
        echo "Using password from ${STAGED_PASSFILE} (file removed)."
    else
        RANDPASS=$(dd if=/dev/urandom bs=1 count=6 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
        if [ -z "${RANDPASS}" ]; then
            RANDPASS="kp$$$(date +%s 2>/dev/null)"
        fi
        echo "${RANDPASS}" > "${PASSFILE}"
    fi
fi

# Status/toggle UI — a real mesquite app window (same appreg pattern as
# sysmon/reading-stats), not raw fbink text. fbink-held text was tried
# first and confirmed unreliable: this device's scriptlet launcher wipes
# the screen a few seconds in regardless of the script's own sleep,
# apparently assuming every scriptlet hands off to a real app window.
# APP_ID deliberately has NO hyphen — confirmed the hard way on a past
# app that hyphens in a com.akshay.X app id break appmgrd's LIPC `load`
# routing (DBus naming rule), causing a silent 10s timeout with no window
# ever appearing.
TARGET_DIR="/var/local/mesquite/dropbear-ssh"
DB="/var/local/appreg.db"
APP_ID="com.akshay.dropbearssh"

rm -rf "${TARGET_DIR}"
cp -r "${SCRIPT_DIR}/app" "${TARGET_DIR}"
chmod +x "${TARGET_DIR}/bridge_handler.sh" "${TARGET_DIR}/keepawake_loop.sh" "${TARGET_DIR}/update_helper.sh"

sqlite3 "$DB" <<EOF
INSERT OR IGNORE INTO interfaces(interface) VALUES('application');
INSERT OR IGNORE INTO handlerIds(handlerId) VALUES('$APP_ID');
INSERT OR REPLACE INTO properties(handlerId,name,value)
  VALUES('$APP_ID','lipcId','$APP_ID');
INSERT OR REPLACE INTO properties(handlerId,name,value)
  VALUES('$APP_ID','command','/usr/bin/mesquite -l $APP_ID -c file://$TARGET_DIR/');
INSERT OR REPLACE INTO properties(handlerId,name,value)
  VALUES('$APP_ID','supportedOrientation','U');
EOF

# Kindle Library scriptlet — only written if it doesn't already exist, so
# an install triggered purely from kterm (README's Option B) also ends up
# with a tappable Home-screen entry, same as Option A. The existence check
# is what makes this safe: this exact file is what Option A's own tap
# executes (its own `if [ ! -d ... ]` guarded `kpm install` line is what
# leads here on a fresh install), so unconditionally overwriting it here
# would mean truncating the very script the shell is still mid-way through
# reading — undefined behavior, not just redundant (this was a real bug,
# fixed in 0.1.7). By the time that scriptlet is running, it obviously
# already exists, so this block never fires in that path — it only fires
# for a genuinely fresh kterm install where nothing's there yet.
# uninstall.sh deliberately never removes this file either way, same as
# it never touches kterm.sh.
if [ ! -f "/mnt/us/documents/dropbear-ssh.sh" ]; then
    cat > "/mnt/us/documents/dropbear-ssh.sh" <<'SCRIPTLET'
#!/bin/sh
# Name: Dropbear SSH
# Author: Akshay
# DontUseFBInk
KPM=/var/local/kmc/bin/kpm
if [ ! -d /mnt/us/kmc/kpm/packages/dropbear-ssh ]; then
    $KPM add-repo https://nealing.net/manifest.json
    $KPM install dropbear-ssh
fi
$KPM launch dropbear-ssh
SCRIPTLET
    chmod +x "/mnt/us/documents/dropbear-ssh.sh"
fi

echo "Installed. Launch with: kpm launch dropbear-ssh"
echo "Password: $(cat "${PASSFILE}")"
echo "(A Library tap shows none of this output — the password is always saved"
echo "in plain text at ${PASSFILE}, readable via USB or"
echo "kterm regardless of how the install ran. The app displays it too.)"
echo "To set your own: edit ${PASSFILE} (plain text, one line), then kill any"
echo "running dropbearmulti dropbear process and 'kpm launch dropbear-ssh'"
echo "again — a running server has already loaded the old password into"
echo "memory, so editing the file alone won't take effect until it restarts."
