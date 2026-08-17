// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
using Toybox.Media;
using Toybox.Application.Storage;
using Toybox.Lang;

// Walks the play-order/content-id map that TrobarSyncDelegate computes into
// Application.Storage during sync (TrobarStorageKeys.PLAY_ORDER/CONTENT_MAP).
class TrobarContentIterator extends Media.ContentIterator {

    var _order as Lang.Array;
    var _contentMap as Lang.Dictionary;
    var _index as Lang.Number;

    function initialize() {
        ContentIterator.initialize();
        var rawOrder = Storage.getValue(TrobarStorageKeys.PLAY_ORDER);
        _order = rawOrder instanceof Lang.Array ? rawOrder as Lang.Array : [];
        var rawMap = Storage.getValue(TrobarStorageKeys.CONTENT_MAP);
        _contentMap = rawMap instanceof Lang.Dictionary ? rawMap as Lang.Dictionary : {};
        _index = _order.size() > 0 ? 0 : -1;
    }

    function get() {
        return _contentAt(_index);
    }

    function next() {
        if (_index < 0 || _index + 1 >= _order.size()) {
            return null;
        }
        _index++;
        return _contentAt(_index);
    }

    function previous() {
        if (_index <= 0) {
            return null;
        }
        _index--;
        return _contentAt(_index);
    }

    function peekNext() {
        if (_index < 0 || _index + 1 >= _order.size()) {
            return null;
        }
        return _contentAt(_index + 1);
    }

    function peekPrevious() {
        if (_index <= 0) {
            return null;
        }
        return _contentAt(_index - 1);
    }

    function getPlaybackProfile() {
        var profile = new Media.PlaybackProfile();
        profile.playbackControls = [
            Media.PLAYBACK_CONTROL_PLAYBACK,
            Media.PLAYBACK_CONTROL_NEXT,
            Media.PLAYBACK_CONTROL_PREVIOUS,
        ];
        return profile;
    }

    function _contentAt(index as Lang.Number) as Media.Content or Null {
        if (index < 0 || index >= _order.size()) {
            return null;
        }
        var trackId = _order[index] as Lang.Number;
        var contentId = _contentMap[trackId.toString()];
        if (contentId == null) {
            return null;
        }
        return Media.getCachedContentObj(new Media.ContentRef(contentId as Lang.Object, Media.CONTENT_TYPE_AUDIO));
    }
}
