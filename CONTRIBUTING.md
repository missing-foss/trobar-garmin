<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Contributing

This is the Garmin client of Trobar — the contribution guidelines, issue
tracker conventions, and dev-environment notes live in the main server
repository's `CONTRIBUTING.md` and `docs/`. Short version: open an issue
before large PRs, `dev/verify.sh` must pass, contributions are
`GPL-3.0-or-later` like the client itself.

Public issues and PRs live here on GitHub.

Contributing a translation? See [Translating Trobar](https://missing-foss.github.io/trobar-server/project/translations/).

## Running the unit tests

```
dev/run-tests.sh          # or just dev/verify.sh, which calls it
```

The suite lives in `test/`, uses Connect IQ's own `Toybox.Test` framework,
and covers the parts of the app that are pure logic: `.m3u8` parsing,
play-order computation, enrollment-response handling, playback navigation
and status text. Anything that needs the network or a real watch is
deliberately not covered here.

A few things about this toolchain are worth knowing before you add a test.

**Test code cannot reach the shipped app.** `monkey.jungle` puts `test/` on
the source path, but `monkeyc` only compiles `(:test)`-annotated code when
`-t` is passed. Everything in `test/` carries that annotation, including
the helper classes. To re-check that for yourself: build with and without
`-t` and grep the two `.prg` files for a test function's name.

**The simulator will not start on Ubuntu 24.04 or newer.** It links against
`libwebkit2gtk-4.0-37`, `libjavascriptcoregtk-4.0-18` and `libsoup2.4-1`,
which 24.04 doesn't package at all (it ships the 4.1/soup3 flavour), so the
binary fails in the dynamic loader. `dev/run-tests.sh` detects this and
re-runs the simulator inside an `ubuntu:22.04` container against your own
SDK and device data — you need docker, but nothing else. On 22.04 it runs
the simulator directly. If neither works it exits 2 and `dev/verify.sh`
reports a skip — locally that's fine, but CI treats exit 2 as a failure:
everything the script needs is installed by the steps before it, so a skip
on a runner means that setup broke rather than that the suite is
unavailable.

The container installs its dependencies on every run, which costs about 40
seconds. If you run the tests often, bake them into an image once and point
the script at it:

```
dev/run-tests.sh --build-image
TROBAR_CIQ_IMAGE=trobar-ciq-test:local dev/run-tests.sh
```

The image is built from the same package list *and the same base* the script
runs against, so there's no second copy of either to fall out of date. Two
variables, and you rarely need more than the first:

| Variable | What it pins | Who sets it |
|---|---|---|
| `TROBAR_CIQ_IMAGE` | an already-built image to run in | `ci.yml`, to a digest |
| `TROBAR_CIQ_BASE` | the base to run in *and* to bake `--build-image` from | you, if you want a reproducible prebaked image |

Left alone, both default to the `ubuntu:22.04` tag, which is what you want
locally.

**`monkeydo` exits 1 whether the suite passed or failed**, so never gate on
its status — `dev/run-tests.sh` parses its output instead, and treats a
missing results line or a zero-test run as a failure.

**Strict type-checking (`-l 3`) applies to test code too.** `Test.assertEqual`
takes two `Lang.Object` values, so anything the compiler types as `Any`
(indexing into a `Lang.Array`) or as a poly type (`Storage.getValue`) needs
an explicit `as Lang.Object` cast at the call site or the test build won't
compile. Writing a `Lang.Array` into storage has the same problem in
reverse: build it as a `Lang.Array` and cast the finished value, rather than
casting an array literal to `Storage.ValueType`.

**The simulator's `Application.Storage` is real and persists between runs**,
and test order isn't guaranteed. Reset the state you touch as the *first*
statement of a test (`TestSupport.resetStorage()`), not the last — a failed
assertion throws, so cleanup at the end never runs. That helper clears
`Properties` (`serverUrl`, `enrollCode`) as well as storage keys, for the
same reason; `Properties` has no `deleteValue`, so `""` is the cleared
state.

One test, `testRedeemTokenlessSuccess`, documents behaviour rather than
endorsing it: a `200` response with no `token` in the body leaves the watch
unpaired while telling the sync delegate that pairing succeeded, so the
sync that follows fails as "not configured" and the real cause is lost.
It's pinned so a future fix is a deliberate change rather than an accident.

## Pull requests

Pull requests opened here are reviewed and then shipped by the maintainers
rather than merged in place, so your commits may arrive under a release
commit rather than your own. Your pull request is closed with a note
crediting you when the change lands. Keep changes focused — a small pull
request with a clear rationale is much easier to take than a large one.

CI here runs source checks only, so a pull request from a fork gets exactly
the same result as any other. The device compile and the simulator tests run
**only** in `dev/verify.sh` — please run it locally before opening a pull
request.

Security issues: not in the public tracker — missing_foss@etik.com.
