// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
using Toybox.WatchUi;

// Input delegate paired with TrobarSyncConfigView. Opens a one-item menu
// ("Forget pairing") via TrobarConfigMenuDelegate.
class TrobarSyncConfigDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onMenu() {
        TrobarConfigMenu.open();
        return true;
    }
}
