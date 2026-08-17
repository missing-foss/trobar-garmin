// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
using Toybox.Application;

// An Audio Content Provider app: the watch's native Music player owns
// playback UI (play/pause/skip, volume, headphones) — this app only ever
// supplies content (TrobarContentDelegate), a sync source
// (TrobarSyncDelegate), and the two config screens Connect IQ requires
// for this app type, repurposed as pairing/status screens.
class TrobarApp extends Application.AudioContentProviderApp {

    function initialize() {
        AudioContentProviderApp.initialize();
    }

    function getContentDelegate(args) {
        return new TrobarContentDelegate();
    }

    function getSyncDelegate() {
        return new TrobarSyncDelegate();
    }

    function getPlaybackConfigurationView() {
        return [new TrobarPlaybackConfigView(), new TrobarPlaybackConfigDelegate()];
    }

    function getSyncConfigurationView() {
        return [new TrobarSyncConfigView(), new TrobarSyncConfigDelegate()];
    }
}
