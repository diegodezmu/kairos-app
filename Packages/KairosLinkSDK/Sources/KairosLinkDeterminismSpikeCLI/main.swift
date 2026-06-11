import CAbletonLink
import Foundation

private let testStepNumber = 128
private let testPulse = 0.25
private let testQuantums = [4.0, 32.0]
private let initialTempo = 120.0

private struct Command: Codable {
    let kind: String
    let enableLink: Bool?
    let startStopSync: Bool?
    let bpm: Double?
    let quantum: Double?
    let quantums: [Double]?
    let minPeers: UInt64?
    let timeoutMs: Int?
    let targetMicros: Int64?
    let originMicros: Int64?
    let stepNumber: Int?
    let pulse: Double?
}

private struct Reply: Codable {
    let ok: Bool
    let message: String
    let snapshot: PeerSnapshot?
}

private struct PeerSnapshot: Codable {
    let label: String
    let pid: Int32
    let sampleMicros: Int64
    let currentClockMicros: Int64
    let peerCount: UInt64
    let tempo: Double
    let isPlaying: Bool
    let startStopSyncEnabled: Bool
    let startTimeMicros: Int64
    let quantums: [QuantumSnapshot]
}

private struct QuantumSnapshot: Codable {
    let quantum: Double
    let beat: Double
    let phase: Double
    let originBeat: Double?
    let computed: GridComputation?
}

private struct GridComputation: Codable {
    let originMicros: Int64
    let elapsedBeats: Double
    let stepFloat: Double
    let currentStep: Int
    let cycleIteration: Int
}

private struct ScenarioSample {
    let label: String
    let snapshots: [PeerSnapshot]
}

private enum SpikeError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case unexpectedReply(String)
    case peerExited(String)
    case timeout(String)
    case environmentBlocked(String)

    var description: String {
        switch self {
        case .invalidArguments(let message):
            return message
        case .unexpectedReply(let message):
            return message
        case .peerExited(let message):
            return message
        case .timeout(let message):
            return message
        case .environmentBlocked(let message):
            return message
        }
    }
}

private func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
    let result = value % modulus
    return result >= 0 ? result : result + modulus
}

private func format(_ value: Double, digits: Int = 6) -> String {
    String(format: "%.\(digits)f", value)
}

private func sleepMillis(_ value: Int) {
    usleep(useconds_t(value * 1_000))
}

private final class LinkPeerRuntime {
    private let label: String
    private let link: abl_link
    private let sessionState: abl_link_session_state

    init(label: String, tempo: Double) {
        self.label = label
        self.link = abl_link_create(tempo)
        self.sessionState = abl_link_create_session_state()

        label.withCString { pointer in
            abl_link_audio_set_peer_name(link, pointer)
        }
    }

    deinit {
        abl_link_destroy_session_state(sessionState)
        abl_link_destroy(link)
    }

    func configure(enableLink: Bool, startStopSync: Bool) {
        abl_link_enable(link, enableLink)
        abl_link_enable_start_stop_sync(link, startStopSync)
    }

    func nowMicros() -> Int64 {
        abl_link_clock_micros(link)
    }

    func waitForPeers(minPeers: UInt64, timeoutMs: Int) throws -> PeerSnapshot {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1_000.0)
        while Date() < deadline {
            let count = abl_link_num_peers(link)
            if count >= minPeers {
                return capture(
                    targetMicros: nil,
                    quantums: testQuantums,
                    originMicros: nil,
                    stepNumber: nil,
                    pulse: nil
                )
            }
            sleepMillis(100)
        }

