// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
using Toybox.Test;
using Toybox.Lang;
using Toybox.Application.Storage;
using Toybox.Application.Properties;

// Enrollment redemption. redeemIfNeeded()'s network call can't run here,
// but every branch either side of it can: the pre-flight checks, and
// _handleRedeemResponse's handling of what comes back.
//
// _pendingOnDone is module state that outlives a single call, so each test
// sets it (via a recorder below) rather than inheriting whatever the last
// one left behind.

// Captures the (paired, failureReason) callback so a test can assert on
// what the delegate would actually have been told — the Storage writes and
// the callback can disagree, which is the point of testRedeemSucceeds and
// testRedeemTokenlessSuccess below.
(:test)
class PairingRecorder {
    var called as Lang.Boolean = false;
    var paired as Lang.Boolean = false;
    var reason as Lang.String or Null = null;

    function initialize() {
    }

    function onDone(pairedResult as Lang.Boolean, failureReason as Lang.String or Null) as Void {
        called = true;
        paired = pairedResult;
        reason = failureReason;
    }
}

(:test)
function testRedeemInvalidCode(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    var recorder = new PairingRecorder();
    TrobarPairing._pendingOnDone = recorder.method(:onDone);

    TrobarPairing._handleRedeemResponse(400, null);

    // 400 is the server saying the code itself is wrong — the one failure
    // the user can actually act on, so it must not be flattened into
    // "network".
    Test.assertEqual(
        Storage.getValue(TrobarStorageKeys.LAST_PAIRING_STATUS) as Lang.Object, "invalid_code");
    Test.assert(recorder.called);
    Test.assert(!recorder.paired);
    Test.assertEqual(recorder.reason as Lang.Object, "invalid_code");
    Test.assert(!TrobarPairing.isPaired());
    return true;
}

(:test)
function testRedeemNetworkFailure(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    var recorder = new PairingRecorder();
    TrobarPairing._pendingOnDone = recorder.method(:onDone);

    // Communications hands back its own negative codes for transport
    // failures; anything that isn't 200 or 400 is reported as network.
    TrobarPairing._handleRedeemResponse(-104, null);

    Test.assertEqual(
        Storage.getValue(TrobarStorageKeys.LAST_PAIRING_STATUS) as Lang.Object, "network");
    Test.assert(!recorder.paired);
    Test.assertEqual(recorder.reason as Lang.Object, "network");
    return true;
}

(:test)
function testRedeemServerErrorIsNetwork(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    var recorder = new PairingRecorder();
    TrobarPairing._pendingOnDone = recorder.method(:onDone);

    TrobarPairing._handleRedeemResponse(500, null);

    Test.assertEqual(
        Storage.getValue(TrobarStorageKeys.LAST_PAIRING_STATUS) as Lang.Object, "network");
    return true;
}

(:test)
function testRedeemSucceeds(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    Storage.setValue(TrobarStorageKeys.LAST_PAIRING_STATUS, "invalid_code");
    var recorder = new PairingRecorder();
    TrobarPairing._pendingOnDone = recorder.method(:onDone);

    TrobarPairing._handleRedeemResponse(
        200, {"token" => "tok-123", "id" => 7, "name" => "Fenix"} as Lang.Dictionary);

    Test.assert(TrobarPairing.isPaired());
    Test.assertEqual(Storage.getValue(TrobarStorageKeys.DEVICE_TOKEN) as Lang.Object, "tok-123");
    Test.assertEqual(Storage.getValue(TrobarStorageKeys.DEVICE_ID) as Lang.Object, 7);
    Test.assertEqual(Storage.getValue(TrobarStorageKeys.DEVICE_NAME) as Lang.Object, "Fenix");
    // A stale failure from an earlier attempt has to be cleared, or the
    // status screen keeps reporting "Pairing failed" on a paired watch.
    Test.assert(Storage.getValue(TrobarStorageKeys.LAST_PAIRING_STATUS) == null);
    Test.assert(recorder.paired);
    Test.assert(recorder.reason == null);
    return true;
}

