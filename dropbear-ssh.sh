#!/bin/sh
# Name: Dropbear SSH
# Author: Akshay
# DontUseFBInk
#
# The one permanent Home-screen entry for this package — no search bar, no
# terminal. Drop this file in the Kindle's documents/ folder via USB (same
# as sideloading a book) and tap "Dropbear SSH" on the Home screen/Library.
# First tap adds the repo, installs, and launches; every tap after that
# re-affirms the install (add-repo no-ops if already added, install
# upgrades in place, the password file is left alone if it already exists)
# and launches — so this single file is both the installer and the
# permanent launcher, there's nothing else to drop in later.
KPM=/var/local/kmc/bin/kpm
$KPM add-repo https://nealing.net/manifest.json
$KPM install dropbear-ssh
$KPM launch dropbear-ssh