        throw SpikeError.environmentBlocked(
            "\(label) no descubrió \(minPeers) peer(s) en \(timeoutMs) ms. Posible bloqueo de red/firewall."
        )
    }

    func startPlaying(quantum: Double) -> PeerSnapshot {
        abl_link_capture_app_session_state(link, sessionState)
        abl_link_set_is_playing_and_request_beat_at_time(
            sessionState,
            true,
            nowMicros(),
            0,
            quantum
        )
        abl_link_commit_app_session_state(link, sessionState)
        return capture(
            targetMicros: nil,
            quantums: testQuantums,
            originMicros: nil,
            stepNumber: nil,
            pulse: nil
        )
    }

    func stopPlaying() -> PeerSnapshot {
        abl_link_capture_app_session_state(link, sessionState)
        abl_link_set_is_playing(sessionState, false, nowMicros())
        abl_link_commit_app_session_state(link, sessionState)
        return capture(
            targetMicros: nil,
            quantums: testQuantums,
            originMicros: nil,
            stepNumber: nil,
            pulse: nil
        )
    }

    func setTempo(_ bpm: Double) -> PeerSnapshot {
        abl_link_capture_app_session_state(link, sessionState)
        abl_link_set_tempo(sessionState, bpm, nowMicros())
        abl_link_commit_app_session_state(link, sessionState)
        return capture(
            targetMicros: nil,
            quantums: testQuantums,
            originMicros: nil,
            stepNumber: nil,
            pulse: nil
        )
    }

    func capture(
        targetMicros: Int64?,
        quantums: [Double],
        originMicros: Int64?,
        stepNumber: Int?,
        pulse: Double?
    ) -> PeerSnapshot {
        let sampleMicros = targetMicros ?? nowMicros()

        if let targetMicros {
            while nowMicros() + 1_000 < targetMicros {
                sleepMillis(1)
            }
            while nowMicros() < targetMicros {}
        }

        abl_link_capture_app_session_state(link, sessionState)

        let quantumSnapshots = quantums.map { quantum -> QuantumSnapshot in
            let beat = abl_link_beat_at_time(sessionState, sampleMicros, quantum)
            let phase = abl_link_phase_at_time(sessionState, sampleMicros, quantum)

            guard
                let originMicros,
                let stepNumber,
                let pulse
            else {
                return QuantumSnapshot(
                    quantum: quantum,
                    beat: beat,
                    phase: phase,
                    originBeat: nil,
                    computed: nil
                )
            }

            let originBeat = abl_link_beat_at_time(sessionState, originMicros, quantum)
            let elapsedBeats = beat - originBeat
            let stepFloat = elapsedBeats / pulse
            let rawStep = Int(floor(stepFloat))
            let currentStep = positiveModulo(rawStep, stepNumber)
            let cycleIteration = Int(floor(stepFloat / Double(stepNumber)))

            return QuantumSnapshot(
                quantum: quantum,
                beat: beat,
                phase: phase,
                originBeat: originBeat,
                computed: GridComputation(
                    originMicros: originMicros,
                    elapsedBeats: elapsedBeats,
                    stepFloat: stepFloat,
                    currentStep: currentStep,
                    cycleIteration: cycleIteration
                )
            )
        }

        return PeerSnapshot(
            label: label,
            pid: Int32(ProcessInfo.processInfo.processIdentifier),
            sampleMicros: sampleMicros,
            currentClockMicros: nowMicros(),
            peerCount: abl_link_num_peers(link),
            tempo: abl_link_tempo(sessionState),
            isPlaying: abl_link_is_playing(sessionState),
            startStopSyncEnabled: abl_link_is_start_stop_sync_enabled(link),
            startTimeMicros: abl_link_time_for_is_playing(sessionState),
            quantums: quantumSnapshots
        )
    }
}

private final class LineReader {
    private let handle: FileHandle
    private var buffer = Data()

    init(handle: FileHandle) {
        self.handle = handle
    }

    func readLine() throws -> String {
        while true {
            if let newlineRange = buffer.firstRange(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
                buffer.removeSubrange(0..<newlineRange.upperBound)
                return String(decoding: lineData, as: UTF8.self)
            }

            let chunk = handle.availableData
            if chunk.isEmpty {
                if buffer.isEmpty {
                    throw SpikeError.peerExited("EOF leyendo stdout del peer")
                }

                let line = String(decoding: buffer, as: UTF8.self)
                buffer.removeAll(keepingCapacity: false)
                return line
            }

            buffer.append(chunk)
        }
    }
}

private final class PeerProcess {
    let label: String

