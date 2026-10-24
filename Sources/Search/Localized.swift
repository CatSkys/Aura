import Foundation

// Translation.
//
// The English the app is written in is the key. A folder under Resources
// named after a language — Resources/zh-Hans.lproj, Resources/zh-Hant.lproj —
// holds Localizable.strings with the same sentences in that language, and
// macOS picks the folder by the Mac's own language order. A sentence a
// translation hasn't reached yet shows in English rather than not at all.
//
// Two ways in, and no third:
//
//   - Localized("…") takes the sentence as it is written, and gives back the
//     sentence in the language the app is running in. A sentence with a value
//     in it — Localized("Search \(version) is downloading…") — is keyed by its
//     shape, "Search {1} is downloading…", and the value is put back where the
//     translation asks for it: a translation may move {1}, leave it out, or
//     use it twice.
//
//   - A sentence that is already a String — an enum's title, a message from
//     somewhere else — is asked for at the place it is shown: `page.title.localized`.
//
// Views SwiftUI makes from a literal — Text("…"), Button("…"), Label("…"),
// Toggle("…"), Section("…") — would look themselves up, and they still do for
// the sentences that hold no value. Every one that does is written here
// anyway, so that the table has one shape rather than two.

/// A sentence on its way to being translated: what it says, and the values
/// its braces stand for. Made by a string literal — plain, or with `\(…)` in
/// it — and never written out by hand.
struct Sentence: ExpressibleByStringInterpolation {
    let key: String
    let values: [String]

    init(stringLiteral value: String) {
        key = value
        values = []
    }

    /// A sentence already in a String, looked up as it stands.
    init(_ text: String) {
        key = text
        values = []
    }

    init(stringInterpolation: Parts) {
        key = stringInterpolation.key
        values = stringInterpolation.values
    }

    struct Parts: StringInterpolationProtocol {
        var key = ""
        var values: [String] = []

        init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity + 2 * interpolationCount)
            values.reserveCapacity(interpolationCount)
        }

        mutating func appendLiteral(_ literal: String) {
            key += literal.replacingOccurrences(of: "{", with: "{{")
        }

        /// A value: written as `{1}`, `{2}` — its place in the sentence — so a
        /// translation can put it wherever its own grammar wants it.
        mutating func appendInterpolation<T>(_ value: T) {
            values.append(String(describing: value))
            key += "{\(values.count)}"
        }
    }
}

/// The sentence in the language the app is running in. The English itself
/// when there is no translation of it yet.
func Localized(_ sentence: Sentence) -> String {
    let table = Bundle.main.localizedString(forKey: sentence.key, value: sentence.key, table: nil)
    guard !sentence.values.isEmpty else { return table.replacingOccurrences(of: "{{", with: "{") }
    return fill(table, with: sentence.values)
}

/// `{1}` in the sentence, the first value in its place. `{{` is a brace the
/// sentence itself says. A brace left over from a translation that dropped a
/// value goes away, rather than showing as `{2}` on screen.
private func fill(_ sentence: String, with values: [String]) -> String {
    var out = ""
    out.reserveCapacity(sentence.count + 16)
    var index = sentence.startIndex
    while index < sentence.endIndex {
        let rest = sentence[index...]
        if rest.hasPrefix("{{") {
            out += "{"
            index = sentence.index(index, offsetBy: 2)
            continue
        }
        if rest.hasPrefix("{"), let close = rest.firstIndex(of: "}") {
            let inner = rest[rest.index(after: index)..<close]
            if let number = Int(inner), values.indices.contains(number - 1) {
                out += values[number - 1]
                index = sentence.index(after: close)
                continue
            }
        }
        out.append(sentence[index])
        index = sentence.index(after: index)
    }
    return out
}

/// The same, for a sentence already in a String.
extension String {
    var localized: String { Localized(Sentence(self)) }
}
