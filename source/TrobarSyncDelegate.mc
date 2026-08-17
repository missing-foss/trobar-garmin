// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
using Toybox.Communications;
using Toybox.Application.Storage;
using Toybox.Application.Properties;
using Toybox.Media;
using Toybox.PersistedContent;
using Toybox.WatchUi;
using Toybox.Time;
using Toybox.Lang;

// A lexical-only interface (exists purely at compile time) purely so
// `has :getId` has genuine ambiguity to work with — see _idFromHandle.
typedef _ContentHandle as interface {
    function getId() as Lang.Object;
};

// The sync entry point for an Audio Content Provider app: whenever
// isSyncNeeded() returns true, the system activates the watch's own
// configured WiFi and calls onStartSync() — no phone needs to be present.
// This is also the one guaranteed moment WiFi is up, so pairing redemption
// (TrobarPairing.redeemIfNeeded) happens as the very first step here rather
// than anywhere else.
//
// Sequencing mirrors Garmin's own monkeymusic sample: single-threaded,
// callback-chained (Monkey C has no coroutines/threads) — deletes fully
// complete before downloads start, and downloads go one at a time via
// recursion through the *Acked callbacks below, not in parallel.
//
// Known, deliberate deprecation risk: what's marked
// "may be removed after System 9" is AppBase.getSyncDelegate() (the getter
// that registers this class), not this class or its methods. If that
// getter is ever removed, playback keeps working (getContentDelegate() is
// unmarked) — only new-content delivery would silently stop, which would
// look like a server problem rather than an app one. Not acted on now;
// tracked deliberately rather than missed.
//
// Known Connect IQ platform limitation (trobar-garmin#20) — confirmed on a
// real fenix5plus across three independent scenarios (nothing to sync, one
// track that never even started downloading, and a real fully-successful
// multi-track sync with live transcoding): the system's own sync-progress
// screen can stay stuck at 0% and never dismiss itself, even though a debug
// breadcrumb confirmed Communications.notifySyncComplete() was genuinely
// called every time, correctly, per Garmin's own documented contract. A
// 400ms Timer-based delay before that call was tried and made no
// difference — reverted rather than kept as dead complexity. This appears
// to be a firmware/platform bug outside this app's control, not something
// fixable in onStartSync()'s own sequencing. Don't re-attempt a delay-based
// fix without new evidence; if it recurs, the sync itself has almost
// certainly still completed (verify server-side) — cancelling the stuck
// screen is safe.
//
// QUALIFIED by trobar-garmin#44, found later: that crash
// threw inside _computePlayOrder() — called from _processNextDownload()
// immediately before notifySyncComplete() — so on any sync it reached, the
// completion notification never happened at all. "Downloads finish, screen
// never dismisses" is the same symptom from a cause that WAS in this app's
// control, which is what the paragraph above rules out. So treat "platform
// bug, nothing to do here" as unconfirmed rather than settled.
//
// It is not a straight replacement, and #56 exists to establish which:
// #44 only fired when the play-order remainder held 2+ entries (an
// insertion sort's inner loop never runs with fewer), so a multi-track
// sync of a single playlist — every entry claimed, remainder empty —
// reproduces #20's conditions without touching #44's. That may be how both
// were true at once. And the breadcrumb above did record
// notifySyncComplete() being called on a successful multi-track sync,
// which #44 firing would have prevented. Don't repeat "#44 explained #20"
// as though it were established.
//
// NB, reconciling this with the notifySyncProgress() comment below: that
// fix and this finding aren't in tension, even though read back-to-back
// they can sound like it. notifySyncProgress() is necessary — skipping it
// entirely was separately confirmed to hang every time — but not
// sufficient, per the testing above, to guarantee the screen dismisses.
// The calls stay because Garmin's contract requires them (and SubMusic,
// a real Store-published app, keeps the same calls) — not because they
// cure this bug. Don't read #18's original "fixes the stuck screen"
// framing as still accurate; that's what this comment corrects.
class TrobarSyncDelegate extends Communications.SyncDelegate {