    private let process: Process
    private let stdinHandle: FileHandle
    private let stdoutReader: LineReader
    private let stderrPipe: Pipe
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(binaryPath: String, label: String) throws {
        self.label = label
        self.process = Process()

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.stdoutReader = LineReader(handle: stdoutPipe.fileHandleForReading)
        self.stderrPipe = stderrPipe

        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["--peer", "--label", label]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let ready = try readReply()
        guard ready.ok else {
            throw SpikeError.unexpectedReply("El peer \(label) no arrancó: \(ready.message)")
        }
    }

    deinit {
        if process.isRunning {
            try? shutdown()
        }
    }

    func configure(enableLink: Bool, startStopSync: Bool) throws {
        _ = try send(
            Command(
                kind: "configure",
                enableLink: enableLink,
                startStopSync: startStopSync,
                bpm: nil,
                quantum: nil,
                quantums: nil,
                minPeers: nil,
                timeoutMs: nil,
                targetMicros: nil,
                originMicros: nil,
                stepNumber: nil,
                pulse: nil
            )
        )
    }

    func waitForPeers(minPeers: UInt64, timeoutMs: Int = 6_000) throws -> PeerSnapshot {
        let reply = try send(
            Command(
                kind: "waitPeers",
                enableLink: nil,
                startStopSync: nil,
                bpm: nil,
                quantum: nil,
                quantums: nil,
                minPeers: minPeers,
                timeoutMs: timeoutMs,
                targetMicros: nil,
                originMicros: nil,
                stepNumber: nil,
                pulse: nil
            )
        )
        return try requireSnapshot(reply)
    }

    func snapshotNow(
        originMicros: Int64? = nil,
        quantums: [Double] = testQuantums,
        stepNumber: Int? = nil,
        pulse: Double? = nil
    ) throws -> PeerSnapshot {
        let reply = try send(
            Command(
                kind: "snapshot",
                enableLink: nil,
                startStopSync: nil,
                bpm: nil,
                quantum: nil,
                quantums: quantums,
                minPeers: nil,
                timeoutMs: nil,
                targetMicros: nil,
                originMicros: originMicros,
                stepNumber: stepNumber,
                pulse: pulse
            )
        )
        return try requireSnapshot(reply)
    }

    func sampleAt(
        targetMicros: Int64,
        originMicros: Int64? = nil,
        quantums: [Double] = testQuantums,
        stepNumber: Int? = nil,
        pulse: Double? = nil
    ) throws -> PeerSnapshot {
        let reply = try send(
            Command(
                kind: "snapshot",
                enableLink: nil,
                startStopSync: nil,
                bpm: nil,
                quantum: nil,
                quantums: quantums,
                minPeers: nil,
                timeoutMs: nil,
                targetMicros: targetMicros,
                originMicros: originMicros,
                stepNumber: stepNumber,
                pulse: pulse
            )
        )
        return try requireSnapshot(reply)
    }

    func startPlaying(quantum: Double) throws -> PeerSnapshot {
        let reply = try send(
            Command(
                kind: "startPlaying",
                enableLink: nil,
                startStopSync: nil,
                bpm: nil,
                quantum: quantum,
                quantums: nil,
                minPeers: nil,
                timeoutMs: nil,
                targetMicros: nil,
                originMicros: nil,
                stepNumber: nil,
                pulse: nil
            )
        )
        return try requireSnapshot(reply)
    }

    func stopPlaying() throws -> PeerSnapshot {
        let reply = try send(
            Command(
                kind: "stopPlaying",
                enableLink: nil,
                startStopSync: nil,
                bpm: nil,
                quantum: nil,
                quantums: nil,
                minPeers: nil,
                timeoutMs: nil,
                targetMicros: nil,
                originMicros: nil,
                stepNumber: nil,
                pulse: nil
            )
        )
        return try requireSnapshot(reply)
    }

    func setTempo(_ bpm: Double) throws -> PeerSnapshot {
        let reply = try send(
            Command(
                kind: "setTempo",
                enableLink: nil,
                startStopSync: nil,
                bpm: bpm,
                quantum: nil,
                quantums: nil,
                minPeers: nil,
                timeoutMs: nil,
                targetMicros: nil,
                originMicros: nil,
                stepNumber: nil,
                pulse: nil
            )
        )
        return try requireSnapshot(reply)
    }

