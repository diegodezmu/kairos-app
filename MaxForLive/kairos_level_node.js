const dgram = require("dgram");
const maxApi = require("max-api");

let host = "127.0.0.1";
let port = 51515;
let sentCount = 0;
let errorCount = 0;

const socket = dgram.createSocket("udp4");
socket.bind(() => {
  socket.setBroadcast(true);
});

function clamp01(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return 0;
  }

  return Math.max(0, Math.min(1, number));
}

function sendPacket(packet) {
  const payload = Buffer.from(JSON.stringify(packet), "utf8");
  socket.send(payload, port, host, (error) => {
    if (error) {
      reportSendError(error);
      return;
    }

    sentCount += 1;

    if (sentCount === 1 || sentCount % 100 === 0) {
      maxApi.post(`KAIROS Level UDP sent ${sentCount} packets to ${host}:${port}`);
    }
  });
}

function reportSendError(error) {
  errorCount += 1;

  if (errorCount <= 5 || errorCount % 100 === 0) {
    maxApi.post(`KAIROS Level UDP error ${errorCount} to ${host}:${port}: ${error.message}`);
  }
}

socket.on("error", (error) => {
  errorCount += 1;

  if (errorCount <= 5 || errorCount % 100 === 0) {
    maxApi.post(`KAIROS Level UDP socket error ${errorCount}: ${error.message}`);
  }
});

maxApi.addHandler("target", (nextHost, nextPort) => {
  if (nextHost) {
    host = String(nextHost);
  }

  if (nextPort) {
    const parsedPort = Number(nextPort);
    if (Number.isInteger(parsedPort) && parsedPort > 0 && parsedPort < 65536) {
      port = parsedPort;
    }
  }

  maxApi.post(`KAIROS Level UDP target ${host}:${port}`);
});

maxApi.addHandler("rms", (sourceSlot, sourceName, rmsL, rmsR, peakL, peakR, senderId, timestampMs) => {
  const parsedSourceSlot = Math.round(Number(sourceSlot));

  if (parsedSourceSlot < 1) {
    maxApi.post(`KAIROS Level UDP ignored invalid source ${sourceSlot}`);
    return;
  }

  sendPacket({
    type: "kairos.level.v1",
    sourceSlot: parsedSourceSlot,
    senderId: String(senderId || `kairos-level-${parsedSourceSlot}`),
    sourceName: String(sourceName || "Track"),
    rmsL: clamp01(rmsL),
    rmsR: clamp01(rmsR),
    peakL: clamp01(peakL),
    peakR: clamp01(peakR),
    timestampMs: Math.round(Number(timestampMs) || Date.now())
  });
});

maxApi.post(`KAIROS Level UDP node loaded. Target ${host}:${port}`);