    var _serverUrl as Lang.String or Null = null;
    var _token as Lang.String or Null = null;
    var _toDelete as Lang.Array or Null = null;
    var _toDownload as Lang.Array or Null = null;
    var _downloaded as Lang.Array or Null = null;
    var _playlists as Lang.Array or Null = null;
    var _deleteIndex as Lang.Number = 0;
    var _downloadIndex as Lang.Number = 0;
    // Per Garmin's own docs for onStartSync(): notifySyncProgress() "must"
    // be called intermittently, not just notifySyncComplete() at the end —
    // confirmed on a real fenix5plus that skipping it entirely (as this
    // class originally did) leaves the system's sync screen stuck
    // indefinitely even though notifySyncComplete() *is* still called.
    // Necessary, not sufficient, though — see the class-level comment
    // above on #20 for what calling it does *not* guarantee. The two
    // totals below drive this periodic call.
    var _totalItems as Lang.Number = 0;
    var _completedItems as Lang.Number = 0;
    // Holds a short internal reason code ("network" etc, see TrobarStatus)
    // — not a localized string — so it can double as what gets persisted
    // to LAST_SYNC_STATUS, localizing only at the point of use.
    var _firstError as Lang.String or Null = null;
    // onStopSync's cancelAllRequests() doesn't unwind the callback chain —
    // a cancelled request still invokes its callback (with a failure code),
    // which would otherwise walk the rest of the list and call
    // notifySyncComplete a second time. Checked at the top of both
    // "process next" drivers, which every callback funnels back into.
    var _cancelled as Lang.Boolean = false;

    function initialize() {
        SyncDelegate.initialize();
    }

    function isSyncNeeded() as Lang.Boolean {
        // Always true once paired: there's no cheap way to know "nothing
        // changed" without a network round trip, so this does wake WiFi on
        // every sync opportunity even when nothing on the server moved —
        // a deliberate, considered trade-off for v1, not an oversight.
        if (TrobarPairing.isPaired()) {
            return true;
        }
        // A URL the app can't use is the same as no URL at all here: waking
        // WiFi for it would spend battery on a request that cannot succeed.
        var serverUrl = TrobarApi.normalizeServerUrl(Properties.getValue("serverUrl"));
        var code = Properties.getValue("enrollCode");
        return serverUrl != null &&
            (code instanceof Lang.String) && !(code as Lang.String).equals("");
    }

    function onStartSync() as Void {
        _cancelled = false;
        _firstError = null;
        _deleteIndex = 0;
        _downloadIndex = 0;
        _totalItems = 0;
        _completedItems = 0;
        // Reported here, before anything can fail, so every exit path to
        // notifySyncComplete() — including an early bail-out on a pairing
        // failure, missing config, or a non-200 /changes response, all more
        // common in practice than a mid-download error — is preceded by at
        // least one notifySyncProgress() call. The call in
        // _onChangesResponse below is now redundant-but-harmless rather
        // than load-bearing.
        Communications.notifySyncProgress(0);
        TrobarPairing.redeemIfNeeded(method(:_onPairingDone));
    }

    function onStopSync() as Void {
        _cancelled = true;
        Communications.cancelAllRequests();
        Communications.notifySyncComplete(null);
    }

    function _onPairingDone(paired as Lang.Boolean, failureReason as Lang.String or Null) as Void {
        if (!paired) {
            var reason = failureReason != null ? failureReason : "network";
            // Recorded here for the same reason as every other exit path
            // (see _onChangesResponse): a sync that dies before it starts
            // must not leave LAST_SYNC_STATUS/LAST_SYNC_AT describing the
            // previous run. Invisible today — TrobarStatus stopped reading
            // LAST_SYNC_STATUS, and a pairing failure is separately
            // recorded under LAST_PAIRING_STATUS — but two sibling branches
            // disagreeing about whether to record is how that key comes
            // back wrong the day something reads it again.
            _recordSyncOutcome(reason);
            Communications.notifySyncComplete(TrobarStatus.reasonText(reason));
            return;
        }

        // Re-read and re-normalized rather than carried over from pairing:
        // the user can edit serverUrl in Garmin Connect Mobile at any time,
        // including after a successful pairing, so a watch that paired fine
        // can still hold an unusable URL by the time it syncs.
        var serverUrl = TrobarApi.normalizeServerUrl(Properties.getValue("serverUrl"));
        var rawToken = Storage.getValue(TrobarStorageKeys.DEVICE_TOKEN);

        if (serverUrl == null || !(rawToken instanceof Lang.String)) {
            _recordSyncOutcome("not_configured");
            Communications.notifySyncComplete(TrobarStatus.reasonText("not_configured"));
            return;
        }

        _serverUrl = serverUrl as Lang.String;
        _token = rawToken as Lang.String;
        TrobarApi.getChanges(_serverUrl as Lang.String, _token as Lang.String, method(:_onChangesResponse));
    }

