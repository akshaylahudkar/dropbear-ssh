#!/bin/sh
# KPM runs this on both a real uninstall AND on every upgrade (uninstall old
# -> install new), so this must NOT touch anything the user configured —
# host keys, authorized_keys, the password file. Only remove what this
# package itself places: the binaries. Confirmed the hard way: an earlier
# version of this script did `rm -rf` on the whole base dir and wiped
# working SSH access on every single upgrade.
BASEDIR="/mnt/us/usbnetlite"
BINDIR="${BASEDIR}/bin"

for PID in $(ps | grep '[d]ropbearmulti dropbear' | awk '{print $1}'); do
    kill "${PID}" 2>/dev/null
done

rm -f "${BINDIR}/dropbearmulti" "${BINDIR}/sftp-server"
