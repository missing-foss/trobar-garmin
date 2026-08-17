// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
using Toybox.WatchUi;
using Toybox.Lang;

// Shared by every config delegate's onMenu() — real-device testing showed
// tapping the Trobar source from the Music app's own source list lands on
// getPlaybackConfigurationView() (TrobarPlaybackConfigDelegate), not
// getSyncConfigurationView() (TrobarSyncConfigDelegate) where this action
// originally lived only. Opening it from both means "Forget pairing" is
// reachable regardless of which one the system actually shows.
module TrobarConfigMenu {
    function open() as Void {
        var label = WatchUi.loadResource(Rez.Strings.menuForgetPairing) as Lang.String;
        var menu = new WatchUi.Menu2({ :title => label });
        menu.addItem(new WatchUi.MenuItem(label, null, :forgetPairing, {}));
        WatchUi.pushView(menu, new TrobarConfigMenuDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }
}
