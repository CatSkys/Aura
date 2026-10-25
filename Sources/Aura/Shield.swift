import Compression
import CryptoKit
import Foundation
import WebKit

// The ad blocker. It enforces the lists the blocking everyone compares to is
// made of — EasyList and EasyPrivacy — rather than a list of the domains that
// were obvious when this was written. The conversion is done at build time by
// Tools/filters.py, into the files in Resources/Shield; nothing is fetched at
// run time, so what this build holds is what this build enforces.
//
// A content rule list is enforced inside WebKit's networking, before a request
// is made and before a stylesheet is applied, so this costs nothing at run time
// in the way a JavaScript blocker does.
//
// The three files answer three different questions:
//
//   network   requests not to make — the adverts, the trackers, and the
//             exceptions that take a block back on the sites it broke
//   extra     the same for rules that needed a regular expression, and the
//             ones that take a whole page away instead of an advert
//   cosmetic  what to hide — a stylesheet applied before the first frame, so
//             the empty box where an advert was never shows
//
// Each file is shipped squeezed (see Tools/filters.py): every rule repeats the
// same keys and the same kinds of request, so twenty-four megabytes of JSON
// read as one and a bit. It is unpacked here before WebKit compiles it.
//
// Which of them a site gets is the site's level. Off is off. Requests is the
// blocking alone, for a site whose layout the hiding broke. Everything is all
// three, which is what a site gets unless somebody said otherwise.

@MainActor
final class Shield: ObservableObject {
    static let shared = Shield()

    /// How much of the blocker one site gets. A checkout that never finishes,
    /// a video that never starts: stepping down here, for this site, beats
    /// turning the blocker off everywhere and forgetting to turn it back.
    enum Level: Int, CaseIterable, Hashable {
        case off
        case requests
        case everything

        var title: String {
            switch self {
            case .off: return "Off"
            case .requests: return "Requests"
            case .everything: return "Everything"
            }
        }
    }

    /// One file of rules. Which files a page is given is the page's level.
    enum Part: String, CaseIterable {
        case network
        case extra
        case cosmetic
    }

    /// Set the one time the list didn't compile. The toggle in Settings can
    /// say "on" all it wants; nothing is actually blocked until this is nil,
    /// so it is the one thing worth telling a person about rather than failing
    /// the quiet way a missing ad is quiet.
    @Published private(set) var trouble: String?

    /// On unless somebody said otherwise. Every tab's controller is told when
    /// this changes, so it takes effect on the next request rather than the
    /// next launch.
    var enabled = true

    /// What each site was given. A site that is not here gets everything: the
    /// promise is that blocking is on, and nobody has said anything about a
    /// site they have not opened yet.
    @Published private(set) var levels: [String: Level] = [:]

    private var compiled: [Part: WKContentRuleList] = [:]
    private var waiting: [WKUserContentController] = []
    private var compiling = false
    private var left = 0

    init() {
        if let stored = Store.settings.dictionary(forKey: "shield.levels") as? [String: Int] {
            for (host, raw) in stored {
                if let level = Level(rawValue: raw) { levels[host] = level }
            }
        }
        // Before there were levels a site was either blocked or paused. A
        // paused site stays off rather than going back to everything.
        if let paused = Store.settings.stringArray(forKey: "shield.paused") {
            for host in paused where levels[host] == nil { levels[host] = .off }
            Store.settings.removeObject(forKey: "shield.paused")
            save()
        }
    }

    func level(on host: String?) -> Level {
        guard let host else { return .everything }
        return levels[host] ?? .everything
    }

    func set(_ level: Level, on host: String) {
        // Everything is what a site gets by not being mentioned, so it is not
        // mentioned: what is stored is the list of sites that are not as usual.
        levels[host] = level == .everything ? nil : level
        save()
    }

    private func save() {
        Store.settings.set(levels.mapValues { $0.rawValue }, forKey: "shield.levels")
    }

    // MARK: - compiling

