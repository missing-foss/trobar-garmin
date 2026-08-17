// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
using Toybox.Test;
using Toybox.Lang;
using Toybox.Application.Storage;

// Status text and the can-we-play predicate.
//
// These assert on the *distinctness* and presence of the strings, never on
// their English wording — the copy is translated (resources-fre/) and a
// test that pins exact text would fail for a legitimate rewording while
// still missing the bug that actually happened, which was two different
// failures rendering as the same message (trobar-garmin#12).

(:test)
function testReasonTextDistinguishesFailures(logger as Test.Logger) as Lang.Boolean {
    var invalid = TrobarStatus.reasonText("invalid_code");
    var network = TrobarStatus.reasonText("network");
    var notConfigured = TrobarStatus.reasonText("not_configured");

    Test.assert(invalid.length() > 0);
    Test.assert(network.length() > 0);
    Test.assert(notConfigured.length() > 0);
    // A wrong enrollment code and an unreachable server send the user to
    // completely different places; they must never read the same.
    Test.assert(!invalid.equals(network));
    Test.assert(!invalid.equals(notConfigured));
    Test.assert(!network.equals(notConfigured));
    return true;
}

(:test)
function testReasonTextFallsBackForUnknownReason(logger as Test.Logger) as Lang.Boolean {
    // Reason codes are persisted to Storage, so an older build's value can
    // outlive the code that wrote it. Anything unrecognised must still
    // produce a real message rather than an empty screen.
    var unknown = TrobarStatus.reasonText("something_from_a_future_version");
    Test.assert(unknown.length() > 0);
    Test.assertEqual(unknown as Lang.Object, TrobarStatus.reasonText("not_configured"));
    return true;
}

(:test)
function testCanPlayFollowsPlayOrder(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    Test.assert(!TrobarStatus.canPlay());

    TestSupport.seedPlayOrder([] as Lang.Array);
    // Paired and synced but nothing assigned still means nothing to play.
    Test.assert(!TrobarStatus.canPlay());

    TestSupport.seedPlayOrder([11] as Lang.Array);
    Test.assert(TrobarStatus.canPlay());
    return true;
}

(:test)
function testCanPlayIgnoresSyncStatus(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    TestSupport.seedPlayOrder([11] as Lang.Array);
    Storage.setValue(TrobarStorageKeys.LAST_SYNC_STATUS, "network");

    // The offline case this app exists for: the last sync failed, the
    // cached tracks are still perfectly playable, and Select still starts
    // playback — so the hint must not disappear (trobar-garmin#21).
    Test.assert(TrobarStatus.canPlay());
    return true;
}

(:test)
function testSyncPointerTextOnlyWhenPaired(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    // Empty means "draw nothing", which is what an unpaired watch needs —
    // there is no sync to point at yet.
    Test.assertEqual(TrobarStatus.syncPointerText().length() as Lang.Object, 0);

    Storage.setValue(TrobarStorageKeys.DEVICE_TOKEN, "tok");
    Test.assert(TrobarStatus.syncPointerText().length() > 0);
    return true;
}
