import XCTest
@testable import Aura

/// Which presses ask first, and which addresses may be navigated to. The
/// classifier is deliberately eager — a false alarm costs a click, a miss
/// costs money — so these tests are written to hold that bias rather than to
/// pin the exact word list.
@MainActor
final class AIToolRiskTests: XCTestCase {
    private func kind(_ name: String, form: String = "", at address: String? = nil) -> AIToolRisk.Class? {
        AIToolRisk.classify(name: name, form: form, address: address.flatMap(URL.init(string:)))
    }

    func testMoneyIsAskedAbout() {
        XCTAssertEqual(kind("Pay $40"), .pay)
        XCTAssertEqual(kind("Buy now"), .pay)
        XCTAssertEqual(kind("Place your order"), .pay)
        XCTAssertEqual(kind("Subscribe"), .pay)
        XCTAssertEqual(kind("立即购买"), .pay)
        XCTAssertEqual(kind("确认支付"), .pay)
        // A payment page's own words carry it even when the button doesn't.
        XCTAssertEqual(kind("Continue", form: "Order summary — total $12.00"), .pay)
    }

    func testDeletingIsAskedAbout() {
        XCTAssertEqual(kind("Delete"), .delete)
        XCTAssertEqual(kind("Delete account"), .delete)
        XCTAssertEqual(kind("Remove from library"), .delete)
        XCTAssertEqual(kind("Unsubscribe"), .delete)
        XCTAssertEqual(kind("删除"), .delete)
        XCTAssertEqual(kind("清空历史记录"), .delete)
    }

    func testSendingIsAskedAbout() {
        XCTAssertEqual(kind("Send"), .submit)
        XCTAssertEqual(kind("Publish"), .submit)
        XCTAssertEqual(kind("Post comment"), .submit)
        XCTAssertEqual(kind("Sign up"), .submit)
        XCTAssertEqual(kind("提交"), .submit)
        XCTAssertEqual(kind("发送"), .submit)
    }

    func testANewButtonLandsInSomeClassAndTheOrderPrefersMoney() {
        // A button that reads as two things at once: being asked about paying
        // is the safer of the two questions.
        XCTAssertEqual(kind("Buy and share"), .pay)
        XCTAssertEqual(kind("Delete and confirm"), .delete)
    }

    func testAnOAuthScreenIsAGrantWhateverItsButtonSays() {
        XCTAssertEqual(kind("Continue", at: "https://accounts.example.com/oauth/authorize?client=x"), .grant)
        XCTAssertEqual(kind("Continue", at: "https://example.com/consent"), .grant)
    }

    func testOrdinaryPressesAskNothing() {
        for name in ["Search", "Next page", "Read more", "Show comments", "Sign in", "Log in",
                     "Add to cart again", "Back to results", "Play"] {
            XCTAssertNil(kind(name), name)
        }
        XCTAssertNil(kind("Search", form: "q", at: "https://search.example.com/"))
    }

    func testOnlyHttpAndHttpsMayBeNavigatedTo() {
        for text in ["https://example.com/a", "http://example.com", "https://localhost:8080/x"] {
            XCTAssertNotNil(AIToolRisk.address(text), text)
        }
        for text in ["javascript:alert(1)", "file:///etc/passwd", "data:text/html,<b>x</b>",
                     "blob:https://example.com/x", "about:blank", "chrome://settings",
                     "https://user:secret@example.com/", "https://intranet/", "", "example.com",
                     "//example.com/", "mailto:a@example.com"] {
            XCTAssertNil(AIToolRisk.address(text), text)
        }
    }

    func testAPaymentIsNeverRemembered() {
        // "Always on this site" for a payment would be a promise nobody means.
        XCTAssertFalse(AIToolRisk.Class.pay.remembers)
        for kind in [AIToolRisk.Class.delete, .submit, .grant] {
            XCTAssertTrue(kind.remembers)
        }
    }

    func testARememberedSiteIsForgottenAgain() throws {
        let address = try XCTUnwrap(URL(string: "https://remember.example.com/checkout"))
        AIToolRisk.forgetAll()
        XCTAssertFalse(AIToolRisk.allowed(.pay, on: address))
        AIToolRisk.allow(.pay, on: address)
        // A payment is asked every time, whatever was remembered.
        XCTAssertFalse(AIToolRisk.allowed(.pay, on: address))
        AIToolRisk.allow(.submit, on: address)
        XCTAssertTrue(AIToolRisk.allowed(.submit, on: address))
        // www is the same site as no www.
        XCTAssertTrue(AIToolRisk.allowed(.submit, on: URL(string: "https://www.remember.example.com/")))
        XCTAssertFalse(AIToolRisk.allowed(.submit, on: URL(string: "https://other.example.com/")))
        XCTAssertGreaterThan(AIToolRisk.remembered, 0)
        AIToolRisk.forgetAll()
        XCTAssertEqual(AIToolRisk.remembered, 0)
    }

    func testEveryToolThatChangesSomethingIsWeighed() {
        // Reading and going are never asked about; everything that presses
        // something is.
        for tool in AITool.all {
            switch tool.risk {
            case .reading, .going:
                XCTAssertFalse(["click", "set_value", "press", "scroll"].contains(tool.name), tool.name)
            case .acting:
                XCTAssertTrue(["click", "set_value", "press", "scroll", "tabs"].contains(tool.name), tool.name)
            }
        }
    }
}