    /// Where one part's rules are in the bundle, and the name they compile
    /// under. The name carries a hash of the file, so a new block list is a
    /// new compiled list and an unchanged one is found rather than built
    /// again: the first launch after an update pays for the reading, and no
    /// launch after that does.
    private func listing(_ part: Part) -> (identifier: String, json: String)? {
        guard let folder = Bundle.main.url(forResource: "Shield", withExtension: nil),
              let packed = try? Data(
                contentsOf: folder.appendingPathComponent("\(part.rawValue).json.z")),
              let json = Shield.unpack(packed)
        else { return nil }
        let hash = SHA256.hash(data: packed)
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(16)
        return ("aura-shield-\(part.rawValue)-\(hash)", json)
    }

    /// The rules as the bundle holds them: how big they were in four bytes,
    /// then the deflate stream it was squeezed into. WebKit is given the JSON
    /// this grows back into.
    nonisolated static func unpack(_ packed: Data) -> String? {
        guard packed.count > 4 else { return nil }
        let size = Int(packed[packed.startIndex]) << 24
            | Int(packed[packed.startIndex + 1]) << 16
            | Int(packed[packed.startIndex + 2]) << 8
            | Int(packed[packed.startIndex + 3])
        guard size > 0 else { return nil }
        var raw = [UInt8](repeating: 0, count: size)
        let written = packed.dropFirst(4).withUnsafeBytes { source -> Int in
            guard let start = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(
                &raw, size, start, source.count, nil, COMPRESSION_ZLIB)
        }
        guard written == size else { return nil }
        return String(decoding: raw, as: UTF8.self)
    }

    func compile() {
        guard compiled.isEmpty, !compiling else { return }
        trouble = nil
        guard let store = WKContentRuleListStore.default() else {
            trouble = "WebKit has nowhere to compile it"
            return
        }
        let parts = Part.allCases.compactMap { part in listing(part).map { (part, $0) } }
        // The blocking is the network rules: without them there is nothing to
        // say that is worth saying.
        guard parts.contains(where: { $0.0 == .network }) else {
            trouble = "The block list didn't come with this build"
            return
        }
        compiling = true
        left = parts.count
        for (part, listing) in parts {
            start(store, part: part, listing: listing, required: part == .network)
        }
    }

    private func start(_ store: WKContentRuleListStore, part: Part,
                       listing: (identifier: String, json: String), required: Bool) {
        store.lookUpContentRuleList(forIdentifier: listing.identifier) { [weak self] cached, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let cached {
                    self.took(part, cached)
                    return
                }
                store.compileContentRuleList(
                    forIdentifier: listing.identifier,
                    encodedContentRuleList: listing.json
                ) { [weak self] made, error in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if let made {
                            self.took(part, made)
                        } else {
                            if required {
                                self.trouble = error?.localizedDescription
                                    ?? "Compiling the block list failed"
                            }
                            self.took(part, nil)
                        }
                    }
                }
            }
        }
    }

    private func took(_ part: Part, _ list: WKContentRuleList?) {
        if let list { compiled[part] = list }
        left -= 1
        guard left == 0 else { return }
        compiling = false
        // Tabs that opened while this was still compiling get it now, and the
        // navigation after this one will say what their site's level is.
        for controller in waiting { attach(controller, level: .everything) }
        waiting.removeAll()
    }

    // MARK: - handing it to a page

    /// Every tab asks for it; whoever asks before it is ready is remembered.
    func protect(_ controller: WKUserContentController) {
        guard trouble == nil else { return }
        if compiled.isEmpty {
            waiting.append(controller)
        } else {
            attach(controller, level: .everything)
        }
    }

    /// Before each page: the lists go on or off for the site this tab is
    /// heading to. A rule list is enforced from the moment it is added, so
    /// doing this at the navigation is what makes a site's level true for the
    /// whole page rather than for the second half of it.
    func tune(_ controller: WKUserContentController, for host: String?) {
        attach(controller, level: level(on: host))
    }

    /// Switched on or off for every page that is already open.
    func apply(to controllers: [(controller: WKUserContentController, host: String?)]) {
        for entry in controllers {
            attach(entry.controller, level: level(on: entry.host))
        }
    }

    private func attach(_ controller: WKUserContentController, level: Level) {
        for list in compiled.values { controller.remove(list) }
        guard enabled, level != .off else { return }
        if let list = compiled[.network] { controller.add(list) }
        guard level == .everything else { return }
        if let list = compiled[.extra] { controller.add(list) }
        if let list = compiled[.cosmetic] { controller.add(list) }
    }
}
