import AppKit

// What a tool call is about to do, and whether the person has to say yes
// first.
//
// A page can put words in front of the model — its own text goes into the
// request (AIPage fences it, and says what it is, and neither is a guarantee).
// Once the model can act, those words can become a click. So every call that
// changes something is classified before it runs, and the four classes that
// can't be taken back are asked about:
//
//   · pay    — money leaves
//   · delete — something is destroyed
//   · submit — something is sent, posted, published, or signed
//   · grant  — something is allowed in, or handed over
//
// The classifier reads what a person reads: the element's accessible name, the
// words on the form around it, and the page's address. Its word lists are
// deliberately over-eager — a wrong pop-up costs one click, and a wrong
// purchase costs more than any number of clicks — so it will ask about a few
// things that turn out to be harmless, which is the direction to err in.
//
// What is remembered is the site and the class, never the button: "always for
// this site" on a Delete is about deleting on that site, which is the promise
// a person means to make. Never anything about a payment: that is asked every
// time, because a site that once had your permission for one purchase is not a
// site that has it for the next.

@MainActor
enum AIToolRisk {
    /// What a call can do.
    enum Kind: Equatable {
        /// Looking: it changes nothing.
        case reading
        /// Going somewhere: a page is loaded.
        case going
        /// Changing the page or the browser: clicks, typing, keys, tabs.
        case acting
    }

    /// What a person is being asked about, and what they may answer.
    enum Class: String, CaseIterable {
        case pay, delete, submit, grant

        var title: String {
            switch self {
            case .pay: return Localized("Spend money?")
            case .delete: return Localized("Delete something?")
            case .submit: return Localized("Send this?")
            case .grant: return Localized("Give access?")
            }
        }

        /// What the card says under the title: what this class means here.
        func detail(_ what: String, _ site: String) -> String {
            switch self {
            case .pay:
                return Localized("The assistant is about to press “\(what)” on \(site), which looks like it spends money. Nothing has been pressed yet.")
            case .delete:
                return Localized("The assistant is about to press “\(what)” on \(site), which looks like it deletes something. Nothing has been pressed yet.")
            case .submit:
                return Localized("The assistant is about to press “\(what)” on \(site), which sends something you can't take back. Nothing has been pressed yet.")
            case .grant:
                return Localized("The assistant is about to press “\(what)” on \(site), which gives something access. Nothing has been pressed yet.")
            }
        }

        /// Whether "always on this site" is a promise worth keeping for it. A
        /// payment never is.
        var remembers: Bool { self != .pay }
    }

    /// Whether a call may run.
    enum Verdict: Equatable {
        case allowed
        /// The person said no. The call does not happen, and the rest of its
        /// batch does not either; the turn still goes on, because they are
        /// owed an answer about what they said no to (see AIToolLoop).
        case refused(String)
    }

    // MARK: - the address

    /// An address that may be navigated to: http or https, and nothing else.
    /// A scheme like javascript:, file:, data: or blob: would let the model
    /// run code, read this Mac, or make a page out of nothing — none of them
    /// is a place to go.
    static func address(_ text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count < 4000,
              let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty, url.user == nil
        else { return nil }
        // A name with no dot is this Mac's own: there is nothing there to
        // reach, and the model wasn't asked to look inside the machine.
        guard host.contains(".") || host == "localhost" else { return nil }
        return url
    }

    // MARK: - the words

    /// The words that make a call one of the four.
    ///
    /// This is the one table in the app that says Chinese on purpose and is
    /// not translated: it is matched against a *page's* own button labels,
    /// not shown to anyone, so a Chinese site's "立即购买" has to be in here
    /// whatever language Aura is running in. It over-triggers by design —
    /// asking once too often costs a click, asking too rarely costs money.
    private static let words: [Class: [String]] = [
        .pay: ["pay", "payment", "buy", "purchase", "checkout", "check out", "order", "subscribe",
               "billing", "credit card", "donate", "top up", "add funds",
               "付款", "支付", "下单", "购买", "立即购买", "结算", "转账", "订阅", "充值", "打赏"],
        .delete: ["delete", "remove", "erase", "destroy", "unsubscribe", "cancel subscription",
                  "deactivate", "close account", "trash", "clear all",
                  "删除", "删掉", "移除", "清空", "注销", "解绑", "取消订阅", "销毁"],
        .submit: ["submit", "send", "publish", "post", "share", "confirm", "save", "apply", "register",
                  "sign up", "sign now", "agree", "accept", "continue", "place order",
                  "提交", "发送", "发布", "保存", "确认", "同意", "接受", "注册", "报名", "申请", "留言"],
        .grant: ["authorize", "authorise", "allow", "grant", "permit", "consent", "connect account",
                 "link account", "give access", "install",
                 "授权", "允许", "同意授权", "绑定账号", "添加账号", "开通"],
    ]

