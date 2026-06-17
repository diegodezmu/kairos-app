autowatch = 1;
inlets = 4;
outlets = 2;

var sourceSlot = 1;
var sourceName = "Track";
var enabled = 1;
var senderId = "kairos-" + Math.floor(Math.random() * 1000000000).toString(16);
var packetCount = 0;

// --- Post-fader level via Live API -----------------------------------------
// `plugin~`/`peakamp~` only see the signal at the device's position in the
// chain, i.e. BEFORE the track mixer fader, so moving the track volume did not
// move the KAIROS meter. We therefore keep the patch's true audio analysis
// (RMS/peak), but align it to the track's post-fader state using Live's mixer
// gain plus the post-fader output meter. This keeps the KAIROS RMS reading tied
// to the same post-fader channel state as Ableton instead of substituting peak
// for RMS.
var trackApi = null;
var deviceApi = null;
var volumeApi = null;
var liveActive = false;
var meterPoller = null;
var latestPostFaderMeter = null;
var postMeterFreshnessMilliseconds = 125;
var rmsIntegrationWindowMilliseconds = 300;
var rmsHistory = [];
var warnedNonTerminalPlacement = false;

function loadbang() {
    initLiveMeter();
    outlet(1, "KAIROS Level sender loaded. Source " + sourceSlot + ", enabled " + enabled + ".");
}

function initLiveMeter() {
    try {
        meterPoller = new Task(pollMeter, this);
        meterPoller.interval = 33; // ~30 Hz, matches the visual meter cadence
        meterPoller.repeat();
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

function readMeter(property) {
    var raw = trackApi.get(property);
    if (raw === undefined || raw === null) {
        return null;
    }
    // LiveAPI.get may return a bare number or a single-element array.
    var value = (raw instanceof Array) ? raw[0] : raw;
    value = Number(value);
    return isNaN(value) ? null : value;
}

function pollMeter() {
    if (!enabled) {
        return;
    }

    if (trackApi === null || !trackApi.id || parseInt(trackApi.id, 10) === 0) {
        if (!resolveTrack()) {
            liveActive = false;
            return;
        }
    }

    var left = readMeter("output_meter_left");
    var right = readMeter("output_meter_right");

    if (left === null || right === null) {
        liveActive = false;
        latestPostFaderMeter = null;
        return;
    }

    liveActive = true;
    latestPostFaderMeter = {
        left: clamp(left),
        right: clamp(right),
        timestampMs: Date.now(),
        mixerGain: readCurrentMixerGain()
    };
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

function resolvePostFaderLevels(values) {
    if (values.length < 4) {
        return values;
    }

    var prefaderRMSLeft = clamp(values[0]);
    var prefaderRMSRight = clamp(values[1]);
    var prefaderPeakLeft = clamp(values[2]);
    var prefaderPeakRight = clamp(values[3]);

    var postRMSLeft = prefaderRMSLeft;
    var postRMSRight = prefaderRMSRight;
    var postPeakLeft = prefaderPeakLeft;
    var postPeakRight = prefaderPeakRight;

    if (hasFreshPostFaderMeter()) {
        var mixerGain = latestPostFaderMeter.mixerGain;
        postPeakLeft = latestPostFaderMeter.left;
        postPeakRight = latestPostFaderMeter.right;

        if (mixerGain !== null) {
            postRMSLeft = prefaderRMSLeft * mixerGain;
            postRMSRight = prefaderRMSRight * mixerGain;
        } else {
            postRMSLeft = scaledPostFaderRMS(prefaderRMSLeft, prefaderPeakLeft, postPeakLeft);
            postRMSRight = scaledPostFaderRMS(prefaderRMSRight, prefaderPeakRight, postPeakRight);
        }

        // The post-fader RMS cannot exceed the current post-fader peak shown by Live.
        postRMSLeft = Math.min(postRMSLeft, postPeakLeft);
        postRMSRight = Math.min(postRMSRight, postPeakRight);
    }

    var integrated = integrateRMS(postRMSLeft, postRMSRight, Date.now());
    return [
        clamp(integrated.left),
        clamp(integrated.right),
        clamp(postPeakLeft),
        clamp(postPeakRight)
    ];
}

function hasFreshPostFaderMeter() {
    return latestPostFaderMeter !== null &&
        (Date.now() - latestPostFaderMeter.timestampMs) <= postMeterFreshnessMilliseconds;
}

function scaledPostFaderRMS(prefaderRMS, prefaderPeak, postPeak) {
    var rms = clamp(prefaderRMS);
    var peak = clamp(prefaderPeak);
    var outputPeak = clamp(postPeak);

    if (rms <= 0 || peak <= 0 || outputPeak <= 0) {
        return 0;
    }

    return clamp(rms * (outputPeak / peak));
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
        .replace(/\u2212/g, "-")
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

    if (sourceSlot < 1) {
        outlet(1, "KAIROS Level source must be 1 or higher. Not sending.");
        return;
    }

    if (values.length < 4) {
        return;
    }

    var packet = {
        type: "kairos.level.v1",
        sourceSlot: sourceSlot,
        senderId: senderId,
        sourceName: sourceName,
        rmsL: clamp(values[0]),
        rmsR: clamp(values[1]),
        peakL: clamp(values[2]),
        peakR: clamp(values[3]),
        timestampMs: Date.now()
    };

    outlet(0, [
        "rms",
        packet.sourceSlot,
        packet.sourceName,
        packet.rmsL,
        packet.rmsR,
        packet.peakL,
        packet.peakR,
        packet.senderId,
        packet.timestampMs
    ]);
    packetCount += 1;

    if (packetCount === 1 || packetCount % 100 === 0) {
        outlet(1, "KAIROS Level sent " + packetCount + " packets on source " + sourceSlot + ".");
    }
}

function clamp(value) {
    value = Number(value);
    if (isNaN(value)) {
        return 0;
    }

    return Math.max(0, Math.min(1, value));
}
