// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
using Toybox.WatchUi;

// Handles the single "Forget pairing" menu action reachable from
// TrobarSyncConfigView and TrobarPlaybackConfigView.
class TrobarConfigMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        if (item.getId() == :forgetPairing) {
            TrobarPairing.forget();
            WatchUi.requestUpdate();
        }
    }
}
