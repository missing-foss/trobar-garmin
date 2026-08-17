// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
using Toybox.Communications;
using Toybox.Media;
using Toybox.PersistedContent;
using Toybox.Lang;

// Thin wrapper over Communications.makeWebRequest for every trobar-server
// endpoint this client talks to — owns URL-joining and Bearer-header
// injection so callers never touch makeWebRequest directly.
module TrobarApi {

    // serverUrl is free text the user typed into Garmin Connect Mobile, so
    // it arrives with whatever they pasted from a browser — most often a
    // trailing slash, sometimes surrounding whitespace. Concatenating that
    // raw produced "https://host//api/device/changes", which works only if
    // something upstream collapses duplicate slashes (nginx does by
    // default, Flask/Werkzeug on its own does not) — so the watch worked or
    // didn't depending on a property of someone else's deployment
    // (trobar-garmin#43).
    //
    // Every request goes through here rather than through the normalized
    // value alone, so a caller that hasn't normalized still can't build a
    // malformed URL. That makes the strip a no-op in the normal path, which
    // is the point: correctness here doesn't depend on remembering to
    // normalize somewhere else.
    function _join(serverUrl as Lang.String, path as Lang.String) as Lang.String {
        return _trimTrailingSlashes(_trim(serverUrl)) + path;
    }

    // Returns the cleaned-up URL, or null when it can't be used at all.
    // The scheme check exists so a missing "https://" is reported as a
    // configuration problem rather than as a network error: makeWebRequest
    // fails either way, but "Network error" sends the user to re-check
    // their wifi and their server, when the actual fix is four characters
    // in a settings field.
    function normalizeServerUrl(raw as Lang.Object or Null) as Lang.String or Null {
        if (!(raw instanceof Lang.String)) {
            return null;
        }
        var value = _trimTrailingSlashes(_trim(raw as Lang.String));
        // Scheme comparison is case-insensitive (RFC 3986 §3.1), and this
        // is not a theoretical case: a phone keyboard auto-capitalising the
        // first character of a text field is exactly how "Https://…"
        // arrives. The scheme is then re-emitted in lower case so what
        // reaches makeWebRequest is canonical regardless of what was typed;
        // everything after it is left exactly as the user wrote it, since
        // path case is significant even though host case isn't.
        //
        // The length tests reject a bare scheme with no host after it.
        if (_startsWithIgnoringCase(value, "https://") && value.length() > 8) {
            return "https://" + (value.substring(8, value.length()) as Lang.String);
        }
        if (_startsWithIgnoringCase(value, "http://") && value.length() > 7) {
            return "http://" + (value.substring(7, value.length()) as Lang.String);
        }
        return null;
    }

    // Lang.String has no trim(), startsWith() or endsWith() — walk the
    // characters. Comparing code points rather than one-character
    // substrings also sidesteps substring()'s null return at the edges.
    function _trim(value as Lang.String) as Lang.String {
        var chars = value.toCharArray();
        var start = 0;
        var end = chars.size();
        while (start < end && _isBlank(chars[start] as Lang.Char)) {
            start++;
        }
        while (end > start && _isBlank(chars[end - 1] as Lang.Char)) {
            end--;
        }
        if (start == 0 && end == chars.size()) {
            return value;
        }
        if (start == end) {
            return "";
        }
        return value.substring(start, end) as Lang.String;
    }

    function _isBlank(c as Lang.Char) as Lang.Boolean {
        var n = c.toNumber();
        return n == 32 || n == 9 || n == 10 || n == 13;
    }

    function _trimTrailingSlashes(value as Lang.String) as Lang.String {
        var chars = value.toCharArray();
        var end = chars.size();
        while (end > 0 && (chars[end - 1] as Lang.Char).toNumber() == 47) {
            end--;
        }
        if (end == chars.size()) {
            return value;
        }
        if (end == 0) {
            return "";
        }
        return value.substring(0, end) as Lang.String;
    }

    // `prefix` must be lower case. toLower() is safe on this app's 3.1.0
    // floor — checked against the SDK's API database rather than assumed,
    // since a method newer than minSdkVersion compiles clean and throws at
    // runtime (trobar-garmin#44); it has been there since 1.0.0. Only the
    // prefix is folded, never the whole value, because the path after the
    // scheme is case-sensitive.
    function _startsWithIgnoringCase(value as Lang.String, prefix as Lang.String) as Lang.Boolean {
        if (value.length() < prefix.length()) {
            return false;
        }
        var head = value.substring(0, prefix.length());
        if (head == null) {
            return false;
        }
        return (head as Lang.String).toLower().equals(prefix);
    }

    // POST /api/enrollment/redeem — session-less, exchanges a short-lived
    // enrollment code for {id, name, token}.
    function redeemEnrollment(
        serverUrl as Lang.String,
        code as Lang.String,
        deviceName as Lang.String,
        callback as Method(responseCode as Lang.Number, data as Lang.Dictionary or Null) as Void
    ) as Void {
        var params = {
            "code" => code,
            "name" => deviceName,
            "device_type" => "watch",
        };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
        };
        Communications.makeWebRequest(_join(serverUrl, "/api/enrollment/redeem"), params, options, callback);
    }

    // GET /api/device/changes — the full (unpaginated) to_download/
    // to_delete/downloaded/playlists/transcode_format working set.
    function getChanges(
        serverUrl as Lang.String,
        token as Lang.String,
        callback as Method(responseCode as Lang.Number, data as Lang.Dictionary or Null) as Void
    ) as Void {
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => { "Authorization" => "Bearer " + token },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
        };
        Communications.makeWebRequest(_join(serverUrl, "/api/device/changes"), null, options, callback);
    }

    // GET /api/device/file/<id> — audio responseType, routes the response
    // straight into the system's encrypted content cache. The watch's
    // transcode_format must be set to an mp3_* tier server-side (no FLAC
    // support in Media.ENCODING_*) — an operational setup step, not
    // something this client can enforce.
    //
    // The callback type below is Communications.makeWebRequest's own
    // declared shape (confirmed by the real compiler, not assumed) — it's
    // the same fixed union for every use of makeWebRequest regardless of
    // :responseType, so PersistedContent.Iterator here doesn't imply
    // anything about audio specifically. What the audio responseType
    // actually hands back isn't fully captured by this static type; the
    // `has :getId` duck-type check in TrobarSyncDelegate is the real
    // (runtime, not static) arbiter, and only a real-device test can
    // confirm it.
    function downloadTrack(
        serverUrl as Lang.String,
        token as Lang.String,
        trackId as Lang.Number,
        callback as Method(responseCode as Lang.Number, data as Lang.Dictionary or Lang.String or PersistedContent.Iterator or Null) as Void
    ) as Void {
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => { "Authorization" => "Bearer " + token },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_AUDIO,
            :mediaEncoding => Media.ENCODING_MP3,
        };
        Communications.makeWebRequest(_join(serverUrl, "/api/device/file/" + trackId), null, options, callback);
    }

    // POST /api/device/ack — {track_id, status, bytes_on_device?}.
    function ackTrack(
        serverUrl as Lang.String,
        token as Lang.String,
        trackId as Lang.Number,
        status as Lang.String,
        callback as Method(responseCode as Lang.Number, data as Lang.Dictionary or Null) as Void
    ) as Void {
        var params = {
            "track_id" => trackId,
            "status" => status,
        };
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {
                "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                "Authorization" => "Bearer " + token,
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
        };
        Communications.makeWebRequest(_join(serverUrl, "/api/device/ack"), params, options, callback);
    }
}
