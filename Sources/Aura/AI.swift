import Foundation
import Security

// The AI add-on: a summary of the page you're on, and questions about it,
// answered where you choose — a model on this Mac, an app on this Mac that
// runs one (Ollama, LM Studio), or a provider you have an account or a key
// with. Off until you turn it on in Settings › AI; nothing is detected,
// downloaded or sent before that, and nothing afterwards until you ask.
//
// This file: where it runs, and the keys. The requests are AIClient's, the
// page's text AIPage's.

/// Whether the AI add-on is in this build at all. Held back from 1.0.5
/// (8 Oct 2026): with it off, none of it shows or runs — no Settings page, no
/// menu items or shortcuts, no line on the welcome or What's New cards — and
/// a setting left on by a test build reads as off. The code stays; this is
/// the one line that brings it back.
enum AI {
    /// Whether the add-on is in this build: `false` from 1.0.5, by the line
    /// that brings it back (this one).
    ///
    /// A test run may take the gate up for the length of that run alone
    /// (`bench ai ship on`), because a surface nobody can switch on is a
    /// surface no probe can drive — and editing this line to look at it is a
    /// change that has been left in a working tree before.
    static let shipped = true
}

/// Where the answers come from.
enum AIProvider: String, CaseIterable, Identifiable {
    /// The model downloaded to this Mac, run by Aura's own engine (AIEngine).
    case thisMac
    case anthropic, openAI, gemini, openRouter
    /// Ollama, on this Mac.
    case ollama
    /// LM Studio, on this Mac.
    case lmStudio
    /// An API of your own (Settings › AI › Custom): a root address, one of
    /// the two ways of writing a request, a model's name and, unless it runs
    /// on this Mac, a key. Everything the providers above are is worked out
    /// from those four, so an OpenAI-compatible server — vLLM, llama.cpp's
    /// own, a gateway in front of several — is this case and nothing else.
    case custom

    var id: String { rawValue }

    var name: String {
        switch self {
        case .thisMac: return "On this Mac"
        case .anthropic: return "Anthropic"
        case .openAI: return "OpenAI"
        case .gemini: return "Google Gemini"
        case .openRouter: return "OpenRouter"
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        case .custom:
            let named = AIProvider.customName.trimmingCharacters(in: .whitespacesAndNewlines)
            return named.isEmpty ? "Custom" : named
        }
    }

    /// Runs on this Mac: nothing leaves it, and no key is needed. Your own
    /// API counts as here when its address is this Mac's.
    var isLocal: Bool {
        switch self {
        case .thisMac, .ollama, .lmStudio: return true
        case .custom:
            let host = base.host()?.lowercased() ?? ""
            return host == "127.0.0.1" || host == "::1" || host == "localhost"
        default: return false
        }
    }

