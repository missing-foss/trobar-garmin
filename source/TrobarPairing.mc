// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
using Toybox.Application;
using Toybox.Application.Storage;
using Toybox.Application.Properties;
using Toybox.Lang;

// Pairing state lives on Application.Storage, never Application.Properties
// — Properties.setValue() is documented as unusable from a background
// process, which is exactly the context onStartSync() runs in
// (see TrobarSyncDelegate). Properties only ever hold what the user typed
// via Garmin Connect Mobile (serverUrl, enrollCode); Storage holds what
// pairing produced (the device id/name/token), plus the last pairing/sync
// failure reason (TrobarStorageKeys.LAST_PAIRING_STATUS) that the status
// views read.
module TrobarPairing {

    // Redemption is async (Communications.makeWebRequest), so the caller's
    // onDone can't just be passed straight through as the web-request
    // callback — it's stashed here until the response arrives.
    var _pendingOnDone as Method(paired as Lang.Boolean, failureReason as Lang.String or Null) as Void or Null = null;

    // obj.method(:name) requires an actual object instance to bind to —
    // a plain module has no `self` for the bare method(:name) shorthand,
    // and modules themselves don't expose a .method() accessor either.
    // This class exists purely to hold that binding for the
    // makeWebRequest callback below.
    class _Responder {
        function initialize() {
        }

        function onResponse(responseCode as Lang.Number, data as Lang.Dictionary or Null) as Void {
            TrobarPairing._handleRedeemResponse(responseCode, data);
        }
    }

    var _responder as _Responder = new _Responder();

    function isPaired() as Lang.Boolean {
        return Storage.getValue(TrobarStorageKeys.DEVICE_TOKEN) != null;
    }

    // Redeems the configured enrollment code if not already paired, then
    // calls onDone(paired, failureReason). failureReason is null on
    // success; one of "not_configured" / "invalid_code" / "network"
    // otherwise. Deliberately never invoked from onStartSync() in this PR
    // — that wiring lands with the sync engine, since onStartSync() is the
    // one guaranteed moment WiFi is up to actually exercise this.
    function redeemIfNeeded(
        onDone as Method(paired as Lang.Boolean, failureReason as Lang.String or Null) as Void
    ) as Void {
        if (isPaired()) {
            onDone.invoke(true, null);
            return;
        }

        // Normalized once, here, at the point the user's text becomes
        // something the app acts on — a URL with no scheme, or nothing but
        // a trailing slash, is a configuration problem and is reported as
        // one rather than being sent to makeWebRequest to come back as a
        // generic network error (trobar-garmin#43).
        var serverUrl = TrobarApi.normalizeServerUrl(Properties.getValue("serverUrl"));
        var rawCode = Properties.getValue("enrollCode");

        if (serverUrl == null || !(rawCode instanceof Lang.String)) {
            Storage.setValue(TrobarStorageKeys.LAST_PAIRING_STATUS, "not_configured");
            onDone.invoke(false, "not_configured");
            return;
        }

        var code = rawCode as Lang.String;

        if (code.equals("")) {
            Storage.setValue(TrobarStorageKeys.LAST_PAIRING_STATUS, "not_configured");
            onDone.invoke(false, "not_configured");
            return;
        }

        _pendingOnDone = onDone;
        TrobarApi.redeemEnrollment(serverUrl as Lang.String, code, "fenix5plus", _responder.method(:onResponse));
    }

    function _handleRedeemResponse(responseCode as Lang.Number, data as Lang.Dictionary or Null) as Void {
        var onDone = _pendingOnDone;
        _pendingOnDone = null;

        if (responseCode == 200 && data != null) {
            var token = data["token"] as Lang.String;
            var id = data["id"] as Lang.Number;
            var name = data["name"] as Lang.String;
            Storage.setValue(TrobarStorageKeys.DEVICE_TOKEN, token);
            Storage.setValue(TrobarStorageKeys.DEVICE_ID, id);
            Storage.setValue(TrobarStorageKeys.DEVICE_NAME, name);
            Storage.deleteValue(TrobarStorageKeys.LAST_PAIRING_STATUS);
            if (onDone != null) {
                onDone.invoke(true, null);
            }
            return;
        }

        var reason = responseCode == 400 ? "invalid_code" : "network";
        Storage.setValue(TrobarStorageKeys.LAST_PAIRING_STATUS, reason);
        if (onDone != null) {
            onDone.invoke(false, reason);
        }
    }

    function forget() as Void {
        Storage.deleteValue(TrobarStorageKeys.DEVICE_TOKEN);
        Storage.deleteValue(TrobarStorageKeys.DEVICE_ID);
        Storage.deleteValue(TrobarStorageKeys.DEVICE_NAME);
        Storage.deleteValue(TrobarStorageKeys.LAST_PAIRING_STATUS);
    }
}
