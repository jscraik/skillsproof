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
}
