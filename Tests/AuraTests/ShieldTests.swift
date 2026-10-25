import XCTest
@testable import Aura

/// What the block list that ships has to be true of.
///
/// The rules themselves are other people's, converted by `Tools/filters.py`.
/// What is worth testing here is that the conversion produced something
/// WebKit's matcher can read, and that the ordering the whole design rests on
/// survived it. Whether WebKit takes the files is
/// `./Tests/BlockerRegression/run.sh` — compiling 113,000 rules belongs in a
/// runner that can say how long it took, not in a unit test.
final class ShieldTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/Shield")

    private func rules(_ part: String) throws -> [[String: Any]] {
        let packed = try Data(contentsOf: Self.root.appendingPathComponent("\(part).json.z"))
        let json = try XCTUnwrap(Shield.unpack(packed), "\(part) would not unpack")
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try XCTUnwrap(parsed as? [[String: Any]], part)
    }

    func testEveryRuleSaysWhatToMatchAndWhatToDo() throws {
        for part in ["network", "extra", "cosmetic"] {
            let rules = try rules(part)
            XCTAssertFalse(rules.isEmpty, part)
            for rule in rules {
                let trigger = try XCTUnwrap(rule["trigger"] as? [String: Any], part)
                let filter = try XCTUnwrap(trigger["url-filter"] as? String, part)
                XCTAssertFalse(filter.isEmpty, part)
                let action = try XCTUnwrap(rule["action"] as? [String: Any], part)
                XCTAssertNotNil(action["type"] as? String, part)
            }
        }
    }

    /// WebKit's url matcher reads a smaller language than a regular expression:
    /// no alternatives, no `\d`, no counted repetitions, no lookaround. One rule
    /// reaching for any of it costs the whole file, so the conversion leaves
    /// those filters out — and this is what says it did. What a filter wants to
    /// match literally is written with a backslash in front — `\|`, `\{` — and
    /// that is a character, not syntax.
    func testNoFilterAsksForSomethingWebKitsMatcherCannotRead() throws {
        let refusals = [
            #"(?<!\\)\|"#,             // alternatives
            #"(?<!\\)\{"#,             // counted repetition
            #"\\[dDwWsSbB1-9]"#,       // built-in classes, word boundaries, backreferences
            #"\(\?[<>=!P]"#,           // lookaround and named groups
        ].map { try! NSRegularExpression(pattern: $0) }

        for part in ["network", "extra", "cosmetic"] {
            for rule in try rules(part) {
                let trigger = rule["trigger"] as? [String: Any] ?? [:]
                guard let filter = trigger["url-filter"] as? String else { continue }
                let range = NSRange(filter.startIndex..., in: filter)
                for refusal in refusals {
                    XCTAssertNil(refusal.firstMatch(in: filter, range: range), "\(part): \(filter)")
                }
            }
        }
    }

    /// An exception takes back what was read before it, and nothing after it.
    func testExceptionsComeAfterTheRulesTheyAnswer() throws {
        for part in ["network", "extra"] {
            let types = try rules(part).compactMap { ($0["action"] as? [String: Any])?["type"] as? String }
            guard let first = types.firstIndex(of: "ignore-previous-rules") else {
                XCTFail("\(part) has no exceptions at all")
                continue
            }
            XCTAssertFalse(types[first...].contains("block"), part)
        }
    }

    /// Taking a page away is the one mistake with no way back from the page, so
    /// it is only ever in the file a site gets at Everything.
    func testOnlyTheFullHalfTakesPagesAway() throws {
        for rule in try rules("network") {
            let trigger = rule["trigger"] as? [String: Any] ?? [:]
            let kinds = trigger["resource-type"] as? [String] ?? []
            XCTAssertNotEqual(kinds, ["document"])
        }
        XCTAssertFalse(try rules("extra").isEmpty)
    }

    /// A site is Everything unless somebody said otherwise, and the last thing
    /// said about it is the one that holds.
    @MainActor
    func testASiteStartsAtEverythingAndKeepsTheLastWord() {
        let shield = Shield.shared
        XCTAssertEqual(shield.level(on: "example.invalid"), .everything)
        XCTAssertEqual(shield.level(on: nil), .everything)

        shield.set(.requests, on: "example.invalid")
        XCTAssertEqual(shield.level(on: "example.invalid"), .requests)
        shield.set(.off, on: "example.invalid")
        XCTAssertEqual(shield.level(on: "example.invalid"), .off)
        // Everything is the absence of a word, so it is not kept as one.
        shield.set(.everything, on: "example.invalid")
        XCTAssertEqual(shield.level(on: "example.invalid"), .everything)
        XCTAssertNil(shield.levels["example.invalid"])
    }
}
