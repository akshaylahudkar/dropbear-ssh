#!/bin/sh
# Starts dropbear on demand, over WiFi (no usbnet tunnel needed if the
# device already has WiFi network connectivity).
BASEDIR="/mnt/us/usbnetlite"
BINDIR="${BASEDIR}/bin"
PASSFILE="${BASEDIR}/etc/ssh_password"
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

if ps | grep -q '[d]ropbearmulti dropbear'; then
    echo "Already running."
    exit 0
fi

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
# 0.0.0.0: prefix forces IPv4-only bind — a bare port makes dropbear also try
#          an IPv6 wildcard bind, which fails with "Address family not
#          supported" since Kindle kernels have no IPv6 support at all.
nohup "${BINDIR}/dropbearmulti" dropbear -R -p "0.0.0.0:${PORT}" -Y "${PASSWORD}" \
    >"${BASEDIR}/dropbear.log" 2>&1 &

KINDLE_IP=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
[ -z "${KINDLE_IP}" ] && KINDLE_IP="<kindle-ip — check Settings > Wi-Fi > (i) on the device>"

echo "SSH server starting on port ${PORT} (pid $!)."
echo "Connect: ssh -p ${PORT} root@${KINDLE_IP}   (sftp: same port)"
