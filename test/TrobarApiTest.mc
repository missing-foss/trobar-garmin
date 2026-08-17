// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
using Toybox.Test;
using Toybox.Lang;

// URL handling: the join every request goes through, and the normalization
// that decides whether the user's typed server URL is usable at all.
//
// The requests themselves can't run here — makeWebRequest needs a network
// and a server — so what's pinned is the string that would be requested.

(:test)
function testJoinLeavesACleanUrlAlone(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqual(
        TrobarApi._join("https://trobar.example.com", "/api/device/changes") as Lang.Object,
        "https://trobar.example.com/api/device/changes");
    return true;
}

(:test)
function testJoinStripsATrailingSlash(logger as Test.Logger) as Lang.Boolean {
    // The bug this fixes: a URL pasted from a browser address bar produced
    // "https://host//api/...", which 404s unless something upstream
    // collapses duplicate slashes.
    Test.assertEqual(
        TrobarApi._join("https://trobar.example.com/", "/api/device/changes") as Lang.Object,
        "https://trobar.example.com/api/device/changes");
    Test.assertEqual(
        TrobarApi._join("https://trobar.example.com///", "/api/device/ack") as Lang.Object,
        "https://trobar.example.com/api/device/ack");
    return true;
}

(:test)
function testJoinStripsSurroundingWhitespace(logger as Test.Logger) as Lang.Boolean {
    // Copy-paste on a phone keyboard picks up spaces; a leading one makes
    // the whole URL unrequestable rather than merely ugly.
    Test.assertEqual(
        TrobarApi._join("  https://trobar.example.com/  ", "/api/device/changes") as Lang.Object,
        "https://trobar.example.com/api/device/changes");
    Test.assertEqual(
        TrobarApi._join("\thttps://trobar.example.com\n", "/api/device/changes") as Lang.Object,
        "https://trobar.example.com/api/device/changes");
    return true;
}

(:test)
function testJoinKeepsAPathPrefix(logger as Test.Logger) as Lang.Boolean {
    // Trobar behind a reverse proxy at a sub-path — only the trailing
    // slash goes, never a path segment the user meant to keep.
    Test.assertEqual(
        TrobarApi._join("https://example.com/trobar/", "/api/device/changes") as Lang.Object,
        "https://example.com/trobar/api/device/changes");
    return true;
}

(:test)
function testJoinBuildsTheFileUrl(logger as Test.Logger) as Lang.Boolean {
    // The one call site that appends an id to the path rather than passing
    // a constant.
    Test.assertEqual(
        TrobarApi._join("https://trobar.example.com/", "/api/device/file/" + 42) as Lang.Object,
        "https://trobar.example.com/api/device/file/42");
    return true;
}

(:test)
function testNormalizeAcceptsBothSchemes(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqual(
        TrobarApi.normalizeServerUrl("https://trobar.example.com") as Lang.Object,
        "https://trobar.example.com");
    // Plain http stays allowed: a self-hosted Trobar on a home LAN is a
    // normal deployment, and refusing it here would lock those users out.
    Test.assertEqual(
        TrobarApi.normalizeServerUrl("http://trobar.example.com:5000") as Lang.Object,
        "http://trobar.example.com:5000");
    return true;
}

(:test)
function testNormalizeCleansUpAsItAccepts(logger as Test.Logger) as Lang.Boolean {
    Test.assertEqual(
        TrobarApi.normalizeServerUrl("  https://trobar.example.com/ ") as Lang.Object,
        "https://trobar.example.com");
    return true;
}

(:test)
function testNormalizeAcceptsACapitalisedScheme(logger as Test.Logger) as Lang.Boolean {
    // URI schemes are case-insensitive (RFC 3986 §3.1), and a phone
    // keyboard auto-capitalising the first character of a text field is
    // exactly how this arrives — rejecting it would be a smaller version
    // of the bug this change fixes.
    Test.assertEqual(
        TrobarApi.normalizeServerUrl("Https://trobar.example.com") as Lang.Object,
        "https://trobar.example.com");
    Test.assertEqual(
        TrobarApi.normalizeServerUrl("HTTPS://trobar.example.com") as Lang.Object,
        "https://trobar.example.com");
    Test.assertEqual(
        TrobarApi.normalizeServerUrl("HTTP://trobar.example.com:5000") as Lang.Object,
        "http://trobar.example.com:5000");
    return true;
}

(:test)
function testNormalizeLeavesEverythingAfterTheSchemeAlone(logger as Test.Logger) as Lang.Boolean {
    // Only the scheme is folded. Path case is significant, so a sub-path
    // must survive exactly as typed even when the scheme was capitalised.
    Test.assertEqual(
        TrobarApi.normalizeServerUrl("HTTPS://Trobar.Example.com/Music/") as Lang.Object,
        "https://Trobar.Example.com/Music");
    return true;
}

(:test)
function testNormalizeRejectsAMissingScheme(logger as Test.Logger) as Lang.Boolean {
    // Rejected rather than guessed at: prepending https:// for the user
    // would silently pick a scheme their server may not serve, and the
    // failure would be just as opaque. Null here becomes "not configured",
    // which points at the settings field.
    Test.assert(TrobarApi.normalizeServerUrl("trobar.example.com") == null);
    Test.assert(TrobarApi.normalizeServerUrl("//trobar.example.com") == null);
    Test.assert(TrobarApi.normalizeServerUrl("ftp://trobar.example.com") == null);
    return true;
}

(:test)
function testNormalizeRejectsEmptyAndDegenerateInput(logger as Test.Logger) as Lang.Boolean {
    Test.assert(TrobarApi.normalizeServerUrl("") == null);
    Test.assert(TrobarApi.normalizeServerUrl("   ") == null);
    Test.assert(TrobarApi.normalizeServerUrl("/") == null);
    // A scheme with no host: "https://" trims to "https:" and must not
    // read as a usable URL.
    Test.assert(TrobarApi.normalizeServerUrl("https://") == null);
    Test.assert(TrobarApi.normalizeServerUrl("http://") == null);
    return true;
}

(:test)
function testNormalizeRejectsNonStrings(logger as Test.Logger) as Lang.Boolean {
    // Properties.getValue returns whatever storage holds, and an app
    // upgrade can change a property's type — this must degrade to "not
    // configured" rather than throw on the way to a sync.
    Test.assert(TrobarApi.normalizeServerUrl(null) == null);
    Test.assert(TrobarApi.normalizeServerUrl(42 as Lang.Object) == null);
    return true;
}
