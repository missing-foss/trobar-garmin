// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
using Toybox.Media;
using Toybox.System;

// Handles playback events from the native Music player. v1 is log-only —
// there's no server-side scrobble/play-count endpoint to report to yet.
class TrobarContentDelegate extends Media.ContentDelegate {

    function initialize() {
        ContentDelegate.initialize();
    }

    function getContentIterator() {
        return new TrobarContentIterator();
    }

    function resetContentIterator() {
        return new TrobarContentIterator();
    }

    function onSong(contentRefId, songEvent, playbackPosition) {
        System.println("TrobarContentDelegate.onSong " + contentRefId + " " + songEvent);
    }
}
