#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 missing-foss
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Builds and runs the Toybox.Test (:test) suite (trobar-garmin#33).
# Run from anywhere in the repo:
#   dev/run-tests.sh
#   dev/run-tests.sh --build-image [tag]   # optional, see CONTRIBUTING.md
#
# Exit codes: 0 = every test passed, 1 = failures (or the run didn't
# produce a usable result), 2 = skipped because the toolchain isn't here.
# dev/verify.sh distinguishes all three; nothing else should treat 2 as
# success.
#
# Connect IQ has no headless test runner: (:test) code executes inside the
# graphical simulator, driven by monkeydo. Two facts shape everything
# below.
#
# 1. The simulator binary needs the GTK/WebKit2-soup2 stack, which Ubuntu
#    24.04 does not ship and does not package at all — libwebkit2gtk-4.0-37,
#    libjavascriptcoregtk-4.0-18 and libsoup2.4-1 have no candidate in the
#    noble archive (only the 4.1/soup3 flavour). On such a host the binary
#    dies in the dynamic loader before main(). So when the libraries are
#    missing and docker is available, the simulator runs in an ubuntu:22.04
#    container against the host's own SDK and device data. Compilation is
#    pure Java and happens on the host either way.
#
# 2. monkeydo exits 1 whether the suite passed or failed (verified both
#    ways), so its status tells you nothing. The result has to be parsed
#    out of its output, and parsed fail-closed: no results line at all —
#    the simulator never came up, the run was killed — must fail, and so
#    must a suite that ran zero tests, since "nothing ran" and "nothing was
#    wrong" print almost the same thing.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

DEVICE="${DEVICE:-fenix5plus}"
PRG="bin/test.prg"
# Baking these packages into an image once turns a ~40s apt step into a
# ~1s container start: dev/run-tests.sh --build-image does exactly that,
# from this same list, so there is no second copy of it to drift.
# The base is named ONCE (trobar-garmin#52). It is both the default image to
# run in and the FROM of the image --build-image bakes, so the prebaked image
# can't quietly be built on a different base than the one the plain path runs
# — which is what happened when this said `FROM ubuntu:22.04` literally while
# CI pinned a digest through TROBAR_CIQ_IMAGE.
#
# Pin either one: TROBAR_CIQ_BASE pins what gets run AND what gets baked;
# TROBAR_CIQ_IMAGE points at an already-built image (what ci.yml sets). The
# floating tag stays the default so local use needs no ceremony.
BASE_IMAGE="${TROBAR_CIQ_BASE:-ubuntu:22.04}"
IMAGE="${TROBAR_CIQ_IMAGE:-$BASE_IMAGE}"
CONTAINER_PACKAGES="openjdk-17-jre-headless xvfb libwebkit2gtk-4.0-37 libsecret-1-0 libsoup2.4-1 libgtk-3-0 libusb-1.0-0 libasound2 libnss3"

if [ "${1:-}" = "--build-image" ]; then
  tag="${2:-trobar-ciq-test:local}"
  printf 'FROM %s\nRUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive \\\n    apt-get install -y -qq --no-install-recommends %s\n' \
    "$BASE_IMAGE" "$CONTAINER_PACKAGES" | docker build -t "$tag" - || exit 1
  echo "built $tag from $BASE_IMAGE — use it with: TROBAR_CIQ_IMAGE=$tag dev/run-tests.sh"
  exit 0
fi

. dev/sdk-on-path.sh

if ! command -v monkeyc >/dev/null 2>&1; then
  echo "SKIP (Connect IQ SDK not installed locally — see .github/workflows/ci.yml)"
  exit 2
fi

# The signing key is irrelevant to a test run — monkeyc simply refuses to
# emit a .prg without one — so a throwaway key is generated when the repo
# has none, rather than making every contributor produce one by hand.
KEY="key.der"
TMPKEY=""
cleanup() {
  [ -n "$TMPKEY" ] && rm -rf "$(dirname "$TMPKEY")"
}
trap cleanup EXIT
if [ ! -f "$KEY" ]; then
  if ! command -v openssl >/dev/null 2>&1; then
    echo "SKIP (no key.der and no openssl to generate a throwaway one)"
    exit 2
  fi
  TMPKEY="$(mktemp -d)/key.der"
  openssl genrsa -out "${TMPKEY%.der}.pem" 4096 2>/dev/null &&
    openssl pkcs8 -topk8 -inform PEM -outform DER \
      -in "${TMPKEY%.der}.pem" -out "$TMPKEY" -nocrypt 2>/dev/null || {
    echo "FAILED to generate a throwaway signing key"; exit 1; }
  KEY="$TMPKEY"
fi

echo "building $PRG (-t)"
if ! monkeyc -f monkey.jungle -d "$DEVICE" -o "$PRG" -y "$KEY" -w -l 3 -t; then
  echo "FAILED to compile the test build"
  exit 1
fi

# monkeydo has to connect to an already-running simulator, and there's no
# readiness signal to wait on — polling for a listening port guesses at an
# undocumented port number. Retrying the connection is the honest version
# of the same wait: it asks the only question that matters.
run_suite() {
  # mktemp, not a fixed /tmp path: a predictable name in a world-writable
  # directory is a symlink someone else can plant.
  local sim_log
  sim_log="$(mktemp -t trobar-simulator.XXXXXX.log)"
  # setsid puts xvfb-run and everything it spawns — Xvfb and the simulator
  # itself — in their own process group, so one signal takes all of them.
  # Killing xvfb-run alone leaves the simulator running, one stray per run.
  local sim_pid killer
  if command -v setsid >/dev/null 2>&1; then
    setsid xvfb-run -a simulator >"$sim_log" 2>&1 &
    sim_pid=$!
    killer="group"
  else
    xvfb-run -a simulator >"$sim_log" 2>&1 &
    sim_pid=$!
    killer="pid"
  fi
  local out="" attempt
  for attempt in $(seq 1 30); do
    out="$(monkeydo "$PRG" "$DEVICE" -t 2>&1)"
    case "$out" in
      *"Unable to connect to simulator"*) sleep 2 ;;
      *) break ;;
    esac
  done
  if [ "$killer" = "group" ]; then
    kill -- -"$sim_pid" 2>/dev/null
  else
    kill "$sim_pid" 2>/dev/null
  fi
  # A simulator that never came up is the one failure where its own log is
  # the only thing that explains why (a missing shared library says so
  # there and nowhere else), so surface it instead of discarding it.
  case "$out" in
    *"Unable to connect to simulator"*)
      out="$out
