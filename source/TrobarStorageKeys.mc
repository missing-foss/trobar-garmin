// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later

// Centralizes Application.Storage key names so they're only ever spelled
// once. DEVICE_*/LAST_PAIRING_STATUS land with pairing;
// CONTENT_MAP/PLAY_ORDER/LAST_SYNC_* with the sync engine. Pairing and
// sync failures are deliberately kept on separate keys — TrobarStatus
// picks a different prefix for each, and conflating them once mislabeled
// a real sync failure as a pairing problem.
module TrobarStorageKeys {
    const DEVICE_TOKEN = "deviceToken";
    const DEVICE_ID = "deviceId";
    const DEVICE_NAME = "deviceName";
    const LAST_PAIRING_STATUS = "lastPairingStatus";
    const CONTENT_MAP = "contentMap";
    const PLAY_ORDER = "playOrder";
    const LAST_SYNC_STATUS = "lastSyncStatus";
    const LAST_SYNC_AT = "lastSyncAt";
}
