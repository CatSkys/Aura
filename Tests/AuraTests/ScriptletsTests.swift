import JavaScriptCore
import XCTest
@testable import Aura

/// The scripts a list asks a page to run, run.
///
/// A scriptlet is only worth shipping if it does what its name says, and the
/// page it is written for is exactly what a unit test cannot have. So the
/// runtime is run in a JavaScriptCore context with just enough of a page
/// around it — a host, a document, two storages — and each scriptlet is asked
/// for its one effect.
final class ScriptletsTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/Shield")

    /// The rules the lists asked for, as the browser reads them.
    private func shipped() throws -> String {
        let packed = try Data(contentsOf: Self.root.appendingPathComponent("scriptlets.json.z"))
        return try XCTUnwrap(Shield.unpack(packed))
    }

    /// A page is given the rules that name it: a few, not five thousand.
    func testAPageIsGivenTheRulesThatNameIt() throws {
        let rules = try XCTUnwrap(Scriptlets.parse(shipped()))
        let runtime = "/* the runtime */"
        let page = try XCTUnwrap(Scriptlets.source(rules, runtime, "usatoday.com"),
                                 "usatoday.com is checked by Admiral and has rules")
        // Five thousand rules name twenty thousand sites; a page is given the
        // few that name it, not the file.
        XCTAssertLessThan(page.count, try shipped().count / 20)
        XCTAssertTrue(page.hasSuffix(runtime))
        XCTAssertNil(Scriptlets.source(rules, runtime, "example.invalid"))

        // A list's `*` is the end of a host it did not know.
        let tickets = try XCTUnwrap(Scriptlets.source(rules, runtime, "ticketmaster.co.uk"))
        XCTAssertTrue(tickets.contains("globalPrivacyControl"))
    }

    /// A page to run in: the host it is on, and nothing of a real browser.
    private func page(host: String, rules: String, setup: String = "") throws -> JSContext {
        let runtime = try String(
            contentsOf: Self.root.appendingPathComponent("scriptlets.js"), encoding: .utf8)
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        var window = this;
        var location = { hostname: \(quoted(host)), pathname: '/' };
        var document = {
            currentScript: null,
            cookie: '',
            addEventListener: function () {},
            querySelectorAll: function () { return []; },
            createElement: function () { return {}; },
        };
        var boxes = { local: {}, session: {} };
        function storage(box) {
            return {
                getItem: function (key) { return Object.prototype.hasOwnProperty.call(box, key) ? box[key] : null; },
                setItem: function (key, value) { box[key] = String(value); },
                removeItem: function (key) { delete box[key]; },
            };
        }
        var localStorage = storage(boxes.local);
        var sessionStorage = storage(boxes.session);
        function EventTarget() {}
        EventTarget.prototype.addEventListener = function (kind, listener) {
            (this.added || (this.added = [])).push(kind + ':' + String(listener));
        };
        """)
        context.evaluateScript(setup)
        // The way the browser hands them over: the list's rules, then the code.
        context.evaluateScript("window.__auraScriptlets = \(rules);\n\(runtime)")
        return context
    }

    private func quoted(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func rules(_ pairs: [(sites: [String], call: [String])]) throws -> String {
        let entries = pairs.map { pair -> [String: Any] in
            ["sites": pair.sites, "js": [pair.call.first ?? "", Array(pair.call.dropFirst())]]
        }
        let data = try JSONSerialization.data(withJSONObject: entries)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    func testSetConstantAnswersTheCheckTheWayTheSiteWants() throws {
        let context = try page(
            host: "news.example.com",
            rules: try rules([(["example.com"], ["set-constant", "navigator.globalPrivacyControl", "false"])]))
        let value = try XCTUnwrap(context.evaluateScript("navigator.globalPrivacyControl"))
        XCTAssertTrue(value.isBoolean)
        XCTAssertFalse(value.toBool())
    }

    func testAScriptNamedForOneSiteStaysOffAnother() throws {
        let context = try page(
            host: "other.example.org",
            rules: try rules([(["example.com"], ["set-constant", "navigator.globalPrivacyControl", "false"])]))
        XCTAssertEqual(context.evaluateScript("typeof navigator.globalPrivacyControl")?.toString(),
                       "undefined")
    }

    /// The check still reads what it expects; only the script doing the
    /// checking is the one taken down, and only when it is that script.
    func testAbortCurrentScriptStopsTheScriptThatChecks() throws {
        let context = try page(
            host: "example.com",
            rules: try rules([(["example.com"], ["abort-current-script", "document.createElement", "admiral"])]))
        // The detector is the script running now: reading the property throws,
        // which takes the rest of that script with it.
        context.evaluateScript("document.currentScript = { textContent: 'admiral.init()', src: '' };")
        XCTAssertEqual(context.evaluateScript("try { document.createElement; 0 } catch (e) { 1 }")?.toInt32(), 1)
        // Anything else reads it as it always did.
        context.evaluateScript("document.currentScript = { textContent: 'var page = 1;', src: '' };")
        XCTAssertEqual(context.evaluateScript("typeof document.createElement")?.toString(), "function")
    }

    func testAListenerTheListNamesIsNeverAdded() throws {
        let context = try page(
            host: "example.com",
            rules: try rules([(["example.com"], ["addEventListener-defuser", "mouseup", "sendClickEvent"])]))
        context.evaluateScript("""
        var target = new EventTarget();
        target.addEventListener('mouseup', function sendClickEvent() {});
        target.addEventListener('mouseup', function ordinary() {});
        """)
        XCTAssertEqual(context.evaluateScript("target.added.length")?.toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("target.added[0]")?.toString().contains("ordinary"), true)
    }

    func testAStoredItemIsWrittenBeforeThePageLooksForIt() throws {
        let context = try page(
            host: "example.com",
            rules: try rules([(["example.com"], ["set-local-storage-item", "browser-ids", "true"])]))
        XCTAssertEqual(context.evaluateScript("localStorage.getItem('browser-ids')")?.toString(), "true")
    }

    /// Reading a property the list knows is what a detector does; the throw
    /// is inside the detector's own script, so the detector stops there.
    func testAPropertyThatThrowsWhenItIsRead() throws {
        let context = try page(
            host: "example.com",
            rules: try rules([(["example.com"], ["abort-on-property-read", "detector"])]))
        XCTAssertEqual(context.evaluateScript("try { detector.tag; 0 } catch (e) { 1 }")?.toInt32(), 1)
    }

    /// Written is the moment a page sets its own flag; the throw is there.
    func testAPropertyThatThrowsWhenItIsWritten() throws {
        let context = try page(
            host: "example.com",
            rules: try rules([(["example.com"], ["abort-on-property-write", "detector"])]))
        XCTAssertEqual(context.evaluateScript("try { detector.armed = 1; 0 } catch (e) { 1 }")?.toInt32(), 1)
    }

    /// The timer a detection waits on never gets armed, and the ones beside it
    /// do: it is the text the page would have run that says which.
    func testATimerTheListNamesIsNeverArmed() throws {
        let context = try page(
            host: "example.com",
            rules: try rules([(["example.com"], ["no-setTimeout-if", "adblock"])]),
            setup: """
            var timers = [];
            // WebKit's timers throw when the receiver is not the window, and
            // the patch that stands in for them has to keep that true.
            setTimeout = function (handler, delay) {
                if (this !== window) { throw new TypeError('Illegal invocation'); }
                timers.push(String(handler));
                return timers.length;
            };
            """)
        context.evaluateScript("""
        setTimeout(function () { adblockCheck(); }, 1000);
        setTimeout(function () { ordinaryWork(); }, 1000);
        """)
        XCTAssertEqual(context.evaluateScript("timers.length")?.toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("timers[0]")?.toString().contains("ordinaryWork"), true)
    }

    /// What the shipped file asks for has to be something the runtime has: a
    /// rule naming a scriptlet that is not here would be injected and do
    /// nothing at all, quietly, forever.
    func testTheShippedRulesOnlyAskForScriptsThatExist() throws {
        let entries = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(shipped().utf8)) as? [[String: Any]])
        XCTAssertFalse(entries.isEmpty)

        let runtime = try String(
            contentsOf: Self.root.appendingPathComponent("scriptlets.js"), encoding: .utf8)
        for entry in entries {
            let call = try XCTUnwrap(entry["js"] as? [Any], "no call")
            let name = try XCTUnwrap(call.first as? String, "no name")
            XCTAssertTrue(runtime.contains("scripts['\(name)'] = "), "no \(name) in the runtime")
            let sites = try XCTUnwrap(entry["sites"] as? [String], "no sites")
            for site in sites {
                XCTAssertEqual(site, site.lowercased(), site)
                XCTAssertFalse(site.isEmpty)
            }
        }
    }
}
