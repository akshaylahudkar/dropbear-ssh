#!/bin/sh
# HTTP bridge for the in-app Start/Stop button. `nc -lk -e` (started once
# by launch.sh) execs this fresh on every connection, wiring its stdin/
# stdout directly to the socket — so anything this script writes to
# stdout IS the HTTP response, and anything unexpected on stdout (echoed
# command output, etc.) would corrupt it. Every command below that could
# print on success is silenced accordingly; only respond() writes to
# stdout.
#
# Ignores the request itself entirely — there's only one action (toggle),
# so there's nothing to route on. Confirmed working end-to-end: the
# mesquite webview's XHR can reach 127.0.0.1 despite the page being
# loaded from file://, no CORS headaches needed.
BASEDIR="/mnt/us/usbnetlite"
BINDIR="${BASEDIR}/bin"
PASSFILE="${BASEDIR}/etc/ssh_password"
PIDFILE="${BASEDIR}/etc/dropbear.pid"
PORT="2022"

respond() {
    # $1 = running (true/false), $2 = ip (only meaningful if running)
    BODY=$(cat <<JSON
{"time":"$(date '+%H:%M:%S')","running":$1,"port":${PORT},"ip":"$2","password":"$(cat "${PASSFILE}" 2>/dev/null)"}
JSON
)
    # Content-Length matters here, not just correctness theater: without
    # it the client has to trust a perfectly clean connection close to
    # know the body's finished, and `nc -e`'s teardown isn't always that
    # clean — confirmed on-device, this caused an intermittent XHR
    # onerror in the app even though the response body had fully arrived
    # (seen even with plain curl in early testing, which reported an
    # error despite printing the correct body).
    LEN=$(printf '%s' "${BODY}" | wc -c | tr -d ' ')
    printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' "${LEN}" "${BODY}"
}

# Same PID-file + /proc liveness check as launch.sh used to use directly
# — see that file's history for why this beats pattern-matching `ps`.

# ── Already running: STOP ────────────────────────────────────────────
if [ -f "${PIDFILE}" ] && [ -d "/proc/$(cat "${PIDFILE}" 2>/dev/null)" ]; then
    kill "$(cat "${PIDFILE}")" 2>/dev/null
    rm -f "${PIDFILE}"
    iptables -D INPUT -p tcp --dport "${PORT}" -j ACCEPT >/dev/null 2>&1
    respond false ""
    exit 0
fi
rm -f "${PIDFILE}"

# ── Not running: START ───────────────────────────────────────────────
PASSWORD=$(cat "${PASSFILE}" 2>/dev/null)
if [ -z "${PASSWORD}" ]; then
    PASSWORD=$(dd if=/dev/urandom bs=1 count=6 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
    [ -z "${PASSWORD}" ] && PASSWORD="kp$$$(date +%s 2>/dev/null)"
    mkdir -p "${BASEDIR}/etc"
    echo "${PASSWORD}" > "${PASSFILE}"
fi

iptables -C INPUT -p tcp --dport "${PORT}" -j ACCEPT >/dev/null 2>&1 || \
    iptables -I INPUT -p tcp --dport "${PORT}" -j ACCEPT >/dev/null 2>&1

# See launch.sh's git history for why every flag here is what it is
# (keepalive/idle-timeout tuning, IPv4-only bind, etc.) — this is the
# exact same invocation, just triggered by the button instead of a tap
# on the outside Library icon.
#
# LD_LIBRARY_PATH=BINDIR: some newer Kindle firmware doesn't ship
# libcrypt.so.1 (needed for -Y's crypt() call) in its system library path
# at all — install.sh bundles a copy in BINDIR for exactly that case. This
# is a no-op on devices that already have their own libcrypt.so.1 system-
# wide (the dynamic linker just finds ours first).
#
# setsid: confirmed the hard way that closing the status app stops the
# server — dropbear forks and daemonizes itself (two different PIDs show
# up in its own log), but that fork never leaves the process group it
# inherited from this chain (nc -e -> this script -> dropbearmulti), which
# traces back to the app's own process tree. appmgrd stopping the app on
# close signals that whole group, catching dropbear in it despite the
# self-fork. setsid puts it in a brand new session, fully independent of
# whatever launched it — the actual fix, not just nohup (which only blocks
# SIGHUP, not a process-group signal).
LD_LIBRARY_PATH="${BINDIR}" setsid "${BINDIR}/dropbearmulti" dropbear -R -p "0.0.0.0:${PORT}" -Y "${PASSWORD}" -K 60 -I 1800 -P "${PIDFILE}" \
    </dev/null >"${BASEDIR}/dropbear.log" 2>&1 &

KINDLE_IP=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')

respond true "${KINDLE_IP}"
