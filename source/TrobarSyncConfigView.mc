// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Application;
using Toybox.Lang;

// The mandatory sync-configuration screen for an AudioContentProviderApp —
// repurposed as the pairing/last-sync status screen, since this app has no
// traditional now-playing screen to surface status/errors in otherwise.
class TrobarSyncConfigView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        // trobar-garmin#26: see TrobarPlaybackConfigView for why — same
        // h/2 +/- 20px rule of thumb applies here.
        dc.drawText(
            w / 2,
            h / 2 - 20,
            Graphics.FONT_SMALL,
            WatchUi.loadResource(Rez.Strings.AppName),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
        dc.drawText(
            w / 2,
            h / 2,
            Graphics.FONT_XTINY,
            TrobarStatus.text(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
        );
        // Permanent web-UI pointer (trobar-garmin#25) instead of asserting
        // sync outcome — empty until paired, so skip the draw call.
        var pointer = TrobarStatus.syncPointerText();
        if (!pointer.equals("")) {
            dc.drawText(
                w / 2,
                h / 2 + 20,
                Graphics.FONT_XTINY,
                pointer,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }
    }
}