--- simulator log ---
$(tail -20 "$sim_log" 2>/dev/null)" ;;
  esac
  rm -f "$sim_log"
  printf '%s\n' "$out"
}

verdict() {
  local out="$1"
  printf '%s\n' "$out"
  # passed=[1-9]... deliberately: a suite where nothing was compiled in
  # reports PASSED (passed=0, failed=0, errors=0), which must not be
  # mistaken for a green run.
  if printf '%s' "$out" | grep -qE 'PASSED \(passed=[1-9][0-9]*, failed=0, errors=0\)'; then
    echo "ok"
    return 0
  fi
  echo "TESTS FAILED (or produced no result — see above)"
  return 1
}

needs_container=0
if ! command -v xvfb-run >/dev/null 2>&1; then
  needs_container=1
elif ldd "$(command -v simulator)" 2>/dev/null | grep -q "not found"; then
  needs_container=1
fi

if [ "$needs_container" -eq 0 ]; then
  verdict "$(run_suite)"
  exit $?
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "SKIP (simulator can't run here — missing libraries or xvfb — and docker isn't available to run it in ubuntu:22.04; see CONTRIBUTING.md)"
  exit 2
fi

# Paths inside the container mirror the host's ~/.Garmin layout under
# /root, so the SDK's own relative lookups (device data, api.db) resolve
# exactly as they do natively. The mount is read-only: the container runs
# as its own root, so under rootful docker anything it created there would
# come back root-owned and lock the host out of its own SDK directory.
# Nothing under ~/.Garmin was modified across repeated runs before this was
# tightened, so read-only costs nothing.
# Both the mount source and the prefix below are RESOLVED to real paths first.
# A bind-mount source cannot be a symlink -- docker refuses with
# "error while creating mount source path ...: file exists" -- and ~/.Garmin
# being a symlink is an ordinary setup, not an exotic one: it is what pointing
# several accounts at one shared SDK looks like. Resolving also keeps the
# prefix match below honest, since otherwise one side is symlinked and the
# other is not and the case simply stops matching.
garmin_root="$(cd "$HOME/.Garmin" 2>/dev/null && pwd -P)" || garmin_root=""
if [ -z "$garmin_root" ]; then
  echo "SKIP (no ~/.Garmin — install the SDK first; see README.md)"
  exit 2
fi
sdk_bin="$(cd "$(dirname "$(command -v monkeyc)")" && pwd -P)"
case "$sdk_bin" in
  "$garmin_root/"*) sdk_in_container="/root/.Garmin/${sdk_bin#"$garmin_root"/}" ;;
  *)
    echo "SKIP (SDK lives at $sdk_bin, outside ~/.Garmin — the container recipe assumes the SDK-manager layout; see CONTRIBUTING.md)"
    exit 2 ;;
esac

echo "running the suite in $IMAGE (this host can't start the simulator directly)"
out="$(docker run --rm \
  -v "$garmin_root":/root/.Garmin:ro \
  -v "$PWD":/work -w /work \
  -e "SDK_BIN=$sdk_in_container" -e "DEVICE=$DEVICE" -e "PRG=$PRG" \
  -e "CONTAINER_PACKAGES=$CONTAINER_PACKAGES" \
  "$IMAGE" bash -c '
    set -uo pipefail
    if ! command -v xvfb-run >/dev/null 2>&1; then
      apt-get update -qq >/dev/null 2>&1
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
        $CONTAINER_PACKAGES >/dev/null 2>&1 || { echo "apt-get failed inside the container"; exit 1; }
    fi
    export PATH="$SDK_BIN:$PATH"
    xvfb-run -a simulator >/tmp/simulator.log 2>&1 &
    for attempt in $(seq 1 30); do
      out="$(monkeydo "$PRG" "$DEVICE" -t 2>&1)"
      case "$out" in
        *"Unable to connect to simulator"*) sleep 2 ;;
        *) break ;;
      esac
    done
    printf "%s\n" "$out"
  ')"
verdict "$out"
exit $?
