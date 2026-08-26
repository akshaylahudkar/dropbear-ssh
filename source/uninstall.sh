#!/bin/sh
# KPM runs this on both a real uninstall AND on every upgrade (uninstall old
# -> install new), so this must NOT touch anything the user configured —
# host keys, authorized_keys, the password file. Only remove what this
# package itself places: the binaries. Confirmed the hard way: an earlier
# version of this script did `rm -rf` on the whole base dir and wiped
# working SSH access on every single upgrade.
BASEDIR="/mnt/us/usbnetlite"
BINDIR="${BASEDIR}/bin"
PIDFILE="${BASEDIR}/etc/dropbear.pid"

# Prefer the pid dropbear itself wrote (via launch.sh's -P) — precise,
# and doesn't depend on parsing `ps` output at all.
KILLED_PIDS=""
if [ -f "${PIDFILE}" ]; then
    OLD_PID=$(cat "${PIDFILE}" 2>/dev/null)
    kill "${OLD_PID}" 2>/dev/null
    KILLED_PIDS="${OLD_PID}"
    rm -f "${PIDFILE}"
fi

# Fallback for anything the pid file missed (stale/missing file, e.g. a
# server started by an older package version pre-dating -P). Match on
# the bare comm name only — busybox's plain `ps` (as opposed to
# `ps -eo ... args`) truncates CMD to argv[0] with no arguments, so a
# pattern requiring "dropbearmulti dropbear" together never matches here
# and silently kills nothing. Confirmed on-device: this left the old
# server running through every past upgrade.
for PID in $(ps | grep '[d]ropbearmulti' | awk '{print $1}'); do
    kill "${PID}" 2>/dev/null
    KILLED_PIDS="${KILLED_PIDS} ${PID}"
done

# kill only sends the signal — it doesn't wait for the process to
# actually exit and release the port. Poll briefly rather than assuming
# instant death, so a KPM upgrade that chains straight into the new
# install.sh/launch.sh doesn't race the old process for the port
# (confirmed hittable: an immediate re-launch right after this script
# saw "No listening ports available" because the old process hadn't
# released 0.0.0.0:2022 yet).
WAITED=0
while [ "${WAITED}" -lt 3 ]; do
    STILL_ALIVE=0
    for PID in ${KILLED_PIDS}; do
        [ -d "/proc/${PID}" ] && STILL_ALIVE=1
    done
    [ "${STILL_ALIVE}" -eq 0 ] && break
    sleep 1
    WAITED=$((WAITED + 1))
done

rm -f "${BINDIR}/dropbearmulti" "${BINDIR}/sftp-server" "${BINDIR}/libcrypt.so.1"

# Loopback HTTP bridge behind the app's Start/Stop button — its pidfile
# lives in the same shared BASEDIR/etc as dropbear's own, deliberately
# (see the big comment at the top of this file re: not touching anything
# else in there).
BRIDGE_PIDFILE="${BASEDIR}/etc/bridge.pid"
if [ -f "${BRIDGE_PIDFILE}" ]; then
    kill "$(cat "${BRIDGE_PIDFILE}")" 2>/dev/null
    rm -f "${BRIDGE_PIDFILE}"
fi
for PID in $(ps | grep '[n]c -lk' | awk '{print $1}'); do
    kill "${PID}" 2>/dev/null
done

# Sleep-deferral loop behind the app's keep-awake checkbox — an active
# background process (unlike the Home-screen launcher file, which is
# deliberately never touched here), so it does get cleaned up on a real
# uninstall. Process-group kill since setsid made its own session/group
# leader match this PID — a plain kill would only stop the outer shell,
# leaving lipc-wait-event running until its next SIGPIPE.
KEEPAWAKE_PIDFILE="${BASEDIR}/etc/keepawake.pid"
if [ -f "${KEEPAWAKE_PIDFILE}" ]; then
    kill -- -"$(cat "${KEEPAWAKE_PIDFILE}")" 2>/dev/null
    rm -f "${KEEPAWAKE_PIDFILE}"
fi

# Mesquite status/toggle app install.sh registers — same appreg pattern as
# sysmon/reading-stats' own uninstall.sh.
DB="/var/local/appreg.db"
APP_ID="com.akshay.dropbearssh"
rm -rf "/var/local/mesquite/dropbear-ssh"
sqlite3 "$DB" <<EOF
DELETE FROM properties WHERE handlerId='$APP_ID';
DELETE FROM handlerIds WHERE handlerId='$APP_ID';
EOF

# Deliberately NOT touching /mnt/us/documents/dropbear-ssh.sh here. It used
# to be safe to delete because install.sh regenerated it every time — now
# it's the permanent, user-placed launcher (both installer and launcher in
# one file), and kpm runs this uninstall.sh as part of every plain
# `kpm install` too (logged as "Running uninstall hooks"), not just a real
# uninstall. Deleting it here means the Home-screen icon would vanish after
# the very first tap, on every future upgrade, forever — confirmed the hard
# way on a real device. A genuine uninstall leaves the launcher in place,
# same as nothing auto-removes kterm.sh; delete it manually via USB if you
# want it gone too.