    /// Your own model's API, as typed in Settings › AI: the root a request is
    /// added to, the name it goes by, and how requests are written. Read from
    /// the settings rather than kept on the case, so a change there is a
    /// change everywhere — a conversation opened before it included.
    static var customAddress: String {
        (Store.settings.string(forKey: "ai.custom.address") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static var customName: String { Store.settings.string(forKey: "ai.custom.name") ?? "" }

    /// The one address requests go to. A key is kept for this host and is
    /// never sent to any other (see AIClient.request).
    var base: URL {
        if Store.testing, let mock = AIProvider.mock { return mock.appendingPathComponent(rawValue + "/") }
        switch self {
        // Never asked over the network: the engine is a program of its own.
        case .thisMac: return URL(string: "http://127.0.0.1:1/")!
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/")!
        case .openAI: return URL(string: "https://api.openai.com/v1/")!
        case .gemini: return URL(string: "https://generativelanguage.googleapis.com/v1beta/")!
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/")!
        case .ollama: return URL(string: "http://127.0.0.1:11434/v1/")!
        case .lmStudio: return URL(string: "http://127.0.0.1:1234/v1/")!
        // Nothing until an address is given, and then exactly that: no
        // provider's host is guessed for it.
        case .custom: return URL(string: AIProvider.customAddress) ?? URL(string: "http://127.0.0.1:1/")!
        }
    }

    var host: String { self == .thisMac ? "this Mac" : base.host() ?? "" }

    /// A test run's stand-in for every provider: a server on this Mac that
    /// answers the way they do (bench ai-mock). Never outside a test run,
    /// and only ever on the loopback address.
    nonisolated(unsafe) static var mock: URL?

    /// Cheap and quick, for a summary; each can be changed in Settings.
    /// The local apps have no default: the list comes from the app.
    var defaultModel: String {
        switch self {
        case .thisMac: return AIEngine.model.name
        case .anthropic: return "claude-haiku-4-5"
        case .openAI: return "gpt-5.4-mini"
        case .gemini: return "gemini-3.8-flash"
        case .openRouter: return "google/gemini-3.8-flash"
        case .ollama, .lmStudio, .custom: return ""
        }
    }

    /// How requests are written.
    enum Wire { case openAI, anthropic, gemini }

    var wire: Wire {
        switch self {
        case .anthropic: return .anthropic
        case .gemini: return .gemini
        // The one choice your own model asks for: most APIs of one's own
        // speak OpenAI's, and Anthropic's is the other shape Aura writes.
        case .custom: return (Store.settings.string(forKey: "ai.custom.wire") ?? "openai") == "anthropic" ? .anthropic : .openAI
        default: return .openAI
        }
    }
}

/// The keys, in the keychain and nowhere else.
///
/// Two keychains, one answer. Aura prefers the data protection keychain, under
/// its own access group: only apps signed as Aura, with the provisioning
/// profile that names it, can read or write there, this Mac only, readable
/// while it is unlocked, never synced, and each key kept for its provider's
/// host (account "provider@host").
///
/// That keychain only exists where macOS knows which app is asking —
/// `com.apple.application-identifier` in the signature, which comes from that
/// profile. A copy built from source, or signed by hand, is refused there with
/// errSecMissingEntitlement, and used to be left unable to keep a key at all.
/// It keeps them in this Mac's login keychain instead: the same promises
/// except the app's own group, an item any other app has to be let in to read,
/// this Mac only and never synced. Which one it is, is asked once and
/// remembered, and written down in Settings rather than guessed at.
///
/// A key is read the moment a request needs it and let go with the request:
/// never in the settings file, a published value, a log line or an error.

@MainActor
enum AIKeys {
    enum Saved { case kept, unavailable, failed }

    /// Which keychain keeps them.
    enum Vault: String {
        /// The data protection keychain, under Aura's own access group: the
        /// one a signed release with its profile uses.
        case protected
        /// This Mac's login keychain: what a copy without that profile has,
        /// so that no copy of Aura is left unable to hold a key.
        case login

        var described: String {
            self == .protected ? Localized("this Mac's keychain") : Localized("this Mac's login keychain")
        }
    }

    private static let service = "com.catskys.aura.ai"
    /// A test run's, by account, gone when it quits.
    private static var rehearsal: [String: String] = [:]
    /// Asked once, on the first key.
    private static var probed: Vault?

    /// Where a key is kept by this copy of Aura.
    static var vault: Vault {
        if let probed { return probed }
        let picked: Vault = takesProtected() ? .protected : .login
        probed = picked
        return picked
    }

    /// Whether the data protection keychain takes an item here: one put and
    /// taken away again, which says more than a search does — a search in a
    /// copy with no access group answers "not found", not "not allowed".
    private static func takesProtected() -> Bool {
        if Store.testing { return false }
        var probe = query(.anthropic, in: .protected, withAccount: "probe")
        probe[kSecValueData as String] = Data("probe".utf8)
        let put = SecItemAdd(probe as CFDictionary, nil)
        if put == errSecDuplicateItem { return true }
        guard put == errSecSuccess else { return false }
        SecItemDelete(probe as CFDictionary)
        return true
    }

    private static func account(_ provider: AIProvider) -> String { "\(provider.rawValue)@\(provider.host)" }

    /// A key's place in one keychain, by account. `withAccount` is for the
    /// probe alone, which is about the keychain and not about a provider.
    private static func query(_ provider: AIProvider, in vault: Vault? = nil,
                              withAccount: String? = nil) -> [String: Any] {
        var asked: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: withAccount ?? account(provider)]
        if (vault ?? AIKeys.vault) == .protected { asked[kSecUseDataProtectionKeychain as String] = true }
        return asked
    }

    static func save(_ key: String, for provider: AIProvider) -> Saved {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !provider.isLocal else { return .failed }
        if Store.testing {
            rehearsal[account(provider)] = key
            return .kept
        }
        switch put(key, for: provider, in: vault) {
        case errSecSuccess: return .kept
        case errSecMissingEntitlement:
            // Chosen wrongly, or the profile under this copy changed under
            // it: the login keychain takes it, and the choice is not asked
            // again this run.
            probed = .login
            return put(key, for: provider, in: .login) == errSecSuccess ? .kept : .unavailable
        default: return .failed
        }
    }

    private static func put(_ key: String, for provider: AIProvider, in vault: Vault) -> OSStatus {
        SecItemDelete(query(provider, in: vault) as CFDictionary)
        var item = query(provider, in: vault)
        item[kSecValueData as String] = Data(key.utf8)
        // The data protection keychain can say how it is protected; the login
        // keychain is already what its name says, this Mac and nobody else's.
        if vault == .protected { item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly }
        item[kSecAttrSynchronizable as String] = false
        item[kSecAttrLabel as String] = "Aura — \(provider.name) key"
        // The last four, to tell keys apart in Settings without reading one.
        item[kSecAttrComment as String] = String(key.suffix(4))
        return SecItemAdd(item as CFDictionary, nil)
    }

    /// The key, for the request about to go out. Nil when there is none.
    static func key(for provider: AIProvider) -> String? {
        if Store.testing { return rehearsal[account(provider)] }
        var asked = query(provider)
        asked[kSecReturnData as String] = true
        asked[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(asked as CFDictionary, &found) == errSecSuccess,
              let data = found as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// "••••1a2b" for one that is kept, without reading the key itself.
    static func hint(for provider: AIProvider) -> String? {
        if Store.testing { return rehearsal[account(provider)].map { "••••" + $0.suffix(4) } }
        var asked = query(provider)
        asked[kSecReturnAttributes as String] = true
        var found: CFTypeRef?
        guard SecItemCopyMatching(asked as CFDictionary, &found) == errSecSuccess,
              let attributes = found as? [String: Any]
        else { return nil }
        return "••••" + (attributes[kSecAttrComment as String] as? String ?? "")
    }

    static func forget(_ provider: AIProvider) {
        if Store.testing { rehearsal[account(provider)] = nil; return }
        SecItemDelete(query(provider) as CFDictionary)
        // A key kept before this copy settled on a keychain is in the other
        // one: it goes too.
        SecItemDelete(query(provider, in: vault == .protected ? .login : .protected) as CFDictionary)
    }

    static func forgetAll() {
        AIProvider.allCases.forEach(forget)
    }

    /// What a probe asks: which keychain this copy has, and whether it really
    /// takes an item — put, read back, taken away again, under a name of its
    /// own so no real key is touched. A test run only, and it leaves nothing.
    static func selftest() -> [String: String] {
        var out = ["vault": vault.rawValue]
        var item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service + ".selftest",
                                   kSecAttrAccount as String: "probe"]
        if vault == .protected { item[kSecUseDataProtectionKeychain as String] = true }
        // The same three things a real key is given, so what this proves is
        // what a key goes through (see put).
        item[kSecAttrSynchronizable as String] = false
        item[kSecAttrLabel as String] = "Aura — probe"
        item[kSecAttrComment as String] = "robe"
        SecItemDelete(item as CFDictionary)
        var put = item
        put[kSecValueData as String] = Data("probe".utf8)
        out["add"] = "\(SecItemAdd(put as CFDictionary, nil))"
        var read = item
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        out["read"] = "\(SecItemCopyMatching(read as CFDictionary, &found))"
        if let data = found as? Data { out["value"] = String(data: data, encoding: .utf8) ?? "" }
        out["delete"] = "\(SecItemDelete(item as CFDictionary))"
        // The data protection keychain, tried whatever this copy settled on:
        // its answer is what a copy with no provisioning profile gets.
        if vault != .protected {
            var refused = item
            refused[kSecUseDataProtectionKeychain as String] = true
            refused[kSecValueData as String] = Data("probe".utf8)
            out["protected"] = "\(SecItemAdd(refused as CFDictionary, nil))"
            SecItemDelete(refused as CFDictionary)
        }
        return out
    }
}