    /// The paths that make whatever is on them a grant: an OAuth screen's
    /// "Allow" is a grant whatever it says.
    private static let grantPaths = ["/oauth", "/authorize", "/authorise", "/consent", "/grant", "/signin-oauth"]

    /// What class a click on this element is, if any. Read from its name, the
    /// form it sits in, and the page's address.
    static func classify(name: String, form: String, address: URL?) -> Class? {
        let said = (name + " " + form).lowercased()
        let path = (address?.path ?? "").lowercased()
        // The address comes first: a permission screen asks for permission
        // whatever its button is called.
        if grantPaths.contains(where: { path.contains($0) }) { return .grant }
        // A word with un- in front of it means the opposite, and subscribing
        // is the one place a payment's own word would be found inside a
        // button that takes a payment away rather than making one.
        if said.contains("unsubscribe") { return .delete }
        // Then the order the classes are in: a button called "Buy and send
        // as a gift" is a payment, and being asked about paying is the safer
        // of the two questions.
        for kind in Class.allCases {
            guard let list = words[kind] else { continue }
            if list.contains(where: { said.contains($0) }) { return kind }
        }
        return nil
    }

    // MARK: - remembering

    /// The site a permission is remembered for: its host, and no more.
    private static func site(_ address: URL?) -> String {
        guard let host = address?.host()?.lowercased() else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func key(_ kind: Class, _ site: String) -> String { "ai.tools.allow.\(kind.rawValue).\(site)" }

    static func allowed(_ kind: Class, on address: URL?) -> Bool {
        let site = site(address)
        guard !site.isEmpty, kind.remembers else { return false }
        return Store.settings.bool(forKey: key(kind, site))
    }

    static func allow(_ kind: Class, on address: URL?) {
        let site = site(address)
        guard !site.isEmpty, kind.remembers else { return }
        Store.settings.set(true, forKey: key(kind, site))
    }

    /// Every promise of this kind, forgotten: Settings › AI's one line.
    static func forgetAll() {
        for kind in Class.allCases {
            for key in Store.settings.dictionaryRepresentation().keys where key.hasPrefix("ai.tools.allow.\(kind.rawValue).") {
                Store.settings.removeObject(forKey: key)
            }
        }
    }

    /// How many sites are remembered, for that line to say.
    static var remembered: Int {
        Store.settings.dictionaryRepresentation().keys.filter { $0.hasPrefix("ai.tools.allow.") }.count
    }

    // MARK: - the check

    /// Whether this call may happen, asking first when it can't be taken back.
    static func weigh(tool: AITool.Definition, arguments: AIToolArguments,
                      in browser: Browser, tab: Tab) async -> Verdict {
        guard tool.risk == .acting else { return .allowed }
        // A tab closed is a tab you have to find again: asked about, and as
        // the class that destroys something.
        if tool.name == "tabs", arguments.string("action") == "close" {
            let id = arguments.string("id") ?? ""
            let named = browser.tabs.first { Short.matches($0, id) }?.title ?? Localized("this tab")
            return await ask(.delete, named, tab, browser)
        }
        // The element, when the call names one: its name is what a person
        // reads before pressing it, and the words around it are what the
        // classifier reads when the name alone is vague.
        var name = ""
        var form = ""
        if let ref = arguments.string("ref"), let element = await AIToolSnap.element(ref, in: tab) {
            name = element.name.isEmpty ? element.role : element.name
            form = await AIToolSnap.formText(of: element, in: tab)
        }
        // Enter in a field with no form around it sends what is in the field:
        // a chat box and a comment box are both like that.
        if tool.name == "press", (arguments.string("key") ?? "").lowercased() == "enter", form.isEmpty, !name.isEmpty {
            return await ask(.submit, name, tab, browser)
        }
        if tool.name == "set_value", arguments.bool("submit") {
            return await ask(.submit, name.isEmpty ? Localized("this field") : name, tab, browser)
        }
        guard let kind = classify(name: name, form: form, address: tab.pageAddress) else { return .allowed }
        return await ask(kind, name.isEmpty ? Localized("this") : name, tab, browser)
    }

    private static func ask(_ kind: Class, _ what: String, _ tab: Tab, _ browser: Browser) async -> Verdict {
        if allowed(kind, on: tab.pageAddress) { return .allowed }
        let site = tab.pageAddress?.host() ?? ""
        guard let asking = browser.chat?.asking else {
            return .refused(Localized("Nothing was done: this conversation is closed."))
        }
        let answer = await asking.confirm(kind: kind, what: what, site: site)
        switch answer {
        case .allow:
            return .allowed
        case .always:
            allow(kind, on: tab.pageAddress)
            return .allowed
        case .refuse:
            return .refused(Localized("The person said no to “\(what)”. Nothing was pressed. Don't try it again unless they ask you to."))
        }
    }
}