(:test)
function testRedeemTokenlessSuccess(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    var recorder = new PairingRecorder();
    TrobarPairing._pendingOnDone = recorder.method(:onDone);

    // A 200 whose body carries no token: not expected from trobar-server,
    // but reachable from any proxy or captive portal that answers 200 with
    // something else. Documents current behaviour rather than endorsing
    // it — the callback says "paired" while isPaired() says otherwise, so
    // the sync that follows bails with "not configured" and the real cause
    // is lost. See the note in CONTRIBUTING.md.
    TrobarPairing._handleRedeemResponse(200, {"id" => 7, "name" => "Fenix"} as Lang.Dictionary);

    Test.assert(!TrobarPairing.isPaired());
    Test.assert(recorder.paired);
    Test.assert(recorder.reason == null);
    return true;
}

(:test)
function testRedeemToleratesNoPendingCallback(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    // onStopSync cancels in-flight requests but a cancelled request still
    // fires its callback, so a response can arrive with nothing waiting on
    // it. Storage must still be updated, and nothing may throw.
    TrobarPairing._pendingOnDone = null;

    TrobarPairing._handleRedeemResponse(400, null);

    Test.assertEqual(
        Storage.getValue(TrobarStorageKeys.LAST_PAIRING_STATUS) as Lang.Object, "invalid_code");
    return true;
}

(:test)
function testRedeemClearsPendingCallback(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    var recorder = new PairingRecorder();
    TrobarPairing._pendingOnDone = recorder.method(:onDone);

    TrobarPairing._handleRedeemResponse(400, null);
    // Cleared before invoking, so a second (cancelled-request) response
    // can't call the delegate's callback twice — which would walk the sync
    // chain a second time and notify completion twice over.
    Test.assert(TrobarPairing._pendingOnDone == null);
    return true;
}

(:test)
function testRedeemIfNeededShortCircuitsWhenPaired(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    Storage.setValue(TrobarStorageKeys.DEVICE_TOKEN, "already-paired");
    var recorder = new PairingRecorder();

    // Synchronous: no request is made, so the callback has already run by
    // the time redeemIfNeeded returns.
    TrobarPairing.redeemIfNeeded(recorder.method(:onDone));

    Test.assert(recorder.called);
    Test.assert(recorder.paired);
    Test.assert(recorder.reason == null);
    return true;
}

(:test)
function testRedeemIfNeededWithoutConfig(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    Properties.setValue("serverUrl", "");
    Properties.setValue("enrollCode", "");
    var recorder = new PairingRecorder();

    TrobarPairing.redeemIfNeeded(recorder.method(:onDone));

    Test.assert(recorder.called);
    Test.assert(!recorder.paired);
    Test.assertEqual(recorder.reason as Lang.Object, "not_configured");
    Test.assertEqual(
        Storage.getValue(TrobarStorageKeys.LAST_PAIRING_STATUS) as Lang.Object, "not_configured");
    return true;
}

(:test)
function testRedeemIfNeededWithAnUnusableUrl(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    Properties.setValue("serverUrl", "trobar.example.com");
    Properties.setValue("enrollCode", "ABC123");
    var recorder = new PairingRecorder();

    TrobarPairing.redeemIfNeeded(recorder.method(:onDone));

    // No request is made at all, and the reason names the actual problem:
    // before trobar-garmin#43 this reached makeWebRequest and came back as
    // "Network error", sending the user to check their wifi instead of the
    // four missing characters in their server URL.
    Test.assert(recorder.called);
    Test.assert(!recorder.paired);
    Test.assertEqual(recorder.reason as Lang.Object, "not_configured");
    Test.assertEqual(
        Storage.getValue(TrobarStorageKeys.LAST_PAIRING_STATUS) as Lang.Object, "not_configured");
    return true;
}

(:test)
function testForgetClearsEverything(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    Storage.setValue(TrobarStorageKeys.DEVICE_TOKEN, "tok");
    Storage.setValue(TrobarStorageKeys.DEVICE_ID, 7);
    Storage.setValue(TrobarStorageKeys.DEVICE_NAME, "Fenix");
    Storage.setValue(TrobarStorageKeys.LAST_PAIRING_STATUS, "network");

    TrobarPairing.forget();

    Test.assert(!TrobarPairing.isPaired());
    Test.assert(Storage.getValue(TrobarStorageKeys.DEVICE_ID) == null);
    Test.assert(Storage.getValue(TrobarStorageKeys.DEVICE_NAME) == null);
    Test.assert(Storage.getValue(TrobarStorageKeys.LAST_PAIRING_STATUS) == null);
    return true;
}