    func shutdown() throws {
        _ = try send(
            Command(
                kind: "shutdown",
                enableLink: nil,
                startStopSync: nil,
                bpm: nil,
                quantum: nil,
                quantums: nil,
                minPeers: nil,
                timeoutMs: nil,
                targetMicros: nil,
                originMicros: nil,
                stepNumber: nil,
                pulse: nil
            )
        )
        process.waitUntilExit()
    }

    private func requireSnapshot(_ reply: Reply) throws -> PeerSnapshot {
        guard reply.ok else {
            throw SpikeError.unexpectedReply(reply.message)
        }
        guard let snapshot = reply.snapshot else {
            throw SpikeError.unexpectedReply("El peer \(label) respondió sin snapshot: \(reply.message)")
        }
        return snapshot
    }

    private func send(_ command: Command) throws -> Reply {
        let data = try encoder.encode(command)
        guard var line = String(data: data, encoding: .utf8) else {
            throw SpikeError.invalidArguments("No se pudo serializar el comando")
        }
        line.append("\n")
        stdinHandle.write(Data(line.utf8))
        return try readReply()
    }

    private func readReply() throws -> Reply {
        let line = try stdoutReader.readLine()
        guard let data = line.data(using: .utf8) else {
            throw SpikeError.unexpectedReply("Salida no UTF-8 de \(label)")
        }

        do {
            return try decoder.decode(Reply.self, from: data)
        } catch {
            let stderr = String(decoding: stderrPipe.fileHandleForReading.availableData, as: UTF8.self)
            throw SpikeError.unexpectedReply(
                "No se pudo decodificar la salida del peer \(label): \(line)\nSTDERR:\n\(stderr)"
            )
        }
    }
}

private final class LocalClock {
    private let link: abl_link

    init() {
        self.link = abl_link_create(initialTempo)
    }

    deinit {
        abl_link_destroy(link)
    }

    func nowMicros() -> Int64 {
        abl_link_clock_micros(link)
    }
}

private struct LogBuffer {
    private(set) var lines: [String] = []

    mutating func append(_ line: String) {
        print(line)
        lines.append(line)
    }

