#!/bin/sh
# Name: Dropbear SSH
# Author: Akshay
# DontUseFBInk
#
# The one permanent Home-screen entry for this package — no search bar, no
# terminal. Drop this file in the Kindle's documents/ folder via USB (same
# as sideloading a book) and tap "Dropbear SSH" on the Home screen/Library.
# First tap installs and launches; every tap after that just launches —
# so this single file is both the installer and the permanent launcher,
# there's nothing else to drop in later.
#
# Deliberately does NOT call `kpm install` on every tap anymore. Confirmed
# the hard way: kpm install always runs the currently-installed version's
# uninstall hooks first, even when "upgrading" to the exact same version
# already installed — which kills the running SSH server as a side effect
# of simply reopening the app, every single time. Checking whether the
# package is already installed (a plain local directory check, no network
# involved) before deciding whether to install at all avoids that
# entirely. Trade-off: this means reopening no longer auto-updates to a
# newer version — grab a fresh copy of this file (or use kterm) to
# actually upgrade later.
KPM=/var/local/kmc/bin/kpm
if [ ! -d /mnt/us/kmc/kpm/packages/dropbear-ssh ]; then
    $KPM add-repo https://nealing.net/manifest.json
    $KPM install dropbear-ssh
fi
$KPM launch dropbear-ssh
