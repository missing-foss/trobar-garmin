// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Application;
using Toybox.Lang;

// The mandatory playback-configuration screen for an AudioContentProviderApp
// — per Garmin's own guide, "the main view when launched by the media
// player" (confirmed on a real fenix5plus: tapping the Trobar source from
// the Music app's source list lands here). Nothing per-track to configure
// in v1 (a single flat play order, no playlist/track picker to build), so
// Select just starts playback directly — see TrobarPlaybackConfigDelegate.
class TrobarPlaybackConfigView extends WatchUi.View {

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        var w = dc.getWidth();
        var h = dc.getHeight();
        // trobar-garmin#26: on this round display, dc.getWidth()/getHeight()
        // describe the encompassing rectangle, not the visible circular
        // area — a line placed too far from vertical center gets clipped
        // regardless of horizontal centering. Confirmed on real hardware.
        // Rule of thumb for this file: keep every line within h/2 +/- 20px,
        // and re-confirm on device before going further out than that.
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
        // Third line is one or the other, never both: "Press Select to
        // play" is more actionable once there's actually something to
        // play, otherwise fall back to the permanent web-UI pointer
        // (trobar-garmin#25) — either way, exactly one short line here.
        var thirdLine = TrobarStatus.canPlay()
            ? WatchUi.loadResource(Rez.Strings.hintPressSelectToPlay) as Lang.String
            : TrobarStatus.syncPointerText();
        if (!thirdLine.equals("")) {
            dc.drawText(
                w / 2,
                h / 2 + 20,
                Graphics.FONT_XTINY,
                thirdLine,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }
    }
}