    function _onChangesResponse(responseCode as Lang.Number, data as Lang.Dictionary or Null) as Void {
        if (responseCode != 200 || data == null) {
            // Without this, a sync that dies here leaves LAST_SYNC_STATUS/
            // LAST_SYNC_AT holding whatever the *previous* sync recorded —
            // the status screen would then read "Paired: name" as though
            // nothing happened, while a partial download failure further
            // down is reported faithfully.
            _recordSyncOutcome("network");
            Communications.notifySyncComplete(TrobarStatus.reasonText("network"));
            return;
        }

        var rawToDelete = data["to_delete"];
        var rawToDownload = data["to_download"];
        var rawDownloaded = data["downloaded"];
        var rawPlaylists = data["playlists"];
        _toDelete = rawToDelete instanceof Lang.Array ? rawToDelete as Lang.Array : [];
        _toDownload = rawToDownload instanceof Lang.Array ? rawToDownload as Lang.Array : [];
        _downloaded = rawDownloaded instanceof Lang.Array ? rawDownloaded as Lang.Array : [];
        _playlists = rawPlaylists instanceof Lang.Array ? rawPlaylists as Lang.Array : [];

        _totalItems = (_toDelete as Lang.Array).size() + (_toDownload as Lang.Array).size();
        _completedItems = 0;
        _reportProgress();

        _processNextDelete();
    }

    // See the comment on _totalItems above: without at least one call here,
    // a real device's own sync screen has been observed to never dismiss
    // itself even though notifySyncComplete() is called correctly.
    function _reportProgress() as Void {
        var pct = _totalItems > 0 ? (_completedItems * 100 / _totalItems) : 100;
        Communications.notifySyncProgress(pct as Lang.Number);
    }

    function _processNextDelete() as Void {
        if (_cancelled) {
            return;
        }
        var deletes = _toDelete as Lang.Array;
        if (_deleteIndex >= deletes.size()) {
            _downloadIndex = 0;
            _processNextDownload();
            return;
        }

        var entry = deletes[_deleteIndex] as Lang.Dictionary;
        var trackId = entry["track_id"] as Lang.Number;
        _removeFromContentMap(trackId);

        var serverUrl = _serverUrl;
        var token = _token;
        if (serverUrl == null || token == null) {
            _deleteIndex++;
            _completedItems++;
            _processNextDelete();
            return;
        }
        TrobarApi.ackTrack(serverUrl, token, trackId, "removed", method(:_onDeleteAcked));
    }

    // Response code intentionally ignored: on failure the server simply
    // keeps the track in status='removed' and re-sends it as a to_delete
    // entry next sync, so a dropped ack here just costs one extra round
    // trip later, not correctness.
    function _onDeleteAcked(responseCode as Lang.Number, data as Lang.Dictionary or Null) as Void {
        if (_cancelled) {
            return;
        }
        _deleteIndex++;
        _completedItems++;
        _reportProgress();
        _processNextDelete();
    }

