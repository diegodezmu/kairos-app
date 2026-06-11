import Foundation
import XCTest
@testable import KairosCore

final class KairosCoreScaffoldTests: XCTestCase {
    func testDummyPasses() {
        XCTAssertTrue(true)
        _ = KairosCoreScaffoldAnchor.self
    }

    func testKairosCoreDoesNotImportUIFrameworks() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcesRoot = packageRoot.appendingPathComponent("Sources/KairosCore", isDirectory: true)

        guard let enumerator = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil) else {
            XCTFail("Could not enumerate KairosCore sources.")
            return
        }

        let forbiddenImportRegex = try NSRegularExpression(
            pattern: #"^\s*import\s+(SwiftUI|AppKit|UIKit)\b"#,
            options: [.anchorsMatchLines]
        )
        var violations: [String] = []

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let contents = try String(contentsOf: fileURL)
            let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
            if forbiddenImportRegex.firstMatch(in: contents, options: [], range: range) != nil {
                let relativePath = fileURL.path.replacingOccurrences(
                    of: packageRoot.path + "/",
                    with: ""
                )
                violations.append(relativePath)
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Forbidden UI imports found:\n\(violations.sorted().joined(separator: "\n"))"
        )
    }
}
