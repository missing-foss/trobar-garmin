#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 missing-foss
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Puts the Connect IQ SDK's bin directory on PATH if it isn't already.
# Source it, don't run it:
#   . dev/sdk-on-path.sh
#
# connect-iq-sdk-manager installs the SDK under ~/.Garmin and puts nothing
# on PATH, so a perfectly working SDK looks absent to a plain shell — which
# made dev/verify.sh skip its build step on a machine that could build
# fine. Both verify.sh and run-tests.sh source this so they can never
# disagree about whether the toolchain is present. CI puts the SDK on PATH
# itself (the sdk-manager reports the path there), so this is a no-op for
# it.
#
# Newest SDK wins when several are installed. sort -V, not sort -r: a plain
# lexicographic sort puts 7.9.0 above 7.10.0, so the day Garmin ships a
# .10 the "newest" would silently become the older one.
if ! command -v monkeyc >/dev/null 2>&1; then
  for _ciq_bin in $(ls -d "$HOME"/.Garmin/ConnectIQ/Sdks/*/bin 2>/dev/null | sort -Vr); do
    if [ -x "$_ciq_bin/monkeyc" ]; then
      PATH="$_ciq_bin:$PATH"
      export PATH
      break
    fi
  done
  unset _ciq_bin
fi