    // Storage.setValue's ValueType requires an exactly-parameterized
    // Dictionary<KeyType,ValueType> — a plain Lang.Dictionary cast doesn't
    // structurally match it. Reading via `raw` (untouched, still typed as
    // whatever Storage.getValue() naturally returns) and passing that same
    // variable straight back — rather than the narrowed local used for
    // .remove()/indexing — sidesteps that mismatch instead of fighting it.
    //
    // If CONTENT_MAP had already lost this track's entry for some other
    // reason, the cached audio itself is orphaned here — nothing calls
    // deleteCachedItem for it, since there's no id left to reference. Not
    // expected in normal operation (CONTENT_MAP is the only place a
    // content id is ever recorded), but worth knowing as a failure mode.
    function _removeFromContentMap(trackId as Lang.Number) as Void {
        var raw = Storage.getValue(TrobarStorageKeys.CONTENT_MAP);
        var map = raw instanceof Lang.Dictionary ? raw as Lang.Dictionary : null;
        if (map == null) {
            return;
        }
        var key = trackId.toString();
        var contentId = map[key];
        if (contentId != null) {
            Media.deleteCachedItem(new Media.ContentRef(contentId as Lang.Object, Media.CONTENT_TYPE_AUDIO));
        }
        map.remove(key);
        Storage.setValue(TrobarStorageKeys.CONTENT_MAP, raw);
    }

    function _processNextDownload() as Void {
        if (_cancelled) {
            return;
        }
        var downloads = _toDownload as Lang.Array;
        if (_downloadIndex >= downloads.size()) {
            _computePlayOrder();
            _recordSyncOutcome(_firstError);
            Communications.notifySyncComplete(_firstError != null ? TrobarStatus.reasonText(_firstError) : null);
            return;
        }

        var entry = downloads[_downloadIndex] as Lang.Dictionary;
        var trackId = entry["track_id"] as Lang.Number;

        var serverUrl = _serverUrl;
        var token = _token;
        if (serverUrl == null || token == null) {
            _downloadIndex++;
            _completedItems++;
            _processNextDownload();
            return;
        }
        TrobarApi.downloadTrack(serverUrl, token, trackId, method(:_onTrackDownloaded));
    }

    function _onTrackDownloaded(
        responseCode as Lang.Number,
        data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null
    ) as Void {
        if (_cancelled) {
            return;
        }
        var downloads = _toDownload as Lang.Array;
        var entry = downloads[_downloadIndex] as Lang.Dictionary;
        var trackId = entry["track_id"] as Lang.Number;

        var contentId = _extractContentId(responseCode, data);
        if (contentId != null) {
            _addToContentMap(trackId, contentId as Lang.Object);
            var serverUrl = _serverUrl;
            var token = _token;
            if (serverUrl != null && token != null) {
                // bytes_on_device is deliberately omitted — the server
                // falls back to its own tracks.size() estimate for this
                // device's storage accounting, which is fine since the
                // audio responseType path never exposes a raw byte count
                // the way a manual file write would.
                TrobarApi.ackTrack(serverUrl, token, trackId, "downloaded", method(:_onDownloadAcked));
                return;
            }
        } else if (_firstError == null) {
            _firstError = "network";
        }

        _downloadIndex++;
        _completedItems++;
        _reportProgress();
        _processNextDownload();
    }

    // makeWebRequest's declared callback union for audio downloads
    // (Dictionary/String/PersistedContent.Iterator/Null — confirmed by the
    // real compiler, the same fixed shape for every use of makeWebRequest
    // regardless of :responseType) includes PersistedContent.Iterator,
    // which is a real hint an audio download may hand back an iterator
    // over cached content rather than an object directly exposing getId()
    // — handled explicitly below so a real-device test can tell "wrong
    // extraction" apart from "wrong everything" if downloads report
    // network errors. Neither Dictionary/String/Iterator nor plain Object
    // statically has :getId (confirmed by the real compiler across
    // iterations), which is why the duck-typed fallback path casts to the
    // lexical-only _ContentHandle interface instead — `has` only works
    // against a type the checker can't already prove membership on.
    function _extractContentId(
        responseCode as Lang.Number,
        data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null
    ) as Lang.Object or Null {
        if (responseCode != 200) {
            return null;
        }
        if (data == null) {
            return null;
        }
        if (data instanceof PersistedContent.Iterator) {
            var first = (data as PersistedContent.Iterator).next();
            if (first == null) {
                return null;
            }
            return _idFromHandle(first as Lang.Object);
        }
        return _idFromHandle(data as Lang.Object);
    }

