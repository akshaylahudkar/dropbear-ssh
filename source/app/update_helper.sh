#!/bin/sh
# Run detached (via setsid, launched by bridge_handler.sh's /update route)
# specifically so `kpm install` never overwrites the very file that's
# still reading and executing it. kpm install replaces this whole app/
# directory — including bridge_handler.sh itself — as part of
# reinstalling; if bridge_handler.sh called `kpm install` on itself
# directly and stayed running to report the result, that overwrite would
# be truncating the script the shell is still mid-way through reading —
# the same class of bug fixed in 0.1.7 for dropbear-ssh.sh. Running the
# actual install from this separate, disposable file sidesteps it
# entirely: this file itself may also get overwritten mid-run (it's part
# of the same app/ directory), but nothing here re-reads itself after
# kpm install returns, so a mid-run overwrite of the remaining lines
# doesn't matter — worst case a stray line gets skipped after the
# install itself has already fully completed.
BASEDIR="/mnt/us/usbnetlite"
BINDIR="${BASEDIR}/bin"
PASSFILE="${BASEDIR}/etc/ssh_password"
PIDFILE="${BASEDIR}/etc/dropbear.pid"
PORT="2022"
KPM="/var/local/kmc/bin/kpm"
PKG_ID="dropbear-ssh"

WAS_RUNNING="false"
if [ -f "${PIDFILE}" ] && [ -d "/proc/$(cat "${PIDFILE}" 2>/dev/null)" ]; then
    WAS_RUNNING="true"
fi

# -y: skip kpm's interactive confirm prompt — no terminal attached here.
"${KPM}" -y install "${PKG_ID}" >/dev/null 2>&1

# Restart dropbear if it was running before — deliberately NOT calling
# into bridge_handler.sh's own start_dropbear() from here, since that
# would mean sourcing a file this same install just replaced (same
# self-modification concern this whole file exists to avoid). Small,
# acceptable duplication of the same start sequence instead.
if [ "${WAS_RUNNING}" = "true" ]; then
    PASSWORD=$(cat "${PASSFILE}" 2>/dev/null)
    if [ -z "${PASSWORD}" ]; then
        PASSWORD=$(dd if=/dev/urandom bs=1 count=6 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
        [ -z "${PASSWORD}" ] && PASSWORD="kp$$$(date +%s 2>/dev/null)"
        mkdir -p "${BASEDIR}/etc"
        echo "${PASSWORD}" > "${PASSFILE}"
    fi
    iptables -C INPUT -p tcp --dport "${PORT}" -j ACCEPT >/dev/null 2>&1 || \
        iptables -I INPUT -p tcp --dport "${PORT}" -j ACCEPT >/dev/null 2>&1
    LD_LIBRARY_PATH="${BINDIR}" setsid "${BINDIR}/dropbearmulti" dropbear -R -p "0.0.0.0:${PORT}" -Y "${PASSWORD}" -K 60 -I 1800 -P "${PIDFILE}" \
        </dev/null >"${BASEDIR}/dropbear.log" 2>&1 &
fi
