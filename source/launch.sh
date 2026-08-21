#!/bin/sh
# Starts dropbear on demand, over WiFi (no usbnet tunnel needed if the
# device already has WiFi network connectivity).
BASEDIR="/mnt/us/usbnetlite"
BINDIR="${BASEDIR}/bin"
PASSFILE="${BASEDIR}/etc/ssh_password"
PIDFILE="${BASEDIR}/etc/dropbear.pid"
PORT="2022"

# Self-heal rather than fall back to a fixed/guessable password if the
# password file is ever missing (this has happened in practice — a shared
# BASEDIR getting wiped by another package's uninstall).
PASSWORD=$(cat "${PASSFILE}" 2>/dev/null)
if [ -z "${PASSWORD}" ]; then
    PASSWORD=$(dd if=/dev/urandom bs=1 count=6 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
    [ -z "${PASSWORD}" ] && PASSWORD="kp$$$(date +%s 2>/dev/null)"
    mkdir -p "${BASEDIR}/etc"
    echo "${PASSWORD}" > "${PASSFILE}"
    echo "No password file found — generated a new one: ${PASSWORD}"
fi

# PID-file + /proc liveness check — more reliable than pattern-matching
# `ps` output (which silently broke on this device's busybox: CMD gets
# truncated to argv[0] with no arguments, so a fuller pattern never
# matched, and every launch tried — and silently failed — to bind an
# already-occupied port instead of detecting the existing server). The
# PID file itself is written by dropbear's own -P flag below, not
# guessed from $! — dropbear forks into the background by default (no
# -F), so $! from this shell would only be the pre-fork process, not
# the one that actually keeps running.
if [ -f "${PIDFILE}" ] && [ -d "/proc/$(cat "${PIDFILE}" 2>/dev/null)" ]; then
    echo "Already running."
    exit 0
fi
rm -f "${PIDFILE}"

# Stock firmware's INPUT chain default-policies to DROP and only allow-lists
# a couple of Amazon-service ports, so inbound connections on our SSH port
# get silently dropped unless we open it explicitly. This rule is runtime
# kernel state (not a file), so it doesn't survive reboot — reapply it every
# launch. -C checks whether it's already there so repeated launches don't
# pile up duplicate rules.
iptables -C INPUT -p tcp --dport "${PORT}" -j ACCEPT 2>/dev/null || \
    iptables -I INPUT -p tcp --dport "${PORT}" -j ACCEPT

# -R: create host keys on first run if missing (written to the hardcoded
#     /mnt/us/usbnetlite/etc/dropbear/dropbear_*_host_key paths)
# -Y: master password — logs in as root with this password, no key needed
# -K 60: send a keepalive every 60s so a session killed by the Kindle
#        suspending WiFi (which cuts the link with no FIN, not a clean
#        close) gets reaped instead of lingering as a zombie connection
#        forever — verified on-device: a K=0 session survived 7+ hours
#        past its client vanishing, a K=5 test session was reaped within
#        one dead-link window.
# -I 1800: also close sessions idle 30+ min regardless of link state, as
#          a backstop (distinct mechanism from -K — this doesn't detect
#          dead peers, just closes stale-but-technically-alive ones).
# 0.0.0.0: prefix forces IPv4-only bind — a bare port makes dropbear also try
#          an IPv6 wildcard bind, which fails with "Address family not
#          supported" since Kindle kernels have no IPv6 support at all.
# -P: dropbear writes its own (post-fork) pid here — see the liveness
#     check above for why this is used instead of the backgrounding
#     shell's $!.
nohup "${BINDIR}/dropbearmulti" dropbear -R -p "0.0.0.0:${PORT}" -Y "${PASSWORD}" -K 60 -I 1800 -P "${PIDFILE}" \
    >"${BASEDIR}/dropbear.log" 2>&1 &

KINDLE_IP=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
[ -z "${KINDLE_IP}" ] && KINDLE_IP="<kindle-ip — check Settings > Wi-Fi > (i) on the device>"

echo "SSH server starting on port ${PORT}."
echo "Connect: ssh -p ${PORT} root@${KINDLE_IP}   (sftp: same port)"