    function _idFromHandle(obj as Lang.Object) as Lang.Object or Null {
        var handle = obj as _ContentHandle;
        if (!(handle has :getId)) {
            return null;
        }
        return handle.getId();
    }

    function _onDownloadAcked(responseCode as Lang.Number, data as Lang.Dictionary or Null) as Void {
        if (_cancelled) {
            return;
        }
        _downloadIndex++;
        _completedItems++;
        _reportProgress();
        _processNextDownload();
    }

    function _addToContentMap(trackId as Lang.Number, contentId as Lang.Object) as Void {
        var raw = Storage.getValue(TrobarStorageKeys.CONTENT_MAP);
        var existing = raw instanceof Lang.Dictionary ? raw as Lang.Dictionary : null;
        var map = existing != null ? existing : ({} as Lang.Dictionary);
        map[trackId.toString()] = contentId;
        Storage.setValue(TrobarStorageKeys.CONTENT_MAP, map as Storage.ValueType);
    }

    function _recordSyncOutcome(reason as Lang.String or Null) as Void {
        Storage.setValue(TrobarStorageKeys.LAST_SYNC_AT, Time.now().value());
        if (reason == null) {
            Storage.deleteValue(TrobarStorageKeys.LAST_SYNC_STATUS);
        } else {
            Storage.setValue(TrobarStorageKeys.LAST_SYNC_STATUS, reason);
        }
    }

    // Play order: every assigned playlist follows its own .m3u8 order (the
    // only place ordering is explicit — the flat to_download/downloaded
    // arrays carry none), processed in the order the server returned them;
    // anything left over (album/artist/track selections alongside, or
    // instead of, playlists) is appended sorted by relative_path
    // lexicographically, which already reproduces correct album order
    // because the server zero-pads track numbers and prefixes multi-disc
    // tracks as CDn-NN. Entries that failed to download (no CONTENT_MAP
    // entry) are filtered out first — a ContentIterator returning null
    // mid-list is how it signals end-of-content, so a failed track left
    // in PLAY_ORDER would stop playback early rather than being skipped.
    function _computePlayOrder() as Void {
        var entries = [] as Lang.Array;
        var downloads = _toDownload as Lang.Array;
        var downloaded = _downloaded as Lang.Array;
        for (var i = 0; i < downloads.size(); i++) {
            entries.add(downloads[i] as Lang.Object);
        }
        for (var i = 0; i < downloaded.size(); i++) {
            entries.add(downloaded[i] as Lang.Object);
        }
        entries = _filterToCachedContent(entries);

        var order = [] as Lang.Array;
        var used = {} as Lang.Dictionary;

        var playlists = _playlists as Lang.Array;
        for (var p = 0; p < playlists.size(); p++) {
            var playlist = playlists[p] as Lang.Dictionary;
            var content = playlist["content"] as Lang.String;
            var playlistOrder = _orderFromPlaylist(content, entries);
            for (var i = 0; i < playlistOrder.size(); i++) {
                var trackId = playlistOrder[i] as Lang.Number;
                // A track in two playlists would otherwise land in
                // PLAY_ORDER twice (one flat queue, not per-playlist) —
                // first playlist that claims it wins.
                if (used[trackId.toString()] != null) {
                    continue;
                }
                order.add(trackId as Lang.Object);
                used[trackId.toString()] = true;
            }
        }

        var remaining = [] as Lang.Array;
        for (var i = 0; i < entries.size(); i++) {
            var e = entries[i] as Lang.Dictionary;
            var trackId = e["track_id"] as Lang.Number;
            if (used[trackId.toString()] == null) {
                remaining.add(e as Lang.Object);
            }
        }
        _sortEntriesByRelativePath(remaining);
        for (var i = 0; i < remaining.size(); i++) {
            var e = remaining[i] as Lang.Dictionary;
            order.add(e["track_id"] as Lang.Object);
        }

        Storage.setValue(TrobarStorageKeys.PLAY_ORDER, order as Storage.ValueType);
    }

