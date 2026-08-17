#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 missing-foss
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Pre-push verification gate for trobar-garmin. Run from the repo root:
#   dev/verify.sh
# This is the ONLY place the compile and the simulator tests are checked.
# CI (.github/workflows/ci.yml) runs the source-only subset — version
# consistency, packaged defaults, gitleaks, REUSE lint. Install the SDK +
# device data yourself (e.g. via connect-iq-sdk-manager-cli or the official
# SDK Manager) and generate key.der (gitignored) to exercise the build step
# here.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
# An SDK installed by connect-iq-sdk-manager isn't on PATH by default, so
# without this the build step below skips on a machine that can build
# perfectly well. Shared with dev/run-tests.sh so the two can't disagree.
. dev/sdk-on-path.sh
fail=0
step() { echo; echo "== $1 =="; }

step "connect iq build (compile smoke check)"
if command -v monkeyc >/dev/null 2>&1; then
  if [ ! -f key.der ]; then
    echo "SKIP (no local key.der — see the Build section in README.md for how to generate one)"
  else
    monkeyc -f monkey.jungle -d fenix5plus -o bin/app.prg -y key.der -w -l 3 && echo ok || fail=1
  fi
else
  echo "SKIP (Connect IQ SDK not installed locally) — nothing else runs this; it is checked here or not at all"
fi

step "unit tests (Toybox.Test in the simulator)"
# Delegated rather than inlined: the run needs a test build, a running
# simulator, a connection retry loop and fail-closed output parsing
# (monkeydo exits 1 even when everything passes). Exit 2 means "toolchain
# not available here", which is a SKIP, not a pass — anything else non-zero
# is a real failure.
dev/run-tests.sh
test_rc=$?
if [ "$test_rc" -eq 0 ]; then
  : # run-tests.sh already printed its own "ok"
elif [ "$test_rc" -eq 2 ]; then
  echo "(skipped — see message above; nothing else runs them, CI included)"
else
  fail=1
fi

step "version consistency (VERSION vs manifest.xml)"
version_file=$(tr -d '[:space:]' < VERSION 2>/dev/null)
manifest_version=$(grep -oE 'version="[0-9]+\.[0-9]+\.[0-9]+"' manifest.xml | head -1 | tr -d 'version="')
if [ -z "$version_file" ] || [ -z "$manifest_version" ]; then
  echo "MISSING: could not read VERSION or manifest.xml's version attribute"; fail=1
elif [ "$version_file" != "$manifest_version" ]; then
  echo "MISMATCH: VERSION=$version_file manifest.xml version=$manifest_version"; fail=1
else
  echo "ok ($version_file)"
fi

step "properties.xml defaults (trobar-garmin#17 — no baked-in test values)"
python3 dev/check_properties_defaults.py && echo ok || fail=1

step "leak scan (strings that must never ship)"
# The pattern list is NOT in this repository. A denylist that ships the terms
# it exists to exclude publishes exactly what it is protecting -- which is what
# used to happen here. Supply one via LEAK_PATTERNS to run it; with no
# list configured this reports that it did not run rather than passing.
if [ -n "${LEAK_PATTERNS:-}" ] && [ -s "${LEAK_PATTERNS}" ]; then
  if git ls-files | xargs grep -InE -f "${LEAK_PATTERNS}" 2>/dev/null; then
    echo "LEAK: forbidden term(s) above"; fail=1
  else
    echo "ok"
  fi
else
  echo "SKIP (no LEAK_PATTERNS configured)"
fi

step "gitleaks (secrets)"
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks git --no-banner . && echo ok || fail=1
else
  echo "SKIP (gitleaks not installed) — CI still runs it"
fi

step "REUSE (per-file SPDX licensing)"
if command -v reuse >/dev/null 2>&1; then
  if reuse lint >/dev/null 2>&1; then echo ok; else reuse lint | tail -20; fail=1; fi
else
  echo "SKIP (reuse not installed — pipx install reuse) — CI still runs it"
fi

step "Tracker references in published prose"
# Public docs must stand alone: an issue number that outlives the tracker it
# points at is worse than no citation. Excludes fenced blocks, inline code, hex
# colours and heading anchors -- a guard that false-positives gets switched
# off, and then protects nothing.
if python3 dev/check-tracker-refs.py docs README.md SECURITY.md CONTRIBUTING.md; then
  echo ok
else
  fail=1
fi

echo
step "Toolchain pin agrees with CI"
# .tool-versions is the source of truth; CI must not drift from it. Deliberately
# a consistency check rather than making CI read the exact string: setup-java's
# acceptance of a "17.0.20+8" style version is not something this repo can test,
# and a check that both agree catches the drift either way.
if [ -f .tool-versions ]; then
  tv_java=$(awk '/^java /{print $2}' .tool-versions | sed 's/^temurin-//; s/\..*//')
  ci_java=$(grep -hoE 'java-version: *"?[0-9]+' .github/workflows/*.yml 2>/dev/null | grep -oE '[0-9]+' | sort -u)
  if [ -n "$tv_java" ] && [ -n "$ci_java" ] && [ "$tv_java" != "$ci_java" ]; then
    echo "PIN DRIFT: .tool-versions says java $tv_java, CI says $ci_java"; fail=1
  else
    echo ok
  fi
else
  echo "SKIP (no .tool-versions in this repo)"
fi

echo
if [ "$fail" -eq 0 ]; then echo "VERIFY OK"; else echo "VERIFY FAILED"; fi
exit "$fail"
