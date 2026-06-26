autowatch = 1;
inlets = 4;
outlets = 2;

// Manual fallbacks (legacy). Identity is now auto-derived from the Live track
// whenever the Live API is reachable; these only apply if the track cannot be
// resolved (e.g. the device is loaded outside a Live track context).
var sourceSlot = 1;
var sourceName = "Track";
var enabled = 1;
var senderId = "kairos-" + Math.floor(Math.random() * 1000000000).toString(16);
var packetCount = 0;

// --- Identity + post-fader level via Live API ------------------------------
// `plugin~`/`peakamp~`/`average~` see the signal at the device's position in the
// chain, i.e. BEFORE the track mixer fader. We therefore measure true linear
// RMS/peak amplitude in the patch and scale it to post-fader by Live's mixer
// gain, so EVERYTHING we send stays in a single, consistent unit system: linear
// amplitude 0..1, which KAIROS converts to dBFS with 20*log10. We intentionally
// no longer substitute Live's `output_meter_*` for the peak: that value is a
// warped GUI-meter reading (not linear amplitude), so converting it with
// 20*log10 produced systematic dB error and mixed units with the RMS path.
//
// Identity (sourceSlot + sourceName) is derived from the track itself so the
// "source channel" shown in KAIROS always matches the real Ableton channel,
// instead of relying on a number/name the user must type by hand on each device.
var trackApi = null;
var deviceApi = null;
var volumeApi = null;
var liveActive = false;
var statePoller = null;
var latestTrackState = null; // { gain, name, slot, timestampMs }
// Mixer gain / name / slot are cheap Live API gets (no GUI-expensive meters),
// so we can refresh them at a comfortable rate and keep them fresh between the
// audio-driven level packets.
var trackStateFreshnessMilliseconds = 500;
var rmsIntegrationWindowMilliseconds = 300;
var rmsHistory = [];
var warnedNonTerminalPlacement = false;

function loadbang() {
    initLivePoll();
    outlet(1, "KAIROS Level sender loaded.");
}

function initLivePoll() {
    try {
        statePoller = new Task(refreshTrackState, this);
        statePoller.interval = 100; // cheap gets only; no output_meter polling
        statePoller.repeat();
    } catch (e) {
        liveActive = false;
    }
}

function resolveTrack() {
    try {
        // canonical_parent of the device is the track / return / group it sits on.
        var api = new LiveAPI(null, "this_device canonical_parent");
        if (api && api.id && parseInt(api.id, 10) !== 0) {
            trackApi = api;
            deviceApi = makeLiveApi("this_device");
            volumeApi = makeLiveApi("this_device canonical_parent mixer_device volume");
            warnIfDeviceIsNotLastInChain();
            return true;
        }
    } catch (e) {}
    trackApi = null;
    deviceApi = null;
    volumeApi = null;
    return false;
}

function makeLiveApi(path) {
    try {
        var api = new LiveAPI(null, path);
        if (api && api.id && parseInt(api.id, 10) !== 0) {
            return api;
        }
    } catch (e) {}

    return null;
}

function warnIfDeviceIsNotLastInChain() {
    if (warnedNonTerminalPlacement || trackApi === null || deviceApi === null) {
        return;
    }

    var path = String(deviceApi.unquotedpath || deviceApi.path || "");
    var match = path.match(/devices\s+(\d+)\s*$/);
    if (match === null) {
        return;
    }

    var deviceIndex = parseInt(match[1], 10);
    var deviceCount = readLiveApiCount(trackApi, "devices");
    if (isNaN(deviceIndex) || deviceCount === null || deviceCount <= 0) {
        return;
    }

    if (deviceIndex < (deviceCount - 1)) {
        warnedNonTerminalPlacement = true;
        outlet(
            1,
            "KAIROS Level sender should be the last device in the chain for exact post-fader RMS."
        );
    }
}

// Poll cheap track state: mixer gain (for post-fader scaling) plus the real
// track name and a stable slot derived from the channel's position. No
// GUI-expensive output meters are read here.
function refreshTrackState() {
    if (!enabled) {
        return;
    }

    if (trackApi === null || !trackApi.id || parseInt(trackApi.id, 10) === 0) {
        if (!resolveTrack()) {
            liveActive = false;
            latestTrackState = null;
            return;
        }
    }

    var gain = readCurrentMixerGain();
    var name = readTrackName();
    var slot = computeAutoSlot();

    if (gain === null && name === null && slot === null) {
        liveActive = false;
        latestTrackState = null;
        return;
    }

    liveActive = true;
    latestTrackState = {
        gain: gain,
        name: name,
        slot: slot,
        timestampMs: Date.now()
    };
}

