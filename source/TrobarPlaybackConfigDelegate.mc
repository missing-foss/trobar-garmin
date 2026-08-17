// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
using Toybox.WatchUi;
using Toybox.Media;

// Input delegate paired with TrobarPlaybackConfigView. Per Garmin's own
// "How do I create an Audio Content Provider?" guide: playback configuration
// is "the main view when launched by the media player" and "the app can
// choose to start playback from this flow using Media.startPlayback()" —
// confirmed on a real fenix5plus that tapping the Trobar source from the
// Music app's own source list lands here, not on
// TrobarSyncConfigView/getSyncConfigurationView(). (Review correction:
// getSyncConfigurationView() itself carries no deprecation marker — it's
// AppBase.getSyncDelegate(), the entry point the whole sync engine hangs
// off, that's marked "may be removed after System 9". Folding "Forget
// pairing" into both delegates is justified by the device evidence alone,
// not by a deprecated config-view API.)
// Without a delegate at all (the original state), Select did nothing —
// there was no way to actually start playback, only a static status
// screen with no path forward. v1 has a single flat play order (no
// playlist/track picker to build), so Select starts it directly rather
// than opening a chooser first.
class TrobarPlaybackConfigDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() {
        Media.startPlayback(null);
        return true;
    }

    // Also reachable from here, not just TrobarSyncConfigView — see the
    // comment on TrobarConfigMenu.open() for why both need it.
    function onMenu() {
        TrobarConfigMenu.open();
        return true;
    }
}
