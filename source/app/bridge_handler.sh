#!/bin/sh
# HTTP bridge for the in-app buttons. `nc -lk -e` (started once by
# launch.sh) execs this fresh on every connection, wiring its stdin/
# stdout directly to the socket — so anything this script writes to
# stdout IS the HTTP response, and anything unexpected on stdout (echoed
# command output, etc.) would corrupt it. Every command below that could
# print on success is silenced accordingly; only respond() and the
# inline /update response write to stdout.
#
# Four actions now, routed by request path: the request line (e.g.
# "GET /keepawake?t=... HTTP/1.1") is read once at the top and matched
# against "/update", "/setpassword", and "/keepawake" — anything else
# (including the original bare "/" the server toggle has always used)
# falls through to that original behavior. Confirmed working end-to-end:
# the mesquite webview's XHR can reach 127.0.0.1 despite the page being
# loaded from file://, no CORS headaches needed.
BASEDIR="/mnt/us/usbnetlite"
BINDIR="${BASEDIR}/bin"
PASSFILE="${BASEDIR}/etc/ssh_password"
PIDFILE="${BASEDIR}/etc/dropbear.pid"
KEEPAWAKE_PIDFILE="${BASEDIR}/etc/keepawake.pid"
TARGET_DIR="/var/local/mesquite/dropbear-ssh"
PORT="2022"

IFS= read -r REQUEST_LINE

