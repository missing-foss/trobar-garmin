// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
using Toybox.Test;
using Toybox.Lang;
using Toybox.Media;
using Toybox.Application.Storage;

// Playback navigation over PLAY_ORDER/CONTENT_MAP.
//
// These tests deliberately never seed a CONTENT_MAP entry for a track they
// then navigate onto, so _contentAt always returns before reaching
// Media.getCachedContentObj — the cache holds nothing in a unit-test run,
// and asking it for a made-up id is not a thing this suite should depend
// on. What's under test is the index arithmetic, which is where the
// off-by-one lives; _index is asserted directly for that reason.

(:test)
function testIteratorWithNoPlayOrder(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    var it = new TrobarContentIterator();

    // -1 is the "nothing to play" sentinel: get() must not report track 0
    // of an empty list.
    Test.assertEqual(it._index as Lang.Object, -1);
    Test.assert(it.get() == null);
    Test.assert(it.next() == null);
    Test.assert(it.previous() == null);
    Test.assert(it.peekNext() == null);
    Test.assert(it.peekPrevious() == null);
    return true;
}

(:test)
function testIteratorStartsAtFirstTrack(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    TestSupport.seedPlayOrder([11, 22, 33] as Lang.Array);
    var it = new TrobarContentIterator();

    Test.assertEqual(it._index as Lang.Object, 0);
    Test.assert(it.peekPrevious() == null);
    return true;
}

(:test)
function testIteratorNextStopsAtTheEnd(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    TestSupport.seedPlayOrder([11, 22] as Lang.Array);
    var it = new TrobarContentIterator();

    it.next();
    Test.assertEqual(it._index as Lang.Object, 1);

    // Past the end returns null AND leaves the index alone — an index that
    // walked off the end would make previous() return the wrong track.
    Test.assert(it.next() == null);
    Test.assertEqual(it._index as Lang.Object, 1);
    Test.assert(it.peekNext() == null);
    return true;
}

(:test)
function testIteratorPreviousStopsAtTheStart(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    TestSupport.seedPlayOrder([11, 22] as Lang.Array);
    var it = new TrobarContentIterator();

    Test.assert(it.previous() == null);
    Test.assertEqual(it._index as Lang.Object, 0);

    it.next();
    it.previous();
    Test.assertEqual(it._index as Lang.Object, 0);
    return true;
}

(:test)
function testIteratorPeekDoesNotMove(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    TestSupport.seedPlayOrder([11, 22, 33] as Lang.Array);
    var it = new TrobarContentIterator();

    it.next();
    it.peekNext();
    it.peekPrevious();
    Test.assertEqual(it._index as Lang.Object, 1);
    return true;
}

(:test)
function testContentAtOutOfRangeIsNull(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    TestSupport.seedPlayOrder([11] as Lang.Array);
    var it = new TrobarContentIterator();

    Test.assert(it._contentAt(-1) == null);
    Test.assert(it._contentAt(1) == null);
    // In range, but the track has no cached content — the case
    // _computePlayOrder's filtering exists to prevent, handled here as
    // null rather than a crash.
    Test.assert(it._contentAt(0) == null);
    return true;
}

(:test)
function testIteratorIgnoresGarbageStorage(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    // Neither key holds the type the iterator expects. Storage is app-owned
    // and survives upgrades, so a shape change must degrade to "nothing to
    // play" rather than throwing on every playback attempt.
    Storage.setValue(TrobarStorageKeys.PLAY_ORDER, "not an array");
    Storage.setValue(TrobarStorageKeys.CONTENT_MAP, 42);

    var it = new TrobarContentIterator();
    Test.assertEqual(it._index as Lang.Object, -1);
    Test.assert(it.get() == null);
    return true;
}

(:test)
function testPlaybackProfileOffersNextAndPrevious(logger as Test.Logger) as Lang.Boolean {
    TestSupport.resetStorage();
    var it = new TrobarContentIterator();

    var profile = it.getPlaybackProfile();
    // The watch draws its transport controls from this list, so assert the
    // controls themselves: a size check alone stays green if NEXT is
    // swapped for something else and the user quietly loses the ability to
    // move through the queue.
    var controls = profile.playbackControls as Lang.Array;
    Test.assertEqual(controls.size() as Lang.Object, 3);
    Test.assertEqual(controls[0] as Lang.Object, Media.PLAYBACK_CONTROL_PLAYBACK);
    Test.assertEqual(controls[1] as Lang.Object, Media.PLAYBACK_CONTROL_NEXT);
    Test.assertEqual(controls[2] as Lang.Object, Media.PLAYBACK_CONTROL_PREVIOUS);
    return true;
}
