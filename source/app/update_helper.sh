#!/bin/sh
# Run detached (via setsid, launched by bridge_handler.sh's /update route)
# specifically so `kpm install` never overwrites the very file that's
# still reading and executing it. kpm install replaces this whole app/
# directory — including this file — as part of reinstalling.
#
# Unlike the first version of this file, there's real logic that needs
# to survive AFTER the kpm install call now (before/after version
# comparison, conditional restart, writing the result file) — "a stray
# skipped line probably doesn't matter" isn't good enough here, a
# truncated run could just never write the result at all and leave the
# app polling forever. So this copies itself to a stable path in /tmp
# and re-execs from there before doing anything real — the copy is
# immune to kpm install overwriting the original in app/, since it's a
# different file entirely by the time the risky part runs.
if [ "$1" != "--relocated" ]; then
    cp "$0" /tmp/dropbear_update_helper_run.sh 2>/dev/null
    chmod +x /tmp/dropbear_update_helper_run.sh 2>/dev/null
    exec sh /tmp/dropbear_update_helper_run.sh --relocated
fi

# ── Everything below runs from the /tmp copy — safe from here on. ─────
BASEDIR="/mnt/us/usbnetlite"
BINDIR="${BASEDIR}/bin"
PASSFILE="${BASEDIR}/etc/ssh_password"
PIDFILE="${BASEDIR}/etc/dropbear.pid"
PORT="2022"
KPM="/var/local/kmc/bin/kpm"
PKG_ID="dropbear-ssh"
PKG_MANIFEST="/mnt/us/kmc/kpm/packages/${PKG_ID}/manifest.json"
TARGET_DIR="/var/local/mesquite/dropbear-ssh"
RESULT_FILE="${TARGET_DIR}/update_result.json"
KEEPAWAKE_PIDFILE="${BASEDIR}/etc/keepawake.pid"

get_version() {
    grep -A4 '"version"' "${PKG_MANIFEST}" 2>/dev/null | grep -oE '[0-9]+' | tr '\n' '.' | sed 's/\.$//'
}

keepawake_state() {
    if [ -f "${KEEPAWAKE_PIDFILE}" ] && [ -d "/proc/$(cat "${KEEPAWAKE_PIDFILE}" 2>/dev/null)" ]; then
        echo "true"
    else
        echo "false"
    fi
}

WAS_RUNNING="false"
if [ -f "${PIDFILE}" ] && [ -d "/proc/$(cat "${PIDFILE}" 2>/dev/null)" ]; then
    WAS_RUNNING="true"
fi

BEFORE_VERSION=$(get_version)

# -y: skip kpm's interactive confirm prompt — no terminal attached here.
"${KPM}" -y install "${PKG_ID}" >/dev/null 2>&1

AFTER_VERSION=$(get_version)
[ -z "${AFTER_VERSION}" ] && AFTER_VERSION="unknown"

# kpm install always reports "upgrading" even when the version is
# identical (confirmed the hard way — same root cause as the
# reopen-kills-server bug fixed in 0.1.11), so its own output can't be
# trusted to tell "actually updated" from "reinstalled the same bits".
# Comparing the version string before and after is the only reliable
# signal.
UPDATED="false"
[ "${AFTER_VERSION}" != "${BEFORE_VERSION}" ] && UPDATED="true"

# Restart if it was running — deliberately a small separate copy of
# bridge_handler.sh's start_dropbear(), not a call into it: that file
# lives in the app/ directory kpm install just replaced.
RUNNING="false"
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
    RUNNING="true"
fi

KINDLE_IP=""
[ "${RUNNING}" = "true" ] && KINDLE_IP=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')

# The frontend polls this file directly (same file:// XHR pattern as
# status.json) rather than going back through the HTTP bridge — simpler,
# and this file living in TARGET_DIR survives the app/ overwrite fine
# since it's written fresh right here, after that overwrite already
# happened.
mkdir -p "${TARGET_DIR}"
cat > "${RESULT_FILE}" <<EOF
{
  "time": "$(date '+%H:%M:%S')",
  "done": true,
  "updated": ${UPDATED},
  "version": "${AFTER_VERSION}",
  "running": ${RUNNING},
  "port": ${PORT},
  "ip": "${KINDLE_IP}",
  "password": "$(cat "${PASSFILE}" 2>/dev/null)",
  "keepawake": $(keepawake_state)
}
EOF

rm -f /tmp/dropbear_update_helper_run.sh
