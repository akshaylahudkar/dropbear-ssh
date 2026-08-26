#!/bin/sh
# Opens the Dropbear SSH status app, showing whatever the server's actual
# current state is. Does NOT toggle anything itself anymore — earlier
# versions did (tap the Library icon to start, tap again to stop), but
# that was confusing since you couldn't see current state before deciding
# to tap, and once accidentally led to stopping SSH when the intent was
# to check it. Toggling now happens via the app's own Start/Stop button,
# wired through bridge_handler.sh over a loopback HTTP bridge — this
# script's only remaining job is making sure that bridge is listening,
# then showing the app.
BASEDIR="/mnt/us/usbnetlite"
PASSFILE="${BASEDIR}/etc/ssh_password"
PIDFILE="${BASEDIR}/etc/dropbear.pid"
KEEPAWAKE_PIDFILE="${BASEDIR}/etc/keepawake.pid"
PORT="2022"

TARGET_DIR="/var/local/mesquite/dropbear-ssh"
APP_ID="com.akshay.dropbearssh"
BRIDGE_PORT="18022"
BRIDGE_PIDFILE="${BASEDIR}/etc/bridge.pid"

if [ ! -d "${TARGET_DIR}" ]; then
    echo "Not installed — run: kpm install dropbear-ssh"
    exit 1
fi

# Start the loopback HTTP bridge if it isn't already listening — same
# pidfile + /proc liveness pattern as dropbear's own check below, so
# repeated launches don't pile up duplicate `nc -lk` listeners. Unlike
# dropbear, nc doesn't fork away from this shell, so $! is the actual
# running process (no equivalent of dropbear's own -P needed).
if ! { [ -f "${BRIDGE_PIDFILE}" ] && [ -d "/proc/$(cat "${BRIDGE_PIDFILE}" 2>/dev/null)" ]; }; then
    # </dev/null here for the exact same reason it matters on dropbear's
    # own invocation below: this is a long-running background process, so
    # without it, it inherits stdin from whatever launched this script —
    # harmless from an interactive kterm shell, but confirmed the hard
    # way that `kpm launch` (via the Library scriptlet or the search bar)
    # hangs waiting for that pipe's EOF, which a forever-running listener
    # never provides.
    nohup nc -lk -p "${BRIDGE_PORT}" -e "${TARGET_DIR}/bridge_handler.sh" \
        </dev/null >"${BASEDIR}/bridge.log" 2>&1 &
    echo $! > "${BRIDGE_PIDFILE}"
fi

if [ -f "${PIDFILE}" ] && [ -d "/proc/$(cat "${PIDFILE}" 2>/dev/null)" ]; then
    RUNNING=true
    KINDLE_IP=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
else
    RUNNING=false
    KINDLE_IP=""
fi

if [ -f "${KEEPAWAKE_PIDFILE}" ] && [ -d "/proc/$(cat "${KEEPAWAKE_PIDFILE}" 2>/dev/null)" ]; then
    KEEPAWAKE=true
else
    KEEPAWAKE=false
fi

cat > "${TARGET_DIR}/status.json" <<EOF
{
  "time": "$(date '+%H:%M:%S')",
  "running": ${RUNNING},
  "port": ${PORT},
  "bridge_port": ${BRIDGE_PORT},
  "ip": "${KINDLE_IP}",
  "password": "$(cat "${PASSFILE}" 2>/dev/null)",
  "keepawake": ${KEEPAWAKE}
}
EOF

# A plain `start` just re-raises an already-backgrounded mesquite process
# without reloading the page — confirmed the hard way (DOMContentLoaded
# never refires, so the webview keeps showing whatever status.json said
# the first time). Stop first (appmgrd's own graceful stop, not a raw
# kill) so every open gets a genuinely fresh process and page load.
lipc-set-prop com.lab126.appmgrd stop app://${APP_ID} 2>/dev/null
sleep 1
nohup lipc-set-prop com.lab126.appmgrd start app://${APP_ID} </dev/null >/dev/null 2>&1 &