function readTrackName() {
    if (trackApi === null) {
        return null;
    }

    var raw = null;
    try {
        raw = trackApi.get("name");
    } catch (e) {
        return null;
    }

    var text = liveApiText(raw);
    if (text === null) {
        return null;
    }

    text = text.trim();
    return text.length ? text : null;
}

// Derive a stable, collision-free numeric slot from the channel's real position
// so the "source channel" in KAIROS maps 1:1 to the Ableton channel without the
// user numbering devices by hand:
//   audio/group tracks -> 1-based index            (tracks 0 -> 1, tracks 1 -> 2, ...)
//   return tracks      -> 1001-based index
//   master track       -> 2001
function computeAutoSlot() {
    if (trackApi === null) {
        return null;
    }

    var path = String(trackApi.unquotedpath || trackApi.path || "");
    var match;

    if ((match = path.match(/return_tracks\s+(\d+)/)) !== null) {
        return 1001 + parseInt(match[1], 10);
    }

    if (path.indexOf("master_track") !== -1) {
        return 2001;
    }

    if ((match = path.match(/tracks\s+(\d+)/)) !== null) {
        return parseInt(match[1], 10) + 1;
    }

    return null;
}

function freshTrackState() {
    if (latestTrackState === null) {
        return null;
    }

    return (Date.now() - latestTrackState.timestampMs) <= trackStateFreshnessMilliseconds
        ? latestTrackState
        : null;
}

function currentGain() {
    var state = freshTrackState();
    return state ? state.gain : null;
}

function effectiveSlot() {
    var state = freshTrackState();
    if (state !== null && state.slot !== null && state.slot >= 1) {
        return state.slot;
    }

    return sourceSlot;
}

function effectiveName() {
    var state = freshTrackState();
    if (state !== null && state.name) {
        return state.name;
    }

    return sourceName;
}

function msg_int(value) {
    if (inlet === 1) {
        sourceSlot = Math.max(1, Math.round(value));
    } else if (inlet === 3) {
        enabled = value ? 1 : 0;
    }
}

function msg_float(value) {
    msg_int(Math.round(value));
}

function list() {
    var values = arrayfromargs(arguments);

    if (inlet === 0) {
        sendLevels(resolvePostFaderLevels(values));
    } else if (inlet === 2) {
        sourceName = values.join(" ");
    }
}

function anything() {
    var values = arrayfromargs(messagename, arguments);

    if (inlet === 2) {
        sourceName = values.join(" ");
    }
}

function source() {
    sourceName = arrayfromargs(arguments).join(" ");
}

function id(value) {
    senderId = String(value);
}

// Convert the patch's pre-fader linear RMS/peak to post-fader linear amplitude
// by applying the current mixer gain, then integrate the RMS over ~300 ms.
// Everything stays in linear amplitude 0..1 so KAIROS's 20*log10 is exact and
// rms/peak share the same unit system.
function resolvePostFaderLevels(values) {
    if (values.length < 4) {
        return values;
    }

    var rmsLeft = clamp(values[0]);
    var rmsRight = clamp(values[1]);
    var peakLeft = clamp(values[2]);
    var peakRight = clamp(values[3]);

    var gain = currentGain();
    if (gain !== null) {
        rmsLeft = clamp(rmsLeft * gain);
        rmsRight = clamp(rmsRight * gain);
        peakLeft = clamp(peakLeft * gain);
        peakRight = clamp(peakRight * gain);
    }

    var integrated = integrateRMS(rmsLeft, rmsRight, Date.now());
    return [
        clamp(integrated.left),
        clamp(integrated.right),
        clamp(peakLeft),
        clamp(peakRight)
    ];
}

function integrateRMS(rmsLeft, rmsRight, timestampMs) {
    rmsHistory.push({
        left: clamp(rmsLeft),
        right: clamp(rmsRight),
        timestampMs: timestampMs
    });

    var minimumTimestamp = timestampMs - rmsIntegrationWindowMilliseconds;
    while (rmsHistory.length > 0 && rmsHistory[0].timestampMs < minimumTimestamp) {
        rmsHistory.shift();
    }

    var leftSquares = 0;
    var rightSquares = 0;
    var count = rmsHistory.length;

    if (count === 0) {
        return { left: 0, right: 0 };
    }

    for (var index = 0; index < count; index++) {
        leftSquares += rmsHistory[index].left * rmsHistory[index].left;
        rightSquares += rmsHistory[index].right * rmsHistory[index].right;
    }

    return {
        left: Math.sqrt(leftSquares / count),
        right: Math.sqrt(rightSquares / count)
    };
}

