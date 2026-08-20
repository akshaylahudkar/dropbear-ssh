#!/bin/sh
# Installs dropbearmulti/sftp-server (repackaged from notmarek/kindle-usbnetlite)
# to the exact paths those binaries were compiled to expect — see that
# project's dropbear_be_cool.patch: host keys and SFTPSERVER_PATH are
# hardcoded to /mnt/us/usbnetlite/..., so this layout is not arbitrary.
BASEDIR="/mnt/us/usbnetlite"
BINDIR="${BASEDIR}/bin"
DROPBEARDIR="${BASEDIR}/etc/dropbear"
PASSFILE="${BASEDIR}/etc/ssh_password"

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
        SRC="./bin_khf"
        ;;
    *)
        SRC="./bin_11thgenplus"
        ;;
esac
echo "Kernel ${KVER} -> using ${SRC}"

cp -f "${SRC}/dropbearmulti" "${BINDIR}/dropbearmulti"
cp -f "${SRC}/sftp-server" "${BINDIR}/sftp-server"
chmod +x "${BINDIR}/dropbearmulti" "${BINDIR}/sftp-server"

# Random per-install password for the master-password auth flag (-Y) — a
# fixed default (e.g. "kindle") would make every install of this package
# guessable, so generate one instead. 6 bytes of /dev/urandom as hex (12
# chars) is plenty for a LAN-only on-demand server; falls back to a
# timestamp/pid mix if urandom or od are somehow unavailable.
if [ ! -f "${PASSFILE}" ]; then
    RANDPASS=$(dd if=/dev/urandom bs=1 count=6 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
    if [ -z "${RANDPASS}" ]; then
        RANDPASS="kp$$$(date +%s 2>/dev/null)"
    fi
    echo "${RANDPASS}" > "${PASSFILE}"
fi

echo "Installed. Launch with: kpm launch dropbear-ssh"
echo "Password: $(cat "${PASSFILE}")"
echo "To set your own: edit ${PASSFILE} (plain text, one line), then kill any"
echo "running dropbearmulti dropbear process and 'kpm launch dropbear-ssh'"
echo "again — a running server has already loaded the old password into"
echo "memory, so editing the file alone won't take effect until it restarts."
