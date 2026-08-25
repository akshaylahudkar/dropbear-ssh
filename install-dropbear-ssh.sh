#!/bin/sh
# Name: Install Dropbear SSH
# Author: Akshay
# DontUseFBInk
#
# One-tap bootstrap: adds the repo, installs, and launches dropbear-ssh —
# entirely via kpm's full path, no search bar involved. Drop this file in
# the Kindle's documents/ folder via USB (same as sideloading a book) and
# tap "Install Dropbear SSH" on the Home screen/Library to run it. Safe to
# re-run: add-repo no-ops if already added, install upgrades in place.
KPM=/var/local/kmc/bin/kpm
$KPM add-repo https://nealing.net/manifest.json
$KPM install dropbear-ssh
$KPM launch dropbear-ssh
