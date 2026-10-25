// Compiles the block list this build ships, the way the browser does.
//
// Shield.swift hands WebKit three files of JSON, and WebKit either takes a file
// or refuses all of it over one rule it cannot read. A converter change that
// produced a refused file would otherwise show up as a page that quietly keeps
// its adverts, so the files are compiled here first.
//
//   ./Tests/BlockerRegression/run.sh

import CryptoKit
import Foundation
import WebKit

/// A short, stable name for a file's contents, so a changed list compiles under
/// a new name rather than being answered by the last one.
func fingerprint(_ text: String) -> String {
    return String(SHA256.hash(data: Data(text.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
        .prefix(16))
}

let root = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Resources/Shield")

guard let store = WKContentRuleListStore.default() else {
    print("WebKit has nowhere to compile a rule list")
    exit(1)
}

var bad = 0
for part in ["network", "extra", "cosmetic"] {
    let path = root.appendingPathComponent("\(part).json")
    guard let json = try? String(contentsOf: path, encoding: .utf8) else {
        print("\(part): not here (\(path.path)) — run ./Tools/filters.py")
        bad += 1
        continue
    }
    let start = Date()
    var settled = false
    store.compileContentRuleList(
        forIdentifier: "aura-blocker-check-\(part)-\(fingerprint(json))",
        encodedContentRuleList: json
    ) { _, error in
        let took = String(format: "%.1f", Date().timeIntervalSince(start))
        if let error {
            print("\(part): refused after \(took)s — \(error.localizedDescription)")
            bad += 1
        } else {
            let size = ByteCountFormatter.string(
                fromByteCount: Int64(json.utf8.count), countStyle: .file)
            print("\(part): \(size) of rules compiled in \(took)s")
        }
        settled = true
    }
    while !settled, RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) {}
}

exit(bad == 0 ? 0 : 1)