    function _filterToCachedContent(entries as Lang.Array) as Lang.Array {
        var raw = Storage.getValue(TrobarStorageKeys.CONTENT_MAP);
        var map = raw instanceof Lang.Dictionary ? raw as Lang.Dictionary : null;
        if (map == null) {
            return [];
        }
        var filtered = [] as Lang.Array;
        for (var i = 0; i < entries.size(); i++) {
            var e = entries[i] as Lang.Dictionary;
            var trackId = e["track_id"] as Lang.Number;
            if (map[trackId.toString()] != null) {
                filtered.add(e as Lang.Object);
            }
        }
        return filtered;
    }

    // Simple insertion sort — entries.size() is small (a single-selection
    // v1 MVP), so Array.sort()'s Comparator ceremony isn't worth it here.
    function _sortEntriesByRelativePath(entries as Lang.Array) as Void {
        for (var i = 1; i < entries.size(); i++) {
            var current = entries[i] as Lang.Dictionary;
            var currentPath = current["relative_path"] as Lang.String;
            var j = i - 1;
            while (j >= 0 && _comparePaths(
                    (entries[j] as Lang.Dictionary)["relative_path"] as Lang.String,
                    currentPath) > 0) {
                entries[j + 1] = entries[j];
                j--;
            }
            entries[j + 1] = current;
        }
    }

    // Lang.String has no compareTo() at runtime on this device, even though
    // the type checker accepts the call at -l 3 — it fails with "Could not
    // find symbol 'compareTo'" only once the line actually executes, which
    // takes a remainder of two or more entries (an insertion sort's inner
    // loop never runs with fewer). Ordering by code point matches what the
    // server's zero-padded, CDn-prefixed names are built for.
    function _comparePaths(a as Lang.String, b as Lang.String) as Lang.Number {
        var ac = a.toCharArray();
        var bc = b.toCharArray();
        var shortest = ac.size() < bc.size() ? ac.size() : bc.size();
        for (var i = 0; i < shortest; i++) {
            var av = (ac[i] as Lang.Char).toNumber();
            var bv = (bc[i] as Lang.Char).toNumber();
            if (av != bv) {
                return av - bv;
            }
        }
        return ac.size() - bc.size();
    }

    function _orderFromPlaylist(content as Lang.String, entries as Lang.Array) as Lang.Array {
        var pathToTrackId = {} as Lang.Dictionary;
        for (var i = 0; i < entries.size(); i++) {
            var e = entries[i] as Lang.Dictionary;
            pathToTrackId[e["relative_path"] as Lang.String] = e["track_id"];
        }

        var order = [] as Lang.Array;
        var lines = _splitLines(content);
        for (var i = 0; i < lines.size(); i++) {
            var line = _stripCR(lines[i] as Lang.String);
            if (line.length() == 0 || _startsWithHash(line)) {
                continue;
            }
            var trackId = pathToTrackId[line];
            if (trackId != null) {
                order.add(trackId as Lang.Object);
            }
        }
        return order;
    }

    function _startsWithHash(line as Lang.String) as Lang.Boolean {
        var first = line.substring(0, 1);
        return first != null && (first as Lang.String).equals("#");
    }

    // Lang.String has no split() — walk it manually via find()/substring().
    function _splitLines(content as Lang.String) as Lang.Array {
        var lines = [] as Lang.Array;
        var remaining = content;
        var idx = remaining.find("\n");
        while (idx != null) {
            lines.add(remaining.substring(0, idx) as Lang.String);
            remaining = remaining.substring((idx as Lang.Number) + 1, remaining.length()) as Lang.String;
            idx = remaining.find("\n");
        }
        if (remaining.length() > 0) {
            lines.add(remaining);
        }
        return lines;
    }

    function _stripCR(line as Lang.String) as Lang.String {
        var len = line.length();
        if (len > 0) {
            var last = line.substring(len - 1, len);
            if (last != null && (last as Lang.String).equals("\r")) {
                return line.substring(0, len - 1) as Lang.String;
            }
        }
        return line;
    }
}
