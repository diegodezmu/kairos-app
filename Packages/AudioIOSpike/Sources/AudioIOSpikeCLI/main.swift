import AudioIOSpikeSupport
import Foundation

struct CLIOptions {
    var outputPath: String?
    var captureDurationSeconds: TimeInterval = 1.0
}

enum CLIError: Error {
    case missingValue(flag: String)
    case unknownFlag(String)
}

func parseOptions(arguments: [String]) throws -> CLIOptions {
    var options = CLIOptions()
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]

        switch argument {
        case "--output":
            let nextIndex = index + 1
            guard nextIndex < arguments.count else {
                throw CLIError.missingValue(flag: argument)
            }
            options.outputPath = arguments[nextIndex]
            index = nextIndex
        case "--capture-seconds":
            let nextIndex = index + 1
            guard nextIndex < arguments.count else {
                throw CLIError.missingValue(flag: argument)
            }
            options.captureDurationSeconds = TimeInterval(arguments[nextIndex]) ?? options.captureDurationSeconds
            index = nextIndex
        default:
            throw CLIError.unknownFlag(argument)
        }

        index += 1
    }

    return options
}

do {
    let options = try parseOptions(arguments: Array(CommandLine.arguments.dropFirst()))
    let report = try AudioIOSpikeRunner.run(captureDurationSeconds: options.captureDurationSeconds)
    let rendered = TextReportFormatter.render(report)

    print(rendered)

    if let outputPath = options.outputPath {
        try rendered.write(
            to: URL(fileURLWithPath: outputPath),
            atomically: true,
            encoding: .utf8
        )
    }

    if !report.partA.passed {
        exit(1)
    }

    if report.partB.status == .failed {
        exit(2)
    }
} catch {
    fputs("AudioIOSpikeCLI error: \(error)\n", stderr)
    exit(3)
}