function readCurrentMixerGain() {
    if (volumeApi === null || !volumeApi.id || parseInt(volumeApi.id, 10) === 0) {
        return null;
    }

    // Prefer the GUI-facing numeric dB value when Live exposes it. This avoids
    // locale/string parsing edge cases and keeps the post-fader correction
    // stable across Live language/settings changes.
    var displayValue = readLiveApiNumber(volumeApi, "display_value");
    if (displayValue !== null) {
        if (!isFinite(displayValue)) {
            return displayValue < 0 ? 0 : null;
        }

        return Math.pow(10, displayValue / 20);
    }

    var currentValue = readLiveApiNumber(volumeApi, "value");
    if (currentValue === null) {
        return null;
    }

    var display = null;
    try {
        display = volumeApi.call("str_for_value", currentValue);
    } catch (e) {}

    if (display === null || display === undefined) {
        try {
            display = volumeApi.call("__str__");
        } catch (e) {}
    }

    var displayText = liveApiText(display);
    var db = parseDecibels(displayText);
    if (db === null) {
        return null;
    }

    if (db === -Infinity) {
        return 0;
    }

    return Math.pow(10, db / 20);
}

function readLiveApiNumber(api, property) {
    if (api === null) {
        return null;
    }

    var raw = null;
    try {
        raw = api.get(property);
    } catch (e) {
        return null;
    }

    if (raw === undefined || raw === null) {
        return null;
    }

    var value = (raw instanceof Array) ? raw[0] : raw;
    value = Number(value);
    return isNaN(value) ? null : value;
}

function readLiveApiCount(api, childName) {
    if (api === null || typeof api.getcount !== "function") {
        return null;
    }

    var count = null;
    try {
        count = api.getcount(childName);
    } catch (e) {
        return null;
    }

    count = Number(count);
    return isNaN(count) ? null : count;
}

function liveApiText(raw) {
    if (raw === undefined || raw === null) {
        return null;
    }

    if (raw instanceof Array) {
        if (raw.length === 0) {
            return null;
        }

        return raw.join(" ");
    }

    return String(raw);
}

function parseDecibels(text) {
    if (text === null) {
        return null;
    }

    var normalized = String(text)
        .replace(/−/g, "-")
        .replace(/,/g, ".")
        .trim()
        .toLowerCase();

    if (normalized.indexOf("-inf") !== -1 || normalized.indexOf("-∞") !== -1) {
        return -Infinity;
    }

    var match = normalized.match(/-?\d+(?:\.\d+)?/);
    return match ? Number(match[0]) : null;
}

function sendLevels(values) {
    if (!enabled) {
        return;
    }

    if (values.length < 4) {
        return;
    }

    var slot = effectiveSlot();
    if (slot < 1) {
        outlet(1, "KAIROS Level source must be 1 or higher. Not sending.");
        return;
    }

    var packet = {
        type: "kairos.level.v1",
        sourceSlot: slot,
        senderId: senderId,
        sourceName: effectiveName(),
        rmsL: clamp(values[0]),
        rmsR: clamp(values[1]),
        peakL: clamp(values[2]),
        peakR: clamp(values[3]),
        timestampMs: Date.now()
    };

    // The name travels to node.script as a positional atom, so encode it to a
    // single space/comma-free token. node.script decodes it back before sending.
    outlet(0, [
        "rms",
        packet.sourceSlot,
        encodeURIComponent(packet.sourceName),
        packet.rmsL,
        packet.rmsR,
        packet.peakL,
        packet.peakR,
        packet.senderId,
        packet.timestampMs
    ]);
    packetCount += 1;

    if (packetCount === 1 || packetCount % 100 === 0) {
        outlet(1, "KAIROS Level sent " + packetCount + " packets on source " + packet.sourceSlot + " (" + packet.sourceName + ").");
    }
}

function clamp(value) {
    value = Number(value);
    if (isNaN(value)) {
        return 0;
    }

    return Math.max(0, Math.min(1, value));
}
