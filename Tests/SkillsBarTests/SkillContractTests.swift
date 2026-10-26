import Foundation
import XCTest

final class SkillContractTests: XCTestCase {
    func testSignedAppResourceLookupPrecedesTheSwiftPMFallback() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dashboardView = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/SkillsBar/Views/DashboardView.swift"),
            encoding: .utf8
        )
        let mainLookup = try XCTUnwrap(dashboardView.range(of: "Bundle.main.url(forResource:"))
        let moduleLookup = try XCTUnwrap(dashboardView.range(of: "AppResources.url(forResource:"))

        XCTAssertLessThan(mainLookup.lowerBound, moduleLookup.lowerBound)
    }

    deinit {}

    func testDefaultUIWorkRoutesToApprovedPipelinePostureContract() throws {
        let repoRoot = repositoryRoot
        let approvedSpec = try String(
            contentsOf: repoRoot.appendingPathComponent(
                ".harness/specs/2026-07-10-skillsbar-pipeline-posture-spec.md"
            ),
            encoding: .utf8
        )
        let historicalSpec = try String(
            contentsOf: repoRoot.appendingPathComponent(
                ".harness/specs/2026-07-09-skills-sdk-menubar-review-popover-spec.md"
            ),
            encoding: .utf8
        )
        let agents = try String(contentsOf: repoRoot.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        let readme = try String(contentsOf: repoRoot.appendingPathComponent("README.md"), encoding: .utf8)

        XCTAssertTrue(approvedSpec.contains("status: approved_documentation_contract"))
        XCTAssertTrue(approvedSpec.contains("visual_reference: .harness/media/2026-07-10-skillsbar-pipeline-posture-approved.png"))
        XCTAssertTrue(historicalSpec.contains("status: superseded_by_pipeline_posture_spec"))
        XCTAssertTrue(historicalSpec.contains("successor_spec: .harness/specs/2026-07-10-skillsbar-pipeline-posture-spec.md"))

        XCTAssertTrue(agents.contains(".harness/specs/2026-07-10-skillsbar-pipeline-posture-spec.md"))
        XCTAssertTrue(agents.contains("ReleaseEvidenceView"))
        XCTAssertTrue(agents.contains("The 2026-07-09 review-popover spec and its materials are historical reference only"))
        XCTAssertTrue(agents.contains("do not use them as the default implementation contract."))
        XCTAssertFalse(agents.contains("check `.harness/specs/2026-07-09-skills-sdk-menubar-review-popover-spec.md` and its referenced mockup before changing popover semantics."))
        XCTAssertTrue(readme.contains(".harness/specs/2026-07-10-skillsbar-pipeline-posture-spec.md"))
        XCTAssertTrue(readme.contains(".harness/media/2026-07-10-skillsbar-pipeline-posture-approved.png"))
        XCTAssertTrue(readme.contains("Superseded review-popover spec retained as historical/reference-only evidence."))
        XCTAssertTrue(readme.contains("historical/reference-only material for intentionally retained legacy context; they do not govern new pipeline-posture changes."))
        XCTAssertFalse(readme.contains("For the review popover, read the spec and current implementation-handoff mockup first"))
    }

    func testDashboardViewDoesNotRetainDeletedFocusAccent() throws {
        let dashboardView = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/SkillsBar/Views/DashboardView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(dashboardView.contains("focusAccent"))
    }

    func testRetiredReviewPresentationIsAbsentFromModelAndLegacyTests() throws {
        let model = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/SkillsBar/Models/DashboardModels.swift"),
            encoding: .utf8
        )
        let legacyTests = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Tests/SkillsBarTests/ReviewPopoverTests.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(model.contains("ReviewPresentation"))
        XCTAssertFalse(legacyTests.contains("ReviewPresentation"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
