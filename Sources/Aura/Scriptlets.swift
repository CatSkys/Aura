import Foundation
import WebKit

// The scripts a filter list asks a page to run — `##+js(set-constant, …)` and
// its like.
//
// Refusing a request is half of blocking. The other half is a site's own check
// for whether one was refused: a script that looks for an advert vendor's
// global or builds a bait element, and then covers the article until the
// blocker is turned off. Those checks are scripts too, and a script can be
// shown what it wants to see — which is what the lists' scriptlet rules do,
// and what Aura could not answer at all before.
//
// Resources/Shield/scriptlets.json.z is the lists' half (Tools/filters.py makes
// it) and scriptlets.js is the running half. They go into the page's own world
// at the start of the document, before the page's first script, because a check
// that has already run cannot be answered.
//
// Five thousand rules name twenty thousand sites, so a page is given the ones
// that name it — a handful, a few hundred bytes — rather than the lot. What a
// rule names travels with it anyway, so a frame from another site runs what the
// lists said about that site and not this page's rules.

@MainActor
enum Scriptlets {
    /// What a rule names: a site and everything under it, a pattern with a `*`
    /// where the list did not know the ending, or the negation of either.
    enum Site {
        case named(String)
        case wildcard(NSRegularExpression)
        case refused(String)
        case refusedWildcard(NSRegularExpression)
    }

    struct Rules {
        /// Each rule as JSON, ready to be handed to a page, and what it names.
        let texts: [String]
        let names: [[Site]]
    }

    static var isReady: Bool { loaded != nil && runtime != nil }

    /// The script for one page, or nothing when the lists say nothing about
    /// the site it is on.
    static func watch(for host: String?) -> WKUserScript? {
        guard let loaded, let runtime, let host,
              let source = source(loaded, runtime, host)
        else { return nil }
        return WKUserScript(source: source,
                            injectionTime: .atDocumentStart,
                            forMainFrameOnly: false,
                            in: .page)
    }

    // MARK: - what is shipped

    private static let loaded: Rules? = {
        guard let folder = Bundle.main.url(forResource: "Shield", withExtension: nil),
              let packed = try? Data(contentsOf: folder.appendingPathComponent("scriptlets.json.z")),
              let json = Shield.unpack(packed)
        else { return nil }
        return parse(json)
    }()

    private static let runtime: String? = {
        guard let folder = Bundle.main.url(forResource: "Shield", withExtension: nil) else { return nil }
        return try? String(contentsOf: folder.appendingPathComponent("scriptlets.js"), encoding: .utf8)
    }()

    // MARK: - the rules a page is given

    nonisolated static func parse(_ json: String) -> Rules? {
        guard let data = json.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        var texts: [String] = []
        var names: [[Site]] = []
        for entry in entries {
            let sites = entry["sites"] as? [String] ?? []
            guard entry["js"] is [Any],
                  let kept = try? JSONSerialization.data(withJSONObject: entry,
                                                         options: [.sortedKeys]),
                  let text = String(data: kept, encoding: .utf8)
            else { continue }
            texts.append(text)
            names.append(sites.compactMap(Site.init(pattern:)))
        }
        return Rules(texts: texts, names: names)
    }

    nonisolated static func source(_ rules: Rules, _ runtime: String, _ host: String) -> String? {
        let kept = zip(rules.texts, rules.names)
            .filter { applies($0.1, host) }
            .map(\.0)
        guard !kept.isEmpty else { return nil }
        return "window.__auraScriptlets=[\(kept.joined(separator: ","))];\n\(runtime)"
    }

    nonisolated private static func applies(_ sites: [Site], _ host: String) -> Bool {
        if sites.isEmpty { return true }
        var named = false
        var refused = false
        for site in sites {
            switch site {
            case .named(let pattern):
                if under(host, pattern) { named = true }
            case .refused(let pattern):
                if under(host, pattern) { refused = true }
            case .wildcard(let expression):
                if matches(expression, host) { named = true }
            case .refusedWildcard(let expression):
                if matches(expression, host) { refused = true }
            }
        }
        return named && !refused
    }

    nonisolated private static func under(_ host: String, _ pattern: String) -> Bool {
        host == pattern || host.hasSuffix("." + pattern)
    }

    nonisolated private static func matches(_ expression: NSRegularExpression, _ host: String) -> Bool {
        expression.firstMatch(in: host, range: NSRange(host.startIndex..., in: host)) != nil
    }
}

extension Scriptlets.Site {
    /// A site as a list writes it. `*` is the part of a host the list did not
    /// know — `ticketmaster.*` is every Ticketmaster — and a leading `~` is a
    /// site the rule is not for.
    init?(pattern: String) {
        guard !pattern.isEmpty else { return nil }
        let refused = pattern.hasPrefix("~")
        let body = refused ? String(pattern.dropFirst()) : pattern
        guard !body.isEmpty else { return nil }
        guard body.contains("*") else {
            self = refused ? .refused(body.lowercased()) : .named(body.lowercased())
            return
        }
        // A list's `*` is the rest of one host: anchored where a host starts,
        // and ending where it ends.
        let expression = body
            .split(separator: "*", omittingEmptySubsequences: false)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: ".*")
        guard let compiled = try? NSRegularExpression(pattern: "^(.*\\.)?\(expression)$") else {
            return nil
        }
        self = refused ? .refusedWildcard(compiled) : .wildcard(compiled)
    }
}
