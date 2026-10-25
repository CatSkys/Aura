// Compiles the block list this build ships, the way the browser does.
//
// Shield.swift hands WebKit three files of JSON, and WebKit either takes a file
// or refuses all of it over one rule it cannot read. A converter change that
// produced a refused file would otherwise show up as a page that quietly keeps
// its adverts, so the files are compiled here first.
//
//   ./Tests/BlockerRegression/run.sh

import Compression
import CryptoKit
import Foundation
import WebKit

/// A short, stable name for a file's contents, so a changed list compiles under
/// a new name rather than being answered by the last one.
func fingerprint(_ data: Data) -> String {
    return String(SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
        .prefix(16))
}

/// A copy of Shield.unpack: this runner is built without the app, so the one
/// thing it shares with the browser is the file format — four bytes saying how
/// big the rules were, then the deflate stream they were squeezed into.
func unpack(_ packed: Data) -> String? {
    guard packed.count > 4 else { return nil }
    let size = Int(packed[packed.startIndex]) << 24
        | Int(packed[packed.startIndex + 1]) << 16
        | Int(packed[packed.startIndex + 2]) << 8
        | Int(packed[packed.startIndex + 3])
    guard size > 0 else { return nil }
    var raw = [UInt8](repeating: 0, count: size)
    let written = packed.dropFirst(4).withUnsafeBytes { source -> Int in
        guard let start = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
        return compression_decode_buffer(&raw, size, start, source.count, nil, COMPRESSION_ZLIB)
    }
    guard written == size else { return nil }
    return String(decoding: raw, as: UTF8.self)
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
    let path = root.appendingPathComponent("\(part).json.z")
    guard let packed = try? Data(contentsOf: path), let json = unpack(packed) else {
        print("\(part): not here (\(path.path)) — run ./Tools/filters.py")
        bad += 1
        continue
    }
    let start = Date()
    var settled = false
    store.compileContentRuleList(
        forIdentifier: "aura-blocker-check-\(part)-\(fingerprint(packed))",
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
