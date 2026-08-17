// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
using Toybox.Application.Storage;
using Toybox.WatchUi;
using Toybox.Lang;

// Shared status text for the two mandatory AudioContentProviderApp config
// screens (TrobarSyncConfigView, TrobarPlaybackConfigView) — nothing
// per-track to configure in v1, so both show the same pairing/last-sync
// status rather than inventing a second thing to maintain.
//
// Pairing failures (LAST_PAIRING_STATUS) and sync failures (LAST_SYNC_STATUS)
// are kept on separate keys and given separate prefixes — conflating them
// once meant a real sync failure ("Network error" mid-sync) would render
// as "Pairing failed: Network error", sending the user to needlessly
// re-check a perfectly valid enrollment code (trobar-garmin#12). A pairing
// failure is checked first since it's the more actionable of the two —
// nothing can sync until it's resolved.
module TrobarStatus {

    function text() as Lang.String {
        var pairingReason = Storage.getValue(TrobarStorageKeys.LAST_PAIRING_STATUS) as Lang.String or Null;
        if (pairingReason != null) {
            var prefix = WatchUi.loadResource(Rez.Strings.statusPairingFailedFmt) as Lang.String;
            return prefix + " " + reasonText(pairingReason);
        }

        if (!TrobarPairing.isPaired()) {
            return WatchUi.loadResource(Rez.Strings.statusNotConfigured) as Lang.String;
        }

        var name = Storage.getValue(TrobarStorageKeys.DEVICE_NAME) as Lang.String;
        var prefix = WatchUi.loadResource(Rez.Strings.statusPairedFmt) as Lang.String;
        return prefix + " " + name;
    }

    // trobar-garmin#25: the watch's own native sync-progress screen is a
    // confirmed liar (trobar-garmin#20 — can stay stuck at 0% even after a
    // genuinely successful sync), so LAST_SYNC_STATUS is no longer surfaced
    // here as something the watch asserts confidently, even though our own
    // recording of it (TrobarSyncDelegate) is accurate. It's still written
    // to Storage for possible future debug use — just not read here.
    // Returns "" (not paired yet, nothing sync-related to say) so callers
    // can skip drawing this line entirely rather than show it empty.
    function syncPointerText() as Lang.String {
        if (!TrobarPairing.isPaired()) {
            return "";
        }
        return WatchUi.loadResource(Rez.Strings.hintCheckWebUi) as Lang.String;
    }

    // Review feedback (trobar-garmin#21): this asks "is there anything to
    // play", not "did everything go well" — onSelect() calls
    // Media.startPlayback() unconditionally regardless of pairing/sync
    // status, so a status-based predicate could disagree with it both
    // ways. A sync failure with content already cached (the offline case
    // this app exists for) would hide the hint even though Select still
    // works; conversely, paired + synced + nothing assigned would show it
    // even though PLAY_ORDER is empty and playback has nothing to do.
    // PLAY_ORDER non-empty is the actual, honest condition.
    function canPlay() as Lang.Boolean {
        var order = Storage.getValue(TrobarStorageKeys.PLAY_ORDER);
        return order instanceof Lang.Array && (order as Lang.Array).size() > 0;
    }

    // Public so TrobarSyncDelegate can reuse the same localized mapping for
    // notifySyncComplete()'s error message.
    function reasonText(reason as Lang.String) as Lang.String {
        if (reason.equals("invalid_code")) {
            return WatchUi.loadResource(Rez.Strings.errInvalidCode) as Lang.String;
        }
        if (reason.equals("network")) {
            return WatchUi.loadResource(Rez.Strings.errNetwork) as Lang.String;
        }
        return WatchUi.loadResource(Rez.Strings.errNotConfigured) as Lang.String;
    }
}