keepawake_state() {
    if [ -f "${KEEPAWAKE_PIDFILE}" ] && [ -d "/proc/$(cat "${KEEPAWAKE_PIDFILE}" 2>/dev/null)" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# The Start button's own logic, extracted to a function purely so it
# reads cleanly next to the toggle-check that decides whether to call it.
# update_helper.sh has its own small, separate copy of this same
# sequence for its post-update restart — deliberately not calling into
# this one, since that file lives in the same directory kpm install just
# overwrote and shouldn't be assumed stable mid-run. See that file for
# why.
start_dropbear() {
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
    # (keepalive/idle-timeout tuning, IPv4-only bind, etc.).
    #
    # LD_LIBRARY_PATH=BINDIR: some newer Kindle firmware doesn't ship
    # libcrypt.so.1 (needed for -Y's crypt() call) in its system library
    # path at all — install.sh bundles a copy in BINDIR for exactly that
    # case. This is a no-op on devices that already have their own
    # libcrypt.so.1 system-wide (the dynamic linker just finds ours first).
    #
    # setsid: confirmed the hard way that closing the status app stops the
    # server — dropbear forks and daemonizes itself (two different PIDs
    # show up in its own log), but that fork never leaves the process
    # group it inherited from this chain (nc -e -> this script ->
    # dropbearmulti), which traces back to the app's own process tree.
    # appmgrd stopping the app on close signals that whole group, catching
    # dropbear in it despite the self-fork. setsid puts it in a brand new
    # session, fully independent of whatever launched it — the actual
    # fix, not just nohup (which only blocks SIGHUP, not a process-group
    # signal).
    LD_LIBRARY_PATH="${BINDIR}" setsid "${BINDIR}/dropbearmulti" dropbear -R -p "0.0.0.0:${PORT}" -Y "${PASSWORD}" -K 60 -I 1800 -P "${PIDFILE}" \
        </dev/null >"${BASEDIR}/dropbear.log" 2>&1 &
}

respond() {
    # $1 = running (true/false), $2 = ip (only meaningful if running)
    # keepawake is looked up fresh every response regardless of which
    # action triggered it, so the app's UI always reflects full current
    # state from a single response, not just whatever this action touched.
    BODY=$(cat <<JSON
{"time":"$(date '+%H:%M:%S')","running":$1,"port":${PORT},"ip":"$2","password":"$(cat "${PASSFILE}" 2>/dev/null)","keepawake":$(keepawake_state)}
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

# ── /update: kick off an install of whatever's currently latest, via a
# separate detached script (update_helper.sh), NOT inline here. kpm
# install replaces this whole app/ directory, including this exact file
# — if bridge_handler.sh ran `kpm install` on its own package and then
# kept running to report the result, that overwrite would truncate the
# very script the shell is still mid-way through reading (same class of
# bug fixed in 0.1.7 for dropbear-ssh.sh). Launching a separate,
# disposable file via setsid and responding immediately sidesteps that
# entirely — this response only confirms the update started, not its
# result. The frontend polls update_result.json (written by
# update_helper.sh itself once it's actually done) for the real
# outcome, so any stale one from a previous update needs clearing here
# first — otherwise a fresh poll could read yesterday's leftover result
# before the new one lands.
case "${REQUEST_LINE}" in
    *"/update"*)
        rm -f "${TARGET_DIR}/update_result.json"
        setsid sh "${TARGET_DIR}/update_helper.sh" </dev/null >/dev/null 2>&1 &

        RUNNING="false"
        KINDLE_IP=""
        if [ -f "${PIDFILE}" ] && [ -d "/proc/$(cat "${PIDFILE}" 2>/dev/null)" ]; then
            RUNNING="true"
            KINDLE_IP=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
        fi
        BODY=$(cat <<JSON
{"time":"$(date '+%H:%M:%S')","update_started":true,"running":${RUNNING},"port":${PORT},"ip":"${KINDLE_IP}","password":"$(cat "${PASSFILE}" 2>/dev/null)","keepawake":$(keepawake_state)}
JSON
)
        LEN=$(printf '%s' "${BODY}" | wc -c | tr -d ' ')
        printf 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' "${LEN}" "${BODY}"
        exit 0
        ;;
esac

# ── /setpassword?pw=<urlencoded>: write a new password and, if the
# server is currently running, restart it so the new password actually
# takes effect (a running dropbear has already loaded the old one into
# memory — same caveat the README documents for editing the file by
# hand). The one action here that carries real user input across the
# bridge rather than just toggling something; pw is pulled out of the
# request line and percent-decoded by hand (sed can undo
# encodeURIComponent's escaping — no proper URL-parsing tool available
# in this shell).
case "${REQUEST_LINE}" in
    *"/setpassword"*)
        RAW_PW=$(printf '%s' "${REQUEST_LINE}" | sed -n 's/.*[?&]pw=\([^& ]*\).*/\1/p')
        NEW_PW=$(printf '%b' "$(printf '%s' "${RAW_PW}" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')")

        if [ -n "${NEW_PW}" ]; then
            mkdir -p "${BASEDIR}/etc"
            printf '%s' "${NEW_PW}" > "${PASSFILE}"
        fi

        RUNNING="false"
        KINDLE_IP=""
        if [ -f "${PIDFILE}" ] && [ -d "/proc/$(cat "${PIDFILE}" 2>/dev/null)" ]; then
            OLD_PID=$(cat "${PIDFILE}" 2>/dev/null)
            kill "${OLD_PID}" 2>/dev/null
            rm -f "${PIDFILE}"
            # Same wait-for-actual-death pattern uninstall.sh uses —
            # kill only sends the signal, doesn't wait for the port to
            # actually free up; confirmed hittable without this (a
            # restart landing before the old process released 0.0.0.0:
            # ${PORT} would fail to bind at all).
            WAITED=0
            while [ -d "/proc/${OLD_PID}" ] && [ "${WAITED}" -lt 3 ]; do
                sleep 1
                WAITED=$((WAITED + 1))
            done
            start_dropbear
            RUNNING="true"
            KINDLE_IP=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
        fi

        respond "${RUNNING}" "${KINDLE_IP}"
        exit 0
        ;;
esac

# ── /keepawake: toggle the sleep-deferral loop, independent of the SSH
# server's own state. Whatever the current dropbear state is, report it
# accurately in the response too (same respond() as the server toggle
# uses) rather than a different response shape.
case "${REQUEST_LINE}" in
    *"/keepawake"*)
        RUNNING="false"
        KINDLE_IP=""
        if [ -f "${PIDFILE}" ] && [ -d "/proc/$(cat "${PIDFILE}" 2>/dev/null)" ]; then
            RUNNING="true"
            KINDLE_IP=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
        fi
        if [ "$(keepawake_state)" = "true" ]; then
            # process-group kill (negative PID), not just the PID itself —
            # setsid makes the loop's own session/group leader match that
            # PID, so this reliably takes both lipc-wait-event and the
            # while-loop reading its output with it in one shot, rather
            # than killing only the shell and hoping SIGPIPE finishes the
            # job on the next event (which could be a long wait away).
            kill -- -"$(cat "${KEEPAWAKE_PIDFILE}")" 2>/dev/null
            rm -f "${KEEPAWAKE_PIDFILE}"
        else
            rm -f "${KEEPAWAKE_PIDFILE}"
            setsid sh "${TARGET_DIR}/keepawake_loop.sh" </dev/null >/dev/null 2>&1 &
            echo $! > "${KEEPAWAKE_PIDFILE}"
        fi
        respond "${RUNNING}" "${KINDLE_IP}"
        exit 0
        ;;
esac

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
# start_dropbear (defined near the top) carries the real explanation for
# LD_LIBRARY_PATH and setsid — this is just where that logic used to live
# inline before /update needed to call it too.
start_dropbear

KINDLE_IP=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')

respond true "${KINDLE_IP}"
