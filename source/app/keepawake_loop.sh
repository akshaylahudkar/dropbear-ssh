#!/bin/sh
# Confirmed working on a real device: powerd only lets you defer suspend
# during the brief "readyToSuspend" state (it rejects the same call at any
# other time with lipcErrNoSuchProperty) — so this listens for that event
# and re-defers every time it fires, indefinitely, rather than trying to
# set it once. Verified this holds a device in readyToSuspend for several
# minutes straight instead of it dropping to full sleep (which kills WiFi,
# and with it, the SSH server).
#
# Run via setsid by bridge_handler.sh so it's a fully independent session,
# same reasoning as dropbearmulti's own setsid — otherwise closing the app
# would kill this too.
lipc-wait-event -m com.lab126.powerd readyToSuspend 2>/dev/null | while read -r _; do
    /usr/bin/powerd_test -d 30 >/dev/null 2>&1
done
