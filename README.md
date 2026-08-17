<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Trobar for Garmin

[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/missing-foss/trobar-garmin/badge)](https://securityscorecards.dev/viewer/?uri=github.com/missing-foss/trobar-garmin)

Trobar on your Garmin watch. Bring the bard up the hills!

The Garmin Connect IQ client of [Trobar](https://github.com/missing-foss/trobar-server)
— self-hosted music library sync. An **Audio Content Provider** app: it plugs
into the watch's own native Music player (like the Spotify/Deezer tiles),
supplying pairing, sync, and content — not a bespoke Trobar player screen.

## Status

Pairing, sync, and native playback are implemented. Not yet on the
Connect IQ Store — see [Releasing](#releasing) below for sideloading a signed
build. Supported device: `fenix5plus` only, for now. See the
[open issues](https://github.com/missing-foss/trobar-garmin/issues) for
current progress.

### Requesting another watch model

Own a different Music-capable Garmin watch? Open an issue using the
[**Request watch model support**](https://github.com/missing-foss/trobar-garmin/issues/new?template=watch_model_request.yml)
template — it asks for the exact model/variant, whether it's Music-capable
(onboard music storage; Connect IQ's Audio Content Provider category, which
this app uses, only runs on those), and optionally its Connect IQ device
id, firmware, and screen shape/resolution.

Adding a device id to the manifest is a one-line change, and compiling for
it takes minutes. **Whether you can sideload a test build and report back is the
real unblocker**: the maintainer only owns a fēnix 5 Plus, so a model can
be built blind but shouldn't be called "supported" until someone with that
watch has confirmed pair → sync → playback actually works on it. A request
that includes "I have this watch and can test" is far more likely to get
done than one that doesn't.

## Build (development)

Requires the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/),
device simulator data for `fenix5plus` (downloading it needs a logged-in
Garmin account — see
[connect-iq-sdk-manager-cli](https://github.com/lindell/connect-iq-sdk-manager-cli)
for a CLI-friendly way to do this), and a throwaway developer key — fine for
a local compile smoke-check, **not** for a build you intend to install and
keep updating (see [Releasing](#releasing)):

```
openssl genrsa -out key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in key.pem -out key.der -nocrypt
monkeyc -f monkey.jungle -d fenix5plus -o bin/app.prg -y key.der -w -l 3
```

`dev/verify.sh` runs the full check set locally — compile, unit tests,
version consistency, packaged defaults, gitleaks and REUSE lint. CI runs the
source-only subset: everything except the compile and the simulator tests.
**Run `dev/verify.sh` before opening a PR** — it is the only place those two
get checked.

## Releasing

There's no Connect IQ Store listing yet, so releases are a signed `.prg`
attached to a GitHub Release, sideloaded by copying it into the watch's
`GARMIN/APPS` folder over USB.

**The signing key never changes** — once a release is signed and installed,
only the same key can ever sign an update for that install. It is generated
once, kept local to whoever builds releases, and never held in CI or in a
repository secret. **Back it up before you need it — there is no recovery if
it is lost.**

Building your own signed copy? Generate a key once:

```
openssl genrsa -out key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in key.pem -out developer-key.der -nocrypt
rm key.pem
chmod 600 developer-key.der
```

then build with it:

```
monkeyc -f monkey.jungle -d fenix5plus -o bin/trobar-garmin.prg -y developer-key.der -w -l 3
```

**[`VERSION`](VERSION) and `manifest.xml`'s own `version="..."` attribute must
match** — both are metadata only; neither is compiled into a sideloaded
`.prg` (confirmed by testing: building with and without the manifest
attribute produces a byte-identical binary). The manifest attribute is
Connect IQ **Store**-submission metadata; `VERSION` plus the release tag is
the actual source of truth for this sideload-only distribution.
`dev/verify.sh` and CI both check the two agree anyway, so there's exactly
one place version bumps happen — bump both together in the same change,
before tagging.

Building the SDK-dependent parts needs a Garmin-account login — see
[connect-iq-sdk-manager-cli](https://github.com/lindell/connect-iq-sdk-manager-cli)
above. Releases are built and signed locally; no signing key is ever held in
CI, by design — same as `trobar-android`'s APK releases.

## Documentation

Full docs live on the
[Trobar documentation site](https://missing-foss.github.io/trobar-server/).

## License

`GPL-3.0-or-later` — see [LICENSE](LICENSE). Contributions are welcome
under the same license; see [CONTRIBUTING.md](CONTRIBUTING.md).

Contributing a translation? See [Translating Trobar](https://missing-foss.github.io/trobar-server/project/translations/) — this app's section covers the `monkey.jungle` resource-path gotcha that silently ships English if missed.
