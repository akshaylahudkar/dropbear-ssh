#!/bin/sh
# Name: Dropbear SSH
# Author: Akshay
# DontUseFBInk
#
# Installer and launcher in one file. Drop it in the Kindle's documents/
# folder over USB and tap "Dropbear SSH" in the Library: the first tap
# installs and launches, later taps only launch.
#
# The install is guarded because `kpm install` runs the installed version's
# uninstall hooks first, even when reinstalling the same version, which
# would kill the running SSH server every time the app is reopened. The
# guard is a local directory check, so no network call on a normal launch.
# Trade-off: reopening will not pull a newer version. Use the app's
# Check for Update button, or `kpm install dropbear-ssh` from kterm.
KPM=/var/local/kmc/bin/kpm
if [ ! -d /mnt/us/kmc/kpm/packages/dropbear-ssh ]; then
    $KPM add-repo https://nealing.net/manifest.json
    $KPM install dropbear-ssh
fi
$KPM launch dropbear-ssh