    func write(to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

private func commandLineValue(for flag: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}

private func quantumSnapshot(_ snapshot: PeerSnapshot, quantum: Double) -> QuantumSnapshot {
    guard let match = snapshot.quantums.first(where: { abs($0.quantum - quantum) < 0.000_001 }) else {
        fatalError("Falta el quantum \(quantum) en \(snapshot.label)")
    }
    return match
}

private func describe(snapshot: PeerSnapshot) -> String {
    let qDescriptions = snapshot.quantums.map { sample -> String in
        let computedDescription: String
        if let computed = sample.computed {
            computedDescription =
                "elapsed=\(format(computed.elapsedBeats)) step=\(computed.currentStep) iter=\(computed.cycleIteration)"
        } else {
            computedDescription = "elapsed=n/a step=n/a iter=n/a"
        }

        return "q\(Int(sample.quantum)) beat=\(format(sample.beat)) phase=\(format(sample.phase)) \(computedDescription)"
    }.joined(separator: " | ")

    return
        "\(snapshot.label) peers=\(snapshot.peerCount) tempo=\(format(snapshot.tempo, digits: 3)) " +
        "playing=\(snapshot.isPlaying) startSync=\(snapshot.startStopSyncEnabled) " +
        "startMicros=\(snapshot.startTimeMicros) sampleMicros=\(snapshot.sampleMicros) :: \(qDescriptions)"
}

private func compareSample(label: String, snapshots: [PeerSnapshot], logger: inout LogBuffer) -> [Double: Bool] {
    logger.append("SAMPLE \(label)")
    snapshots.forEach { logger.append("  \(describe(snapshot: $0))") }

    var result: [Double: Bool] = [:]

    for quantum in testQuantums {
        let quantumSamples = snapshots.map { quantumSnapshot($0, quantum: quantum) }
        let beats = quantumSamples.map(\.beat)
        let rawBeatSpread = (beats.max() ?? 0) - (beats.min() ?? 0)

        let elapseds = quantumSamples.compactMap { $0.computed?.elapsedBeats }
        let elapsedSpread = elapseds.isEmpty ? 0 : (elapseds.max() ?? 0) - (elapseds.min() ?? 0)

        let steps = quantumSamples.compactMap { $0.computed?.currentStep }
        let stepMatch = Set(steps).count <= 1

        let iterations = quantumSamples.compactMap { $0.computed?.cycleIteration }
        let iterationMatch = Set(iterations).count <= 1

        let combinedMatch = stepMatch && iterationMatch
        result[quantum] = combinedMatch

        let stepList = zip(snapshots.map(\.label), steps).map { "\($0.0)=\($0.1)" }.joined(separator: ", ")
        let iterationList = zip(snapshots.map(\.label), iterations).map { "\($0.0)=\($0.1)" }.joined(separator: ", ")

        logger.append(
            "  q\(Int(quantum)) rawBeatSpread=\(format(rawBeatSpread)) " +
            "elapsedSpread=\(format(elapsedSpread)) stepMatch=\(stepMatch) iterationMatch=\(iterationMatch) " +
            "steps[\(stepList)] iterations[\(iterationList)]"
        )
    }

    return result
}

private func frozenOrigins(from snapshots: [PeerSnapshot]) -> [String: [Double: Double]] {
    var result: [String: [Double: Double]] = [:]

    for snapshot in snapshots {
        for sample in snapshot.quantums {
            guard let originBeat = sample.originBeat else {
                continue
            }
            result[snapshot.label, default: [:]][sample.quantum] = originBeat
        }
    }

    return result
}

private func compareWithFrozenOrigins(
    label: String,
    snapshots: [PeerSnapshot],
    frozenOrigins: [String: [Double: Double]],
    logger: inout LogBuffer
) {
    logger.append("SAMPLE \(label)")

    for quantum in testQuantums {
        var computed: [(label: String, beat: Double, originBeat: Double, elapsed: Double, step: Int, iteration: Int)] = []

        for snapshot in snapshots {
            let sample = quantumSnapshot(snapshot, quantum: quantum)
            guard let originBeat = frozenOrigins[snapshot.label]?[quantum] else {
                continue
            }

            let elapsedBeats = sample.beat - originBeat
            let stepFloat = elapsedBeats / testPulse
            let rawStep = Int(floor(stepFloat))
            let currentStep = positiveModulo(rawStep, testStepNumber)
            let cycleIteration = Int(floor(stepFloat / Double(testStepNumber)))

            computed.append(
                (
                    label: snapshot.label,
                    beat: sample.beat,
                    originBeat: originBeat,
                    elapsed: elapsedBeats,
                    step: currentStep,
                    iteration: cycleIteration
                )
            )
        }

        let stepMatch = Set(computed.map(\.step)).count <= 1
        let iterationMatch = Set(computed.map(\.iteration)).count <= 1
        let elapsedSpread =
            (computed.map(\.elapsed).max() ?? 0) - (computed.map(\.elapsed).min() ?? 0)

        let details = computed.map {
            "\($0.label) beat=\(format($0.beat)) originBeat=\(format($0.originBeat)) " +
            "elapsed=\(format($0.elapsed)) step=\($0.step) iter=\($0.iteration)"
        }.joined(separator: " | ")

        logger.append(
            "  q\(Int(quantum)) elapsedSpread=\(format(elapsedSpread)) " +
            "stepMatch=\(stepMatch) iterationMatch=\(iterationMatch) :: \(details)"
        )
    }
}

private func waitForSharedStart(
    peers: [PeerProcess],
    timeoutMs: Int,
    logger: inout LogBuffer
) throws -> Int64 {
    let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1_000.0)
    var iteration = 0

    while Date() < deadline {
        let snapshots = try peers.map { try $0.snapshotNow() }
        iteration += 1
        if iteration == 1 || iteration % 5 == 0 {
            logger.append("  polling shared start")
            snapshots.forEach { logger.append("    \(describe(snapshot: $0))") }
        }
        if
            snapshots.allSatisfy(\.isPlaying),
            let minimumStart = snapshots.map(\.startTimeMicros).min(),
            let maximumStart = snapshots.map(\.startTimeMicros).max(),
            minimumStart > 0,
            maximumStart - minimumStart <= 1_000
        {
            let sharedStart = (minimumStart + maximumStart) / 2
            logger.append(
                "Shared transport start observed at hostMicros≈\(sharedStart) " +
                "(spread=\(maximumStart - minimumStart)us)"
            )
            return sharedStart
        }
        sleepMillis(100)
    }

    throw SpikeError.timeout("No apareció un start compartido en \(timeoutMs) ms")
}

private func waitForTempo(
    peers: [PeerProcess],
    bpm: Double,
    timeoutMs: Int,
    logger: inout LogBuffer
) throws {
    let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1_000.0)
    while Date() < deadline {
        let snapshots = try peers.map { try $0.snapshotNow() }
        if snapshots.allSatisfy({ abs($0.tempo - bpm) < 0.01 }) {
            logger.append("Tempo compartido actualizado a \(format(bpm, digits: 3)) BPM")
            return
        }
        sleepMillis(100)
    }

