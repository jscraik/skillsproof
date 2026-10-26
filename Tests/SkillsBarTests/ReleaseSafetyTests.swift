import Foundation
import XCTest
@testable import SkillsBar

final class ReleaseSafetyTests: XCTestCase {
    func testFixtureCommandsUseExplicitSourceCheckout() {
        let source = URL(fileURLWithPath: "/tmp/portable-source-checkout")
        let root = DashboardLoader.resolvedDefaultRepoRoot(environment: ["AGENT_SKILLS_ROOT": source.path])
        XCTAssertEqual(root, source)
        XCTAssertTrue(DashboardLoader.localEvidenceCommand(root: root).hasPrefix("cd '\(source.path)' && "))
    }

    func testInstalledDiscoveryUsesProvidedHomeWithoutSDKCheckout() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let skill = home.appendingPathComponent(".codex/skills/portable/SKILL.md")
        try FileManager.default.createDirectory(at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "---\nname: portable\ndescription: Portable installed skill.\n---\n".write(to: skill, atomically: true, encoding: .utf8)
        let dashboard = try DashboardLoader(environment: [:], homeDirectory: home, storedSkillPath: nil,
            installedRegistryLookup: { _, _ in SkillDashboard.placeholder.tessl }).loadSync()
        XCTAssertEqual(dashboard.fleet.selectedSkillPath, skill.path)
        XCTAssertEqual(dashboard.displayName, "portable")
    }

    func testFixtureSwitchesRespectBuildConfiguration() {
        let environment = ["SKILLSBAR_DEMO_MODE": "1", "SKILLSBAR_REVIEW_FIXTURE": "live"]
        #if DEBUG
        XCTAssertTrue(DashboardDataSource(environment: environment).usesReviewFixture)
        #else
        XCTAssertFalse(DashboardDataSource(environment: environment).usesReviewFixture)
        XCTAssertFalse(SkillsBarDemoMode.isEnabled(in: environment))
        #endif
    }

    func testTesslFixtureCannotClaimLiveProvenance() {
        let signal = DashboardLoader(environment: ["TESSL_REGISTRY_FIXTURE": "1", "TESSL_REGISTRY_FIXTURE_SCORE": "100"])
            .tesslFixtureSignal(registryPath: "example/skill")
        #if DEBUG
        XCTAssertEqual(signal?.dataOrigin, .fixture)
        XCTAssertEqual(signal?.registryScore, 100)
        #else
        XCTAssertNil(signal)
        #endif
    }
}
