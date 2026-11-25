import Foundation
@testable import SkillsBarCore
import XCTest

final class CommandJSONTests: XCTestCase {
    private func parse(_ text: String) -> JSONNode? {
        CommandResult(exitCode: 0, stdout: text, stderr: "").json
    }

    func testCompleteJSONAndNoisyOutput() {
        XCTAssertEqual(parse("{\"answer\":42}")?.int(at: ["answer"]), 42)
        XCTAssertNotNil(parse("[1,2,3]"))
        XCTAssertEqual(parse("warning\n{\"nested\":{\"answer\":42}}\ndone")?.int(at: ["nested", "answer"]), 42)
        XCTAssertEqual(parse("{invalid}\n{\"answer\":42}")?.int(at: ["answer"]), 42)
    }

    func testFallbackRespectsStringsAndDoesNotPromoteNestedFragments() {
        XCTAssertNil(parse(#"log "{}" trailing"#))
        XCTAssertNil(parse(#"log {invalid: {"answer":42}} trailing"#))
        XCTAssertEqual(parse(#"log {"text":"brace } and quote \" and slash \\","answer":42}"#)?.int(at: ["answer"]), 42)
    }

    func testUnfinishedLogQuotesDoNotHideLaterJSON() {
        let warningPrefix = "warning \"unfinished "
        let receipt = "{\"status\":42}"
        XCTAssertEqual(parse(#"warning "unfinished {"partial":1, {"status":42}"#)?.int(at: ["status"]), 42)
        XCTAssertEqual(parse(warningPrefix + receipt)?.int(at: ["status"]), 42)
        XCTAssertEqual(parse(warningPrefix + receipt + " trailing")?.int(at: ["status"]), 42)
        XCTAssertEqual(parse(#"warning "path {missing" {"status":"success"}"#)?.string(at: ["status"]), "success")
        XCTAssertEqual(parse("warning \"unfinished {\"broken\":42\n{\"status\":\"success\"}")?.string(at: ["status"]), "success")

        for separator in ["\n", "\r\n", "\r"] {
            for suffix in ["", "\\"] {
                let output = "warning \"unfinished" + suffix + separator + "{\"status\":\"success\"}"
                XCTAssertEqual(parse(output)?.string(at: ["status"]), "success")
            }
        }
        XCTAssertNil(parse("log {\"text\":\"unfinished\n{\"status\":\"success\"}"))
    }

    func testUnfinishedLogQuoteDoesNotPromoteNestedMalformedObject() {
        let output = "warning \"unfinished {broken: {\"status\":\"success\"}}"
        XCTAssertNil(parse(output))
        XCTAssertNil(parse(#"warning "unfinished {"items":[{"status":42}"#))
    }

    func testUnfinishedLogQuoteWithBraceHeavyOutputDoesNotRescanEveryBrace() {
        let output = "warning \"unfinished " + String(repeating: "{", count: 10_000)
        XCTAssertNil(parse(output))
    }

    func testQuotedBalancedObjectsAreScannedOnceBeforeTheLogQuoteCloses() {
        let fragments = String(repeating: #"{"fragment":1} "#, count: 3_000)
        XCTAssertNil(parse("warning \"unfinished " + fragments + "\""))
    }
}