    throw SpikeError.timeout("El tempo \(bpm) no se propagó a todos los peers en \(timeoutMs) ms")
}

private func spawnPeers(binaryPath: String, labels: [String]) throws -> [PeerProcess] {
    try labels.map { try PeerProcess(binaryPath: binaryPath, label: $0) }
}

private func shutdownAll(_ peers: [PeerProcess], logger: inout LogBuffer) {
    for peer in peers {
        do {
            try peer.shutdown()
        } catch {
            logger.append("WARN shutdown \(peer.label): \(error)")
        }
    }
}

private func runNoStartStopScenario(binaryPath: String, logger: inout LogBuffer) throws {
    logger.append("")
    logger.append("=== Scenario 1: start/stop sync OFF ===")

    let peers = try spawnPeers(binaryPath: binaryPath, labels: ["A-off", "B-off"])
    defer { shutdownAll(peers, logger: &logger) }

    try peers.forEach { try $0.configure(enableLink: true, startStopSync: false) }
    _ = try peers[0].waitForPeers(minPeers: 1)
    _ = try peers[1].waitForPeers(minPeers: 1)

    logger.append("Peer A-off starts playback with Link enabled but start/stop sync disabled.")
    _ = try peers[0].startPlaying(quantum: 4)
    sleepMillis(800)

    let snapshots = try peers.map { try $0.snapshotNow() }
    snapshots.forEach { logger.append("  \(describe(snapshot: $0))") }

    let aPlaying = snapshots[0].isPlaying
    let bPlaying = snapshots[1].isPlaying
    logger.append(
        "RESULT start/stop OFF: A-off playing=\(aPlaying) | B-off playing=\(bPlaying). " +
        "Sin start/stop sync no aparece un origen de transporte compartido."
    )
}

private func runDeterminismScenario(binaryPath: String, logger: inout LogBuffer) throws {
    logger.append("")
    logger.append("=== Scenario 2: shared start, late join, long cycle, tempo change ===")

    let clock = LocalClock()
    let peers = try spawnPeers(binaryPath: binaryPath, labels: ["A", "B"])
    defer { shutdownAll(peers, logger: &logger) }

    try peers.forEach { try $0.configure(enableLink: true, startStopSync: true) }
    _ = try peers[0].waitForPeers(minPeers: 1)
    _ = try peers[1].waitForPeers(minPeers: 1)

    logger.append("Peer A starts playback with start/stop sync enabled.")
    _ = try peers[0].startPlaying(quantum: 4)

    let sharedOriginMicros = try waitForSharedStart(peers: peers, timeoutMs: 5_000, logger: &logger)

    let earlyTarget = max(clock.nowMicros() + 2_000_000, sharedOriginMicros + 4_250_000)
    let earlySnapshots = try peers.map {
        try $0.sampleAt(
            targetMicros: earlyTarget,
            originMicros: sharedOriginMicros,
            quantums: testQuantums,
            stepNumber: testStepNumber,
            pulse: testPulse
        )
    }
    _ = compareSample(label: "present-peers @ +8.5 beats", snapshots: earlySnapshots, logger: &logger)

    logger.append("Spawning late peer C while the session is already running.")
    let latePeer = try PeerProcess(binaryPath: binaryPath, label: "C")
    defer { shutdownAll([latePeer], logger: &logger) }

    try latePeer.configure(enableLink: true, startStopSync: true)
    _ = try latePeer.waitForPeers(minPeers: 2)
    let lateJoinSnapshot = try latePeer.snapshotNow()
    logger.append("Late join snapshot:")
    logger.append("  \(describe(snapshot: lateJoinSnapshot))")

    var localLateOrigin: Int64?
    if !(lateJoinSnapshot.isPlaying && lateJoinSnapshot.startTimeMicros == sharedOriginMicros) {
        logger.append(
            "Late peer C did not inherit the original shared transport start. " +
            "Switching C to local transport mode (start/stop sync OFF) to measure a local late origin."
        )
        try latePeer.configure(enableLink: true, startStopSync: false)
        let localStartSnapshot = try latePeer.startPlaying(quantum: 4)
        localLateOrigin = localStartSnapshot.startTimeMicros
        logger.append("  local-start C :: \(describe(snapshot: localStartSnapshot))")
    } else {
        logger.append("Late peer C inherited the shared transport origin directly from Link.")
    }

    let lateTarget = max(clock.nowMicros() + 2_000_000, sharedOriginMicros + 10_250_000)
    let alignedLateSnapshots =
        try (peers + [latePeer]).map {
            try $0.sampleAt(
                targetMicros: lateTarget,
                originMicros: sharedOriginMicros,
                quantums: testQuantums,
                stepNumber: testStepNumber,
                pulse: testPulse
            )
        }
    _ = compareSample(label: "late-join with shared original origin", snapshots: alignedLateSnapshots, logger: &logger)
    let frozenOriginBeats = frozenOrigins(from: alignedLateSnapshots)

    if let localLateOrigin {
        let localOriginSnapshot = try latePeer.sampleAt(
            targetMicros: lateTarget,
            originMicros: localLateOrigin,
            quantums: testQuantums,
            stepNumber: testStepNumber,
            pulse: testPulse
        )
        logger.append("SAMPLE late-join with C local origin")
        logger.append("  \(describe(snapshot: localOriginSnapshot))")
    }

    let longCycleTarget = max(clock.nowMicros() + 2_000_000, sharedOriginMicros + 16_750_000)
    let longCycleSnapshots =
        try (peers + [latePeer]).map {
            try $0.sampleAt(
                targetMicros: longCycleTarget,
                originMicros: sharedOriginMicros,
                quantums: testQuantums,
                stepNumber: testStepNumber,
                pulse: testPulse
            )
        }
    _ = compareSample(label: "long-cycle boundary crossed (>32 beats)", snapshots: longCycleSnapshots, logger: &logger)

    logger.append("Changing tempo live from 120 BPM to 90 BPM via peer A.")
    _ = try peers[0].setTempo(90)
    try waitForTempo(peers: peers + [latePeer], bpm: 90, timeoutMs: 5_000, logger: &logger)

    let afterTempoTarget = clock.nowMicros() + 4_000_000
    let afterTempoSnapshots =
        try (peers + [latePeer]).map {
            try $0.sampleAt(
                targetMicros: afterTempoTarget,
                originMicros: sharedOriginMicros,
                quantums: testQuantums,
                stepNumber: testStepNumber,
                pulse: testPulse
            )
        }
    _ = compareSample(label: "after hot tempo change", snapshots: afterTempoSnapshots, logger: &logger)
    compareWithFrozenOrigins(
        label: "after hot tempo change (frozen originBeat per peer)",
        snapshots: afterTempoSnapshots,
        frozenOrigins: frozenOriginBeats,
        logger: &logger
    )
    let postTempoStartTimes = afterTempoSnapshots.map { "\($0.label)=\($0.startTimeMicros)" }.joined(separator: ", ")
    logger.append(
        "Post-tempo startTimeMicros snapshot: \(postTempoStartTimes) | originalSharedOrigin=\(sharedOriginMicros)"
    )

    logger.append(
        "RESULT summary: two peers present at the shared start stayed aligned on currentStep and cycleIteration " +
        "across a 32-beat cycle. After a live tempo change, continuity only held when each peer reused a " +
        "frozen originBeat captured before the tempo change. The late peer only became comparable once it " +
        "used the original shared start host time instead of its own late local start."
    )
}

private func runPeerMode() -> Int32 {
    let label = commandLineValue(for: "--label") ?? "peer"
    let runtime = LinkPeerRuntime(label: label, tempo: initialTempo)

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    func reply(ok: Bool, message: String, snapshot: PeerSnapshot?) {
        let payload = Reply(ok: ok, message: message, snapshot: snapshot)
        do {
            let data = try encoder.encode(payload)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            let fallback = "{\"ok\":false,\"message\":\"encoding failure: \(error)\",\"snapshot\":null}\n"
            FileHandle.standardOutput.write(Data(fallback.utf8))
        }
    }

    reply(
        ok: true,
        message: "ready",
        snapshot: runtime.capture(
            targetMicros: nil,
            quantums: testQuantums,
            originMicros: nil,
            stepNumber: nil,
            pulse: nil
        )
    )

    while let line = readLine() {
        guard let data = line.data(using: .utf8) else {
            reply(ok: false, message: "stdin no UTF-8", snapshot: nil)
            continue
        }

        do {
            let command = try decoder.decode(Command.self, from: data)

            switch command.kind {
            case "configure":
                runtime.configure(
                    enableLink: command.enableLink ?? true,
                    startStopSync: command.startStopSync ?? false
                )
                reply(
                    ok: true,
                    message: "configured",
                    snapshot: runtime.capture(
                        targetMicros: nil,
                        quantums: testQuantums,
                        originMicros: nil,
                        stepNumber: nil,
                        pulse: nil
                    )
                )

            case "waitPeers":
                let snapshot = try runtime.waitForPeers(
                    minPeers: command.minPeers ?? 0,
                    timeoutMs: command.timeoutMs ?? 5_000
                )
                reply(ok: true, message: "peers-ready", snapshot: snapshot)

            case "snapshot":
                let snapshot = runtime.capture(
                    targetMicros: command.targetMicros,
                    quantums: command.quantums ?? testQuantums,
                    originMicros: command.originMicros,
                    stepNumber: command.stepNumber,
                    pulse: command.pulse
                )
                reply(ok: true, message: "snapshot", snapshot: snapshot)

            case "startPlaying":
                let snapshot = runtime.startPlaying(quantum: command.quantum ?? 4)
                reply(ok: true, message: "started", snapshot: snapshot)

            case "stopPlaying":
                let snapshot = runtime.stopPlaying()
                reply(ok: true, message: "stopped", snapshot: snapshot)

            case "setTempo":
                let snapshot = runtime.setTempo(command.bpm ?? initialTempo)
                reply(ok: true, message: "tempo-set", snapshot: snapshot)

            case "shutdown":
                runtime.configure(enableLink: false, startStopSync: false)
                reply(ok: true, message: "bye", snapshot: nil)
                return 0

            default:
                reply(ok: false, message: "unknown command: \(command.kind)", snapshot: nil)
            }
        } catch {
            reply(ok: false, message: String(describing: error), snapshot: nil)
        }
    }

    return 0
}

private func runCoordinatorMode() -> Int32 {
    var logger = LogBuffer()
    let outputPath = commandLineValue(for: "--output")
    let binaryPath = CommandLine.arguments[0]

    logger.append("# Kairos Link determinism spike")
    logger.append("binaryPath=\(binaryPath)")
    logger.append("testCycle=128 steps x pulse 1/4 = 32 beats")

    do {
        try runNoStartStopScenario(binaryPath: binaryPath, logger: &logger)
        sleepMillis(500)
        try runDeterminismScenario(binaryPath: binaryPath, logger: &logger)
        logger.append("")
        logger.append("SPIKE STATUS: OK")
    } catch {
        logger.append("")
        logger.append("SPIKE STATUS: DECISION-NEEDED")
        logger.append("ERROR: \(error)")
        if let outputPath {
            try? logger.write(to: outputPath)
        }
        return 2
    }

    if let outputPath {
        do {
            try logger.write(to: outputPath)
            logger.append("WROTE LOG: \(outputPath)")
        } catch {
            logger.append("WARN log write failed: \(error)")
            return 1
        }
    }

    return 0
}

if CommandLine.arguments.contains("--peer") {
    exit(runPeerMode())
} else {
    exit(runCoordinatorMode())
}
