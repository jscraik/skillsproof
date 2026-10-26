import AppKit
@testable import SkillsBar
import SkillsBarCore
import SwiftUI
import XCTest

final class ReviewPopoverTests: XCTestCase {
    @MainActor
    private final class TestPasteboard: PasteboardWriting {
        var string: String?
        var acceptsWrites = true

        func clearContents() -> Int {
            string = nil
            return 1
        }

        func setString(_ string: String, forType _: NSPasteboard.PasteboardType) -> Bool {
            guard acceptsWrites else { return false }
            self.string = string
            return true
        }
    }

    private let expectedCommand = "cd '\(DashboardLoader.defaultRepoRoot.path.replacingOccurrences(of: "'", with: "'\\''"))' && ./bin/ask sdk security risk-modes 'Skills/agent-ops/improve-agent-native/SKILL.md' --preview --json --robot"
    private let expectedIdentityCommand = "cd '\(DashboardLoader.defaultRepoRoot.path.replacingOccurrences(of: "'", with: "'\\''"))' && ./bin/ask sdk start 'Skills/agent-ops/improve-agent-native' --json --robot"

    func testReviewFixtureMatchesImplementationHandoffContract() {
        let dashboard = SkillDashboard.reviewFixture

        XCTAssertEqual(dashboard.verdictTitle, "Needs review")
        XCTAssertEqual(dashboard.verdictDetail, "3 risks need inspection")
        XCTAssertEqual(dashboard.description, "Live eval plugin for improve-agent-native.")
        XCTAssertEqual(dashboard.score, 78)
        XCTAssertEqual(dashboard.pipeline.postureScore, 0)
        XCTAssertEqual(dashboard.pipeline.evidencedStageCount, 1)
        XCTAssertEqual(dashboard.pipeline.activeReceipt?.stage, .candidateBaseline)
        XCTAssertEqual(dashboard.pipeline.activeReceipt?.nextAction, "Canonical package digest missing")
        XCTAssertEqual(dashboard.pipeline.activeReceipt?.command, expectedIdentityCommand)
        XCTAssertEqual(dashboard.quality.statusLabel, "100%")
        XCTAssertEqual(dashboard.impact.statusLabel, "71/71")
        XCTAssertEqual(dashboard.security.statusDisplay, "3 risks")
        XCTAssertEqual(dashboard.security.severityLine, "1 critical, 2 high")
        XCTAssertEqual(dashboard.tessl.registryScore, 66)
        XCTAssertEqual(dashboard.tessl.registryVersion, "0.2.0")
        XCTAssertEqual(dashboard.tessl.registryQualityScore, 100)
        XCTAssertEqual(dashboard.tessl.registryImpactScore, 63)
        XCTAssertEqual(dashboard.tessl.registrySecurityDisplay, "Passed")
        XCTAssertEqual(dashboard.tessl.registryEvalCount, 68)
        XCTAssertEqual(dashboard.tessl.registryImprovementMultiplier, 1.28)
        XCTAssertEqual(dashboard.tessl.registryVisibilityDisplay, "Private")
        XCTAssertEqual(dashboard.reviewInspectCommand, expectedCommand)
        var incompleteDashboard = SkillDashboard.reviewFixture
        incompleteDashboard.quality.score = nil
        incompleteDashboard.impact.score = nil
        XCTAssertNil(incompleteDashboard.score)
    }

    #if DEBUG
    func testReferenceFixtureIsVisualOnlyAndKeepsTheGateModelIntact() throws {
        let dashboard = SkillDashboard.visualReferenceFixture

        XCTAssertEqual(dashboard.pipeline.activeReceipt?.stage, .ossLocal)
        XCTAssertEqual(dashboard.pipeline.evidencedStageCount, 5)
        XCTAssertEqual(dashboard.pipeline.orderedReceipts.prefix(4).map(\.evidenceStatus), [.passed, .passed, .passed, .passed])
        XCTAssertEqual(dashboard.pipeline.orderedReceipts[4].evidenceStatus, .blocked)
        XCTAssertEqual(dashboard.tessl.registryVersion, "0.3.3")

        let source = DashboardDataSource(environment: ["SKILLSBAR_REVIEW_FIXTURE": "reference"])
        XCTAssertEqual(try source.loadSync().pipeline.activeReceipt?.stage, .ossLocal)
        XCTAssertEqual(SkillDashboard.reviewFixture.pipeline.activeReceipt?.stage, .candidateBaseline)
    }
    #endif

    func testPipelinePresentationMovesTheFocusedSectionWithLiveEvidence() {
        let presentation = PipelinePresentation(candidate: pipelineCandidate(activeStage: .securityReview))

        XCTAssertEqual(presentation.completedReceipts.map(\.stage), [.candidateBaseline, .mechanicalValidation])
        XCTAssertEqual(presentation.focusedReceipts.map(\.stage), [.securityReview, .evalPreparation])
        XCTAssertEqual(presentation.remainingLocalReceipts.map(\.stage), [.ossLocal, .ossCloud])
        XCTAssertEqual(
            presentation.remainingDeliveryReceipts.map(\.stage),
            [.tesslStaging, .tesslLiveRegistry, .liveScoreAndRuntime]
        )
    }

    func testPipelinePresentationPlacesGateFiveInTheReferenceLayoutWithoutHardcodingIt() {
        let presentation = PipelinePresentation(candidate: pipelineCandidate(activeStage: .ossLocal))

        XCTAssertEqual(
            presentation.completedReceipts.map(\.stage),
            [.candidateBaseline, .mechanicalValidation, .securityReview, .evalPreparation]
        )
        XCTAssertEqual(presentation.focusedReceipts.map(\.stage), [.ossLocal, .ossCloud])
        XCTAssertTrue(presentation.remainingLocalReceipts.isEmpty)
        XCTAssertEqual(
            presentation.remainingDeliveryReceipts.map(\.stage),
            [.tesslStaging, .tesslLiveRegistry, .liveScoreAndRuntime]
        )
    }

    func testPipelinePresentationPlacesEveryActiveGateInItsOwnFocusedSection() {
        for activeStage in PipelineStage.allCases {
            let presentation = PipelinePresentation(candidate: pipelineCandidate(activeStage: activeStage))
            let renderedStages = presentation.completedReceipts
                + presentation.focusedReceipts
                + presentation.remainingLocalReceipts
                + presentation.remainingDeliveryReceipts

            XCTAssertEqual(presentation.focusedReceipts.first?.stage, activeStage)
            XCTAssertEqual(renderedStages.map(\.stage), PipelineStage.allCases)
            XCTAssertTrue(presentation.completedReceipts.allSatisfy { $0.evidenceStatus == .passed })
        }
    }

    func testDataSourceUsesLivePipelineWhenTheVisualFixtureIsUnset() throws {
        var liveDashboard = SkillDashboard.reviewFixture
        liveDashboard.pipeline = pipelineCandidate(activeStage: .tesslStaging)
        let source = DashboardDataSource(
            environment: [:],
            liveLoad: { liveDashboard },
            liveLoadAsync: { liveDashboard }
        )

        XCTAssertEqual(try source.loadSync().pipeline.activeReceipt?.stage, .tesslStaging)
    }

    func testCommandDisclosureLabelNamesTheStageAndKeepsVisibleTextFirst() {
        for stage in PipelineStage.allCases {
            let collapsed = CommandDisclosureText(stageTitle: stage.title, isExpanded: false)
            XCTAssertEqual(collapsed.title, "Show command")
            XCTAssertEqual(collapsed.accessibilityLabel, "Show command, \(stage.title)")
            XCTAssertEqual(collapsed.accessibilityValue, "Collapsed")

            let expanded = CommandDisclosureText(stageTitle: stage.title, isExpanded: true)
            XCTAssertEqual(expanded.title, "Hide command")
            XCTAssertEqual(expanded.accessibilityLabel, "Hide command, \(stage.title)")
            XCTAssertEqual(expanded.accessibilityValue, "Expanded")
        }
    }

    func testDensePipelineActionLabelsKeepTheFullReasonAvailableSeparately() {
        guard let active = SkillDashboard.reviewFixture.pipeline.activeReceipt else {
            return XCTFail("The review fixture must expose an active pipeline receipt")
        }

        XCTAssertEqual(active.compactActionLabel, "Digest required")
        XCTAssertEqual(active.nextAction, "Canonical package digest missing")
    }

    func testRegistryVisibilityIsNormalizedAndCanBeAbsent() {
        var dashboard = SkillDashboard.reviewFixture
        dashboard.tessl.registryVisibility = "PUBLIC"
        XCTAssertEqual(dashboard.tessl.registryVisibilityDisplay, "Public")

        dashboard.tessl.registryVisibility = nil
        XCTAssertNil(dashboard.tessl.registryVisibilityDisplay)
    }

    func testRegistryMetricTonesFollowActualValues() {
        XCTAssertEqual(RegistryMetricPresentation.percentTone(nil), .pending)
        XCTAssertEqual(RegistryMetricPresentation.percentTone(100), .positive)
        XCTAssertEqual(RegistryMetricPresentation.percentTone(72), .warning)
        XCTAssertEqual(RegistryMetricPresentation.percentTone(35), .danger)
        XCTAssertEqual(SecurityDisposition(label: nil).tone, .pending)
        XCTAssertEqual(SecurityDisposition(label: "Passed").tone, .positive)
        XCTAssertEqual(SecurityDisposition(label: "Advisory").tone, .advisory)
        XCTAssertEqual(SecurityDisposition(label: "Advisory review").tone, .advisory)
        XCTAssertEqual(SecurityDisposition(label: "Flagged").tone, .warning)
        XCTAssertEqual(SecurityDisposition(label: "Failed").tone, .danger)

        var flaggedDashboard = SkillDashboard.reviewFixture
        flaggedDashboard.tessl.registrySecurityLabel = "Flagged"
        flaggedDashboard.tessl.registryScore = 35
        XCTAssertTrue(flaggedDashboard.tessl.evidenceRequiresReview)
    }

    func testSemanticVersionNormalizationHandlesUpperAndLowercasePrefixes() {
        XCTAssertEqual(normalizeSemanticVersion("v1.2.3"), "1.2.3")
        XCTAssertEqual(normalizeSemanticVersion("V1.2.3"), "1.2.3")
        XCTAssertEqual(normalizeSemanticVersion(" 1.2.3 "), "1.2.3")
    }

    func testSecurityDispositionUsesSeverityFirstPrecedence() {
        XCTAssertEqual(SecurityDisposition(label: nil), .pending)
        XCTAssertEqual(SecurityDisposition(label: "Passed"), .passed)
        XCTAssertEqual(SecurityDisposition(label: "Advisory"), .advisory)
        XCTAssertEqual(SecurityDisposition(label: "Flagged"), .flagged)
        XCTAssertEqual(SecurityDisposition(label: "Failed"), .failed)
        XCTAssertEqual(SecurityDisposition(label: "Not passed"), .failed)
        XCTAssertEqual(SecurityDisposition(label: "Critical advisory"), .failed)
        XCTAssertEqual(SecurityDisposition(label: "Flagged but passed baseline"), .flagged)
        XCTAssertEqual(SecurityDisposition(label: "Failed after advisory review"), .failed)
        var advisoryDashboard = SkillDashboard.reviewFixture
        advisoryDashboard.security = SecuritySignal(
            score: 70,
            status: "Advisory",
            detail: "Manual review advised.",
            sourceLabel: "Local SDK risk-modes",
            segmentCount: 2,
            inspectCommand: expectedCommand
        )
        XCTAssertEqual(advisoryDashboard.security.disposition, .advisory)
        XCTAssertEqual(advisoryDashboard.security.tone, .advisory)
    }

    func testRegistryVersionDoesNotFallBackToLocalSkillVersion() {
        var tessl = SkillDashboard.reviewFixture.tessl
        tessl.registryVersion = nil

        XCTAssertEqual(tessl.registryVersionDisplay, "version --")
    }

    func testSanitizedTesslPayloadMapsRegistryContract() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "tessl-private-skill", withExtension: "json"))
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let metadata = TesslRegistryMetadata(payload: JSONNode(object))

        XCTAssertEqual(metadata.score, 66)
        XCTAssertEqual(metadata.version, "0.2.0")
        XCTAssertEqual(metadata.qualityScore, 100)
        XCTAssertEqual(metadata.impactScore, 63)
        XCTAssertEqual(metadata.securityLabel, "Passed")
        XCTAssertEqual(metadata.evalCount, 68)
        XCTAssertEqual(metadata.visibility, "private")
    }

    func testSanitizedTesslPayloadSupportsPublicAndMissingVisibility() throws {
        let publicMetadata = try registryMetadata(fixture: "tessl-public-skill")
        let missingMetadata = try registryMetadata(fixture: "tessl-visibility-missing")

        XCTAssertEqual(publicMetadata.visibility, "public")
        XCTAssertNil(missingMetadata.visibility)
    }

    func testRegistryVisibilityDisplayNormalizesPluginMetadataForThePill() {
        var privateSignal = SkillDashboard.reviewFixture.tessl
        privateSignal.registryVisibility = "private"
        XCTAssertEqual(privateSignal.registryVisibilityDisplay, "Private")

        privateSignal.registryVisibility = "PUBLIC"
        XCTAssertEqual(privateSignal.registryVisibilityDisplay, "Public")
    }

    func testTesslMetadataPrefersCanonicalResultOverUnrelatedNestedKeys() throws {
        let metadata = try registryMetadata(fixture: "tessl-ambiguous-skill")

        XCTAssertEqual(metadata.version, "2.0.0")
        XCTAssertEqual(metadata.securityLabel, "Advisory")
        XCTAssertEqual(metadata.evalCount, 42)
        XCTAssertEqual(metadata.visibility, "public")
    }

    func testLiveTesslSearchSchemaUsesTheRequestedRegistryResult() throws {
        let metadata = try registryMetadata(
            fixture: "tessl-live-search-result",
            registryPath: "jscraik/improve-agent-native"
        )

        XCTAssertEqual(metadata.score, 67)
        XCTAssertEqual(metadata.version, "0.2.0")
        XCTAssertEqual(metadata.qualityScore, 100)
        XCTAssertEqual(metadata.impactScore, 63)
        XCTAssertEqual(metadata.securityLabel, "LOW")
        XCTAssertEqual(metadata.evalCount, 68)
        XCTAssertEqual(metadata.improvementMultiplier, 1.28)
        XCTAssertNil(metadata.visibility)
    }

    @MainActor
    func testReviewFixtureRenderMatchesCurrentCanvasContract() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillsbar-review-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try SnapshotRenderer.render(dashboard: .reviewFixture, to: outputURL)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: outputURL)))
        XCTAssertEqual(bitmap.pixelsWide, Int(MenuBarTemplateMetrics.width))
        XCTAssertEqual(bitmap.pixelsHigh, Int(MenuBarTemplateMetrics.preferredHeight))
    }

    @MainActor
    func testReviewFixtureRenderMatchesRetainedBaseline() throws {
        let baselineURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".harness/evidence/2026-10-21-skillsproof-guided-native.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: baselineURL.path))

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillsbar-review-baseline-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try SnapshotRenderer.render(dashboard: .reviewFixture, configuration: SnapshotConfiguration(colorScheme: .dark), to: outputURL)
        let baselineBitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: baselineURL)))
        let renderedBitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: outputURL)))
        XCTAssertEqual(renderedBitmap.pixelsWide, baselineBitmap.pixelsWide)
        XCTAssertEqual(renderedBitmap.pixelsHigh, baselineBitmap.pixelsHigh)
        XCTAssertLessThanOrEqual(
            try pixelDifference(outputURL, baselineURL),
            0.05,
            "The production fixture render must remain within the retained visual baseline contract"
        )
    }

    @MainActor
    func testReviewFixtureRendersPipelinePostureDeterministically() throws {
        let firstURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillsbar-review-first-\(UUID().uuidString).png")
        let secondURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillsbar-review-second-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }

        try SnapshotRenderer.render(dashboard: .reviewFixture, to: firstURL)
        try SnapshotRenderer.render(dashboard: .reviewFixture, to: secondURL)

        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: firstURL)))
        XCTAssertEqual(bitmap.pixelsWide, Int(MenuBarTemplateMetrics.width))
        XCTAssertEqual(bitmap.pixelsHigh, Int(MenuBarTemplateMetrics.preferredHeight))
        XCTAssertLessThanOrEqual(
            try pixelDifference(firstURL, secondURL),
            0.0005,
            "Repeated production renders must not capture partially materialized layers"
        )
    }

    @MainActor
    func testAdaptiveAndSemanticVariantsRenderAtStableCanvasSize() throws {
        var advisory = SkillDashboard.reviewFixture
        advisory.security.status = "Advisory"
        advisory.security.score = 70

        var publicRegistry = SkillDashboard.reviewFixture
        publicRegistry.tessl.registryVisibility = "public"

        var missingVisibility = SkillDashboard.reviewFixture
        missingVisibility.tessl.registryVisibility = nil

        let variants: [(SkillDashboard, SnapshotConfiguration)] = [
            (advisory, .default),
            (publicRegistry, .default),
            (missingVisibility, .default),
            (.reviewFixture, SnapshotConfiguration(colorScheme: .light)),
            (.reviewFixture, SnapshotConfiguration(colorScheme: .dark)),
            (.reviewFixture, SnapshotConfiguration(dynamicTypeSize: .accessibility2, reduceTransparency: true, increasedContrast: true))
        ]

        for (dashboard, configuration) in variants {
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("skillsbar-variant-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: outputURL) }
            try SnapshotRenderer.render(dashboard: dashboard, configuration: configuration, to: outputURL)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: outputURL)))
            XCTAssertEqual(bitmap.pixelsWide, Int(MenuBarTemplateMetrics.width))
            XCTAssertEqual(bitmap.pixelsHigh, Int(MenuBarTemplateMetrics.preferredHeight))
        }
    }

    @MainActor
    func testLightAndDarkAppearancesRenderDistinctAdaptivePopovers() throws {
        let lightURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillsbar-light-appearance-\(UUID().uuidString).png")
        let darkURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillsbar-dark-appearance-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: lightURL)
            try? FileManager.default.removeItem(at: darkURL)
        }

        try SnapshotRenderer.render(
            dashboard: .reviewFixture,
            configuration: SnapshotConfiguration(colorScheme: .light),
            to: lightURL
        )
        try SnapshotRenderer.render(
            dashboard: .reviewFixture,
            configuration: SnapshotConfiguration(colorScheme: .dark),
            to: darkURL
        )

        XCTAssertGreaterThan(
            try pixelDifference(lightURL, darkURL),
            0.05,
            "The popover must visibly follow an explicit light or dark system appearance."
        )
    }

    func testSnapshotDarkFlagPinsTheCaptureAppearance() {
        XCTAssertNil(SnapshotRequest.configuration(arguments: ["SkillsBar", "--snapshot", "capture.png"]).colorScheme)
        XCTAssertEqual(
            SnapshotRequest.configuration(arguments: ["SkillsBar", "--snapshot-dark", "--snapshot", "capture.png"]).colorScheme,
            .dark
        )
    }

    #if DEBUG
    func testReviewFixtureBypassesLiveLoader() throws {
        var liveLoadCount = 0
        let source = DashboardDataSource(
            environment: ["SKILLSBAR_REVIEW_FIXTURE": "1"],
            liveLoad: {
                liveLoadCount += 1
                return .placeholder
            }
        )

        let dashboard = try source.loadSync()

        XCTAssertEqual(liveLoadCount, 0)
        XCTAssertEqual(dashboard.reviewInspectCommand, expectedCommand)
    }

    @MainActor
    func testDemoModePreservesFixtureBoundaryForThePopover() {
        let source = DashboardDataSource(
            environment: [SkillsBarDemoMode.environmentKey: "1"],
            liveLoad: {
                XCTFail("Demo mode must not invoke the live loader")
                return .placeholder
            }
        )
        let model = DashboardModel(
            dashboard: source.initialDashboard,
            autorefresh: false,
            source: source
        )

        XCTAssertTrue(source.usesReviewFixture)
        XCTAssertTrue(model.usesReviewFixture)
        XCTAssertEqual(model.dashboard.tessl.dataOrigin, .liveCLI)
    }

    @MainActor
    func testAsyncNoCLIFixtureBypassesLiveLoader() async throws {
        var liveLoadCount = 0
        let source = DashboardDataSource(
            environment: ["SKILLSBAR_REVIEW_FIXTURE": "no-cli"],
            liveLoad: { .placeholder },
            liveLoadAsync: {
                liveLoadCount += 1
                return .reviewFixture
            }
        )

        let dashboard = try await source.load()

        XCTAssertEqual(liveLoadCount, 0)
        XCTAssertEqual(
            dashboard.registryEvidenceCaption,
            "Historical external baseline · not proof for this candidate."
        )
    }
    #endif

    @MainActor
    func testAsyncLoadUsesLiveLoaderWhenFixtureIsDisabled() async throws {
        var liveLoadCount = 0
        let source = DashboardDataSource(
            environment: [:],
            liveLoad: { .placeholder },
            liveLoadAsync: {
                liveLoadCount += 1
                return .reviewFixture
            }
        )

        let dashboard = try await source.load()

        XCTAssertEqual(liveLoadCount, 1)
        XCTAssertEqual(dashboard.registryPath, SkillDashboard.reviewFixture.registryPath)
    }

    func testPipelinePostureReconcilesVisibleFixtureContributions() {
        let candidate = SkillDashboard.reviewFixture.pipeline

        XCTAssertEqual(candidate.orderedReceipts.map(\.stage), PipelineStage.allCases)
        XCTAssertEqual(candidate.orderedReceipts.count, 9)
        XCTAssertEqual(
            candidate.orderedReceipts.map(\.evidenceStatus),
            [.reviewRequired, .held, .held, .held, .unproven, .unproven, .unproven, .unproven, .unproven]
        )
        XCTAssertEqual(candidate.orderedReceipts.map { candidate.contribution(for: $0) }, Array(repeating: 0, count: 9))
        XCTAssertEqual(candidate.postureScore, 0)
        XCTAssertEqual(
            candidate.postureScore,
            candidate.orderedReceipts.reduce(0) { $0 + candidate.contribution(for: $1) }
        )
    }

    func testPipelineGatesLaterReceiptsAfterReviewStage() {
        let fingerprint = "candidate-a"
        let candidate = PipelineCandidate(
            fingerprint: fingerprint,
            governedInputPaths: ["Skills/example/SKILL.md"],
            observedAt: Date(timeIntervalSince1970: 0),
            stageReceipts: PipelineStage.allCases.map { stage in
                PipelineStageReceipt(
                    stage: stage,
                    candidateFingerprint: fingerprint,
                    evidenceStatus: stage == .securityReview ? .reviewRequired : .passed,
                    stageScore: 100,
                    command: "inspect \(stage.title)",
                    receiptPath: "receipt:\(stage.rawValue)",
                    modelProfile: "test",
                    observedAt: Date(timeIntervalSince1970: 0),
                    nextAction: "Inspect \(stage.title)"
                )
            }
        )

        guard let securityIndex = PipelineStage.allCases.firstIndex(of: .securityReview) else {
            XCTFail("Security review must remain a canonical pipeline stage")
            return
        }
        XCTAssertTrue(candidate.orderedReceipts.prefix(securityIndex).allSatisfy { $0.evidenceStatus == .passed })
        XCTAssertEqual(candidate.orderedReceipts[securityIndex].evidenceStatus, .reviewRequired)
        XCTAssertTrue(candidate.orderedReceipts.dropFirst(securityIndex + 1).allSatisfy { $0.evidenceStatus == .held })
        XCTAssertEqual(candidate.postureScore, 35)
    }

    func testMissingPipelineStageRemainsUnprovenAndHoldsLaterReceipts() {
        for missing in PipelineStage.allCases {
            let candidate = PipelineCandidate(
                fingerprint: "candidate-a",
                governedInputPaths: [],
                observedAt: Date(timeIntervalSince1970: 0),
                stageReceipts: PipelineStage.allCases
                    .filter { $0 != missing }
                    .map(passedPipelineReceipt)
            )

            XCTAssertEqual(candidate.orderedReceipts.map(\.stage), PipelineStage.allCases)
            XCTAssertEqual(candidate.activeReceipt?.stage, missing)
            for receipt in candidate.orderedReceipts {
                let expected: PipelineEvidenceStatus = receipt.stage.number < missing.number
                    ? .passed : (receipt.stage == missing ? .unproven : .held)
                XCTAssertEqual(receipt.evidenceStatus, expected, "Missing \(missing): \(receipt.stage)")
                if receipt.stage.number >= missing.number {
                    XCTAssertEqual(candidate.contribution(for: receipt), 0)
                }
            }
        }
    }

    func testEmptyPipelineHasNineUnprovenStages() {
        let candidate = PipelineCandidate(
            fingerprint: "candidate-a",
            governedInputPaths: [],
            observedAt: Date(timeIntervalSince1970: 0),
            stageReceipts: []
        )

        XCTAssertEqual(candidate.orderedReceipts.map(\.stage), PipelineStage.allCases)
        XCTAssertTrue(candidate.orderedReceipts.allSatisfy { $0.evidenceStatus == .unproven })
        XCTAssertEqual(candidate.activeReceipt?.stage, .candidateBaseline)
        XCTAssertEqual(candidate.postureScore, 0)
    }

    func testCompletePipelineRetainsPassedEvidence() {
        let receipts = PipelineStage.allCases.map(passedPipelineReceipt)
        let candidate = PipelineCandidate(
            fingerprint: "candidate-a",
            governedInputPaths: [],
            observedAt: Date(timeIntervalSince1970: 0),
            stageReceipts: receipts
        )

        XCTAssertEqual(candidate.orderedReceipts, receipts)
        XCTAssertNil(candidate.activeReceipt)
        XCTAssertEqual(candidate.postureScore, 100)
    }

    private func passedPipelineReceipt(_ stage: PipelineStage) -> PipelineStageReceipt {
        PipelineStageReceipt(
            stage: stage,
            candidateFingerprint: "candidate-a",
            evidenceStatus: .passed,
            stageScore: 100,
            command: "inspect \(stage.title)",
            receiptPath: "receipt:\(stage.rawValue)",
            modelProfile: "test",
            observedAt: Date(timeIntervalSince1970: 0),
            nextAction: "Inspect \(stage.title)"
        )
    }

    func testFingerprintChangeMakesOldReceiptsStale() {
        let oldFingerprint = "old"
        let candidate = PipelineCandidate(
            fingerprint: "new",
            governedInputPaths: ["Skills/example/SKILL.md", "Skills/example/references/core.md"],
            observedAt: Date(timeIntervalSince1970: 1),
            stageReceipts: PipelineStage.allCases.map { stage in
                PipelineStageReceipt(
                    stage: stage,
                    candidateFingerprint: oldFingerprint,
                    evidenceStatus: .passed,
                    stageScore: 100,
                    command: "inspect",
                    receiptPath: "old-receipt",
                    modelProfile: "test",
                    observedAt: Date(timeIntervalSince1970: 0),
                    nextAction: "Re-establish evidence"
                )
            }
        )

        XCTAssertTrue(candidate.orderedReceipts.allSatisfy { $0.evidenceStatus == .stale })
        XCTAssertEqual(candidate.evidencedStageCount, 0)
        XCTAssertEqual(candidate.postureScore, 0)
    }

    func testLoaderRejectsEvidenceWhenGovernedInputChangesDuringCollection() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillsbar-candidate-binding-\(UUID().uuidString)")
        let selectedSkillPath = "Skills/example/SKILL.md"
        let skillURL = root.appendingPathComponent(selectedSkillPath)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: skillURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# Candidate before collection".write(to: skillURL, atomically: true, encoding: .utf8)

        let boundEvidence = try DashboardLoader.collectEvidence(
            root: root,
            selectedSkillPath: selectedSkillPath
        ) {
            try "# Candidate changed during collection".write(
                to: skillURL,
                atomically: true,
                encoding: .utf8
            )
            return (
                quality: MetricSignal(
                    score: 100,
                    detail: "Package verified.",
                    source: "Local SDK package verify",
                    command: "verify"
                ),
                security: SecuritySignal(
                    score: 100,
                    status: "Passed",
                    detail: "No known issues.",
                    sourceLabel: "Local SDK risk-modes",
                    segmentCount: 0,
                    inspectCommand: "inspect"
                )
            )
        }
        let candidate = DashboardLoader.pipelineCandidate(
            root: root,
            selectedSkillPath: selectedSkillPath,
            evidenceFingerprint: boundEvidence.candidateFingerprint,
            quality: boundEvidence.evidence.quality,
            security: boundEvidence.evidence.security,
            observedAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertNotEqual(candidate.fingerprint, boundEvidence.candidateFingerprint)
        XCTAssertTrue(candidate.orderedReceipts.prefix(4).allSatisfy { $0.evidenceStatus == .stale })
        XCTAssertTrue(candidate.orderedReceipts.dropFirst(4).allSatisfy { $0.evidenceStatus == .unproven })
        XCTAssertEqual(candidate.evidencedStageCount, 0)
        XCTAssertEqual(candidate.postureScore, 0)
    }

    func testPipelineCandidateRejectsMissingGovernedInput() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillsbar-missing-candidate-\(UUID().uuidString)")
        let selectedSkillPath = "Skills/example/SKILL.md"
        let skillURL = root.appendingPathComponent(selectedSkillPath)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: skillURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# Candidate before removal".write(to: skillURL, atomically: true, encoding: .utf8)

        let boundEvidence = DashboardLoader.collectEvidence(
            root: root,
            selectedSkillPath: selectedSkillPath
        ) {}
        try FileManager.default.removeItem(at: skillURL)

        let candidate = DashboardLoader.pipelineCandidate(
            root: root,
            selectedSkillPath: selectedSkillPath,
            evidenceFingerprint: boundEvidence.candidateFingerprint,
            quality: MetricSignal(
                score: 100,
                detail: "Package verified.",
                source: "Local SDK package verify",
                command: "verify"
            ),
            security: SecuritySignal(
                score: 100,
                status: "Passed",
                detail: "No known issues.",
                sourceLabel: "Local SDK risk-modes",
                segmentCount: 0,
                inspectCommand: "inspect"
            )
        )

        XCTAssertEqual(candidate.fingerprint, "unreadable-candidate")
        XCTAssertTrue(candidate.orderedReceipts.allSatisfy { $0.evidenceStatus == .unproven })
    }

    func testCanonicalIdentityRemainsActiveUntilCanonicalDigestExists() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillsbar-active-stage-\(UUID().uuidString)")
        let selectedSkillPath = "Skills/example/SKILL.md"
        let skillURL = root.appendingPathComponent(selectedSkillPath)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: skillURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# Stable candidate".write(to: skillURL, atomically: true, encoding: .utf8)
        let fingerprint = DashboardLoader.collectEvidence(
            root: root,
            selectedSkillPath: selectedSkillPath
        ) {}
        let candidate = DashboardLoader.pipelineCandidate(
            root: root,
            selectedSkillPath: selectedSkillPath,
            evidenceFingerprint: fingerprint.candidateFingerprint,
            quality: MetricSignal(
                score: 100,
                detail: "Package verified.",
                source: "Local SDK package verify",
                command: "verify"
            ),
            security: SecuritySignal(
                score: 100,
                status: "Passed",
                detail: "No known issues.",
                sourceLabel: "Local SDK risk-modes",
                segmentCount: 0,
                inspectCommand: "inspect"
            ),
            observedAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(PipelineStage.ossLocal.title, "Eval local proof")
        XCTAssertEqual(PipelineStage.ossCloud.title, "Eval cloud proof")
        XCTAssertEqual(PipelineStage.tesslLiveRegistry.title, "Tessl publication & registry")
        XCTAssertEqual(
            candidate.orderedReceipts.first { $0.stage == .ossLocal }?.nextAction,
            "Eval local profile · Unproven"
        )
        XCTAssertEqual(
            candidate.orderedReceipts.first { $0.stage == .ossCloud }?.nextAction,
            "Eval cloud profile · Same scenario IDs required"
        )
        XCTAssertEqual(
            candidate.orderedReceipts.first { $0.stage == .tesslLiveRegistry }?.nextAction,
            "Publish receipt · registry visibility"
        )
        XCTAssertEqual(candidate.activeReceipt?.stage, .candidateBaseline)
        XCTAssertEqual(candidate.activeReceipt?.modelProfile, "local-identity")
        XCTAssertEqual(candidate.activeReceipt?.nextAction, "Canonical package digest missing")
        XCTAssertTrue(candidate.activeReceipt?.command.contains("./bin/ask sdk start") ?? false)
    }

    func testHistoricalTesslDataDoesNotChangeLocalPipelinePosture() {
        var dashboard = SkillDashboard.reviewFixture
        let before = dashboard.pipeline.postureScore
        dashboard.tessl.registryScore = 100
        dashboard.tessl.registryQualityScore = 100
        dashboard.tessl.registryImpactScore = 100
        dashboard.tessl.registrySecurityLabel = "Passed"
        dashboard.tessl.registryImprovementMultiplier = 1.28

        XCTAssertEqual(dashboard.pipeline.postureScore, before)
        XCTAssertEqual(dashboard.pipeline.postureScore, 0)
    }

    func testLiveTesslComparisonReportsVersionMatchWithoutClaimingPackageIdentity() {
        var dashboard = SkillDashboard.reviewFixture
        dashboard.version = "v0.2.0"
        dashboard.tessl.registryVersion = "0.2.0"
        dashboard.tessl.dataOrigin = .liveCLI

        XCTAssertEqual(
            dashboard.registryEvidenceCaption,
            "Version matches local declaration · package identity unverified."
        )
    }

    func testLiveTesslComparisonReportsVersionMismatch() {
        var dashboard = SkillDashboard.reviewFixture
        dashboard.version = "0.3.0"
        dashboard.tessl.registryVersion = "0.2.0"
        dashboard.tessl.dataOrigin = .liveCLI

        XCTAssertEqual(
            dashboard.registryEvidenceCaption,
            "Live Tessl registry · v0.2.0 differs from local v0.3.0."
        )
    }

    func testLiveTesslComparisonDoesNotInventIdentityWithoutRegistryVersion() {
        var dashboard = SkillDashboard.reviewFixture
        dashboard.tessl.registryVersion = nil
        dashboard.tessl.dataOrigin = .liveCLI

        XCTAssertEqual(
            dashboard.registryEvidenceCaption,
            "Live Tessl registry data · candidate identity not verified."
        )
    }

    func testMissingTesslCLIUsesHistoricalFallbackCaption() {
        var dashboard = SkillDashboard.reviewFixture
        dashboard.tessl.cliAvailable = false
        dashboard.tessl.dataOrigin = .unavailable

        XCTAssertEqual(
            dashboard.registryEvidenceCaption,
            "Historical external baseline · not proof for this candidate."
        )
    }

    #if DEBUG
    func testNoCLIFixtureUsesCachedRegistryDataWithoutALiveClaim() throws {
        var liveLoadCount = 0
        let source = DashboardDataSource(
            environment: ["SKILLSBAR_REVIEW_FIXTURE": "no-cli"],
            liveLoad: {
                liveLoadCount += 1
                return .placeholder
            }
        )

        let dashboard = try source.loadSync()

        XCTAssertEqual(liveLoadCount, 0)
        XCTAssertEqual(dashboard.tessl.dataOrigin, .cached)
        XCTAssertFalse(dashboard.tessl.cliAvailable)
        XCTAssertEqual(dashboard.tessl.registryScore, 66)
        XCTAssertEqual(dashboard.tessl.registrySecurityDisplay, "Passed")
        XCTAssertEqual(
            dashboard.registryEvidenceCaption,
            "Historical external baseline · not proof for this candidate."
        )
    }
    #endif

    func testTesslRegistryCacheRoundTripsOnlyLiveRegistryObservations() throws {
        let suiteName = "skillsbar-registry-cache-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cache = TesslRegistryCache(defaults: defaults, keyPrefix: "test-cache")

        let observedAt = Date(timeIntervalSince1970: 1_725_000_000)
        cache.save(
            registryPath: "jscraik/improve-agent-native",
            signal: SkillDashboard.reviewFixture.tessl,
            observedAt: observedAt
        )
        let snapshot = try XCTUnwrap(cache.load(registryPath: "jscraik/improve-agent-native"))

        XCTAssertEqual(snapshot.score, 66)
        XCTAssertEqual(snapshot.version, "0.2.0")
        XCTAssertEqual(snapshot.cachedSignal.dataOrigin, .cached)
        XCTAssertFalse(snapshot.cachedSignal.cliAvailable)
        XCTAssertEqual(snapshot.cachedSignal.observedAt, observedAt)
        XCTAssertNil(cache.load(registryPath: "jscraik/another-skill"))

        cache.save(registryPath: "jscraik/unavailable", signal: SkillDashboard.reviewNoCLIFixture.tessl)
        XCTAssertNil(cache.load(registryPath: "jscraik/unavailable"))
    }

    func testNineGatePipelineStressPreservesOrderAndSingleActiveGate() {
        for _ in 0..<1_000 {
            let candidate = SkillDashboard.reviewFixture.pipeline
            XCTAssertEqual(candidate.orderedReceipts.map(\.stage), PipelineStage.allCases)
            XCTAssertEqual(candidate.orderedReceipts.count, 9)
            XCTAssertEqual(candidate.activeReceipt?.stage, .candidateBaseline)
            XCTAssertEqual(candidate.evidencedStageCount, 1)
            XCTAssertEqual(candidate.orderedReceipts.filter { $0.evidenceStatus == .reviewRequired }.count, 1)
            XCTAssertTrue(candidate.orderedReceipts.dropFirst(4).allSatisfy { $0.evidenceStatus == .unproven })
        }
    }

    @MainActor
    func testLiveAndNoCLIFixturesRenderAtStableCanvasSize() throws {
        var renderedSnapshots: [Data] = []
        for dashboard in [SkillDashboard.reviewFixture, .reviewNoCLIFixture] {
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("skillsbar-release-evidence-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: outputURL) }

            try SnapshotRenderer.render(dashboard: dashboard, to: outputURL)
            let snapshot = try Data(contentsOf: outputURL)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: snapshot))
            XCTAssertEqual(bitmap.pixelsWide, Int(MenuBarTemplateMetrics.width))
            XCTAssertEqual(bitmap.pixelsHigh, Int(MenuBarTemplateMetrics.preferredHeight))
            renderedSnapshots.append(snapshot)
        }

        XCTAssertGreaterThan(
            try pixelDifference(renderedSnapshots[0], renderedSnapshots[1]),
            0.0002,
            "The fixed Tessl baseline must make live and no-CLI states visibly distinct without scrolling"
        )
    }

    @MainActor
    func testStageDetailsKeepUniformHeightWithAndWithoutCommands() throws {
        let candidate = SkillDashboard.reviewFixture.pipeline
        var heights: [CGFloat] = []
        for receipt in candidate.orderedReceipts {
            let content = SelectedStageDetail(
                receipt: receipt,
                activeStage: candidate.activeReceipt?.stage,
                stageCount: 9,
                securityBadge: receipt.stage == .securityReview ? "1 critical, 2 high" : ""
            ).frame(width: MenuBarTemplateMetrics.width - 24)
            let hostingView = NSHostingView(rootView: content)
            hostingView.layoutSubtreeIfNeeded()
            heights.append(hostingView.fittingSize.height)
        }
        XCTAssertEqual(heights.count, 9)
        XCTAssertTrue(candidate.orderedReceipts.contains { $0.command.isEmpty })
        XCTAssertTrue(candidate.orderedReceipts.contains { !$0.command.isEmpty })
        let shortest = try XCTUnwrap(heights.min())
        XCTAssertGreaterThan(shortest, 0)
        XCTAssertLessThanOrEqual(try XCTUnwrap(heights.max()) - shortest, 1,
                                 "Stage navigation must not move the registry: \(heights)")
    }

    @MainActor
    func testFocusCanvasRetainsNineStagesAndCommand() {
        let contentWidth = MenuBarTemplateMetrics.width - 32
        let content = ReleaseEvidenceView(dashboard: .reviewFixture, isRefreshing: false)
            .frame(width: contentWidth)
        let hostingView = NSHostingView(rootView: content)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(hostingView.fittingSize.height, 0)
        XCTAssertEqual(MenuBarTemplateMetrics.preferredHeight, 586)
        XCTAssertEqual(SkillDashboard.reviewFixture.pipeline.orderedReceipts.count, 9)
        XCTAssertFalse(SkillDashboard.reviewFixture.pipeline.activeReceipt?.command.isEmpty ?? true)
    }

    func testBlockedLiveRegistryComparisonIsNotCalledHistorical() {
        var dashboard = SkillDashboard.reviewFixture
        dashboard.tessl.cliAvailable = true
        dashboard.tessl.authenticated = false
        dashboard.tessl.dataOrigin = .unavailable

        XCTAssertEqual(
            dashboard.registryEvidenceCaption,
            "Registry comparison unavailable · not proof for this candidate."
        )
    }

    func testUnavailableRegistryWithoutCacheDoesNotClaimHistoricalEvidence() {
        var dashboard = SkillDashboard.placeholder
        dashboard.tessl.dataOrigin = .unavailable
        dashboard.tessl.cliAvailable = false
        dashboard.tessl.registryScore = nil
        dashboard.tessl.registryVersion = nil
        dashboard.tessl.registryQualityScore = nil
        dashboard.tessl.registryImpactScore = nil
        dashboard.tessl.registrySecurityLabel = nil

        XCTAssertEqual(
            dashboard.registryEvidenceCaption,
            "Tessl CLI unavailable · no registry evidence cached."
        )
    }

    func testLiveSourceUsesLoaderWhenFixtureIsDisabled() throws {
        var liveLoadCount = 0
        let source = DashboardDataSource(
            environment: [:],
            liveLoad: {
                liveLoadCount += 1
                return .placeholder
            }
        )

        _ = try source.loadSync()

        XCTAssertEqual(liveLoadCount, 1)
    }

    func testTesslCommandPrefersAnExplicitConfiguredBinary() {
        let command = DashboardLoader.tesslCommand(
            environment: ["TESSL_BIN": "/Applications/Tessl/bin/tessl"]
        )

        XCTAssertEqual(command, "'/Applications/Tessl/bin/tessl'")
    }

    func testTesslVisibilityUsesTheRegistryDetailField() {
        let output = """
        Name            jscraik/improve-agent-native
        Latest Version  0.2.0
        Visibility      Private
        Security        Passed
        """

        XCTAssertEqual(DashboardLoader.tesslVisibility(fromPluginInfo: output), "private")
        XCTAssertNil(DashboardLoader.tesslVisibility(fromPluginInfo: "Registry lookup unavailable"))
    }

    func testSkillDiscoveryListsOnlyLocalSkillMarkdownFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillsbar-skill-discovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Skills/agent-ops/alpha"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Skills/frontend/beta"),
            withIntermediateDirectories: true
        )
        try "# Alpha".write(
            to: root.appendingPathComponent("Skills/agent-ops/alpha/SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Beta".write(
            to: root.appendingPathComponent("Skills/frontend/beta/SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Ignore me".write(
            to: root.appendingPathComponent("Skills/frontend/beta/README.md"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(
            DashboardLoader.discoverSkillPaths(root: root),
            ["Skills/agent-ops/alpha/SKILL.md", "Skills/frontend/beta/SKILL.md"]
        )
    }

    func testMenuBarTemplateUsesApprovedPointMetrics() {
        XCTAssertEqual(MenuBarTemplateMetrics.width, 460)
        let expectedHeight = NSScreen.main.map {
            min(MenuBarTemplateMetrics.preferredHeight, max(1, $0.visibleFrame.height - 32))
        } ?? MenuBarTemplateMetrics.preferredHeight
        XCTAssertEqual(MenuBarTemplateMetrics.height, expectedHeight)
        XCTAssertEqual(MenuBarTemplateMetrics.minimumInteractiveTarget, 44)
        XCTAssertEqual(SkillsSDKIconLoader.menuBarImage?.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(SkillsSDKIconLoader.menuBarImage?.isTemplate, true)
    }

    func testMenuBarStatusTracksEvidenceWithoutTreatingRegistryAsLocalProof() {
        XCTAssertEqual(
            MenuBarStatus.resolve(dashboard: .reviewFixture, isRefreshing: false),
            .attention
        )
        XCTAssertEqual(
            MenuBarStatus.resolve(dashboard: .reviewFixture, isRefreshing: true),
            .refreshing
        )

        var current = SkillDashboard.reviewFixture
        current.pipeline = PipelineCandidate(
            fingerprint: current.pipeline.fingerprint,
            governedInputPaths: current.pipeline.governedInputPaths,
            observedAt: current.pipeline.observedAt,
            stageReceipts: current.pipeline.orderedReceipts.map { receipt in
                PipelineStageReceipt(
                    stage: receipt.stage,
                    candidateFingerprint: current.pipeline.fingerprint,
                    evidenceStatus: .passed,
                    stageScore: receipt.stageScore,
                    command: receipt.command,
                    receiptPath: receipt.receiptPath,
                    modelProfile: receipt.modelProfile,
                    observedAt: receipt.observedAt,
                    nextAction: receipt.nextAction,
                    completedChecks: receipt.completedChecks,
                    requiredChecks: receipt.requiredChecks
                )
            }
        )
        XCTAssertEqual(MenuBarStatus.resolve(dashboard: current, isRefreshing: false), .current)
    }

    @MainActor
    func testCopyWritesExactReviewCommandToInjectedPasteboard() {
        let pasteboard = TestPasteboard()
        let model = CopyFeedbackModel(pasteboard: pasteboard)

        model.copy(SkillDashboard.reviewFixture.reviewInspectCommand)

        XCTAssertEqual(pasteboard.string, expectedCommand)
        XCTAssertEqual(model.copiedCommand, expectedCommand)
    }

    @MainActor
    func testCopyFailureDoesNotReportSuccess() {
        let pasteboard = TestPasteboard()
        pasteboard.acceptsWrites = false
        let model = CopyFeedbackModel(pasteboard: pasteboard)

        XCTAssertFalse(model.copy(expectedCommand))
        XCTAssertNil(model.copiedCommand)
        XCTAssertEqual(model.copyError, "Could not copy command")
        XCTAssertEqual(model.error(for: "unrelated summary"), nil)
    }

    @MainActor
    func testSelectingSkillDuringAnActiveLoadQueuesAnotherRefresh() async {
        let gate = RefreshLoadGate()
        let source = DashboardDataSource(
            environment: [:],
            liveLoadAsync: { await gate.load() }
        )
        let model = DashboardModel(autorefresh: false, source: source)
        let previousSelection = UserDefaults.standard.object(forKey: DashboardLoader.selectedSkillDefaultsKey)
        defer {
            if let previousSelection {
                UserDefaults.standard.set(previousSelection, forKey: DashboardLoader.selectedSkillDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: DashboardLoader.selectedSkillDefaultsKey)
            }
        }

        let initialRefresh = Task { @MainActor in await model.refresh() }
        await gate.waitForBlockedLoad()
        model.selectSkill(path: "Skills/testing/alternate/SKILL.md")
        XCTAssertEqual(model.pendingSelectionPath, "Skills/testing/alternate/SKILL.md")
        await Task.yield()
        await gate.releaseBlockedLoad()
        await initialRefresh.value
        try? await Task.sleep(for: .milliseconds(50))

        let loadCount = await gate.loadCount
        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(model.pendingSelectionPath, "Skills/testing/alternate/SKILL.md",
                       "An unrelated fixture must not clear the requested copy's loading state")
    }

    @MainActor
    func testSourceChangeDuringAnActiveLoadIsReloadedAfterThatLoad() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillsbar-source-change-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let skillPath = "Skills/testing/alternate/SKILL.md"
        let skillURL = root.appendingPathComponent(skillPath)
        try FileManager.default.createDirectory(at: skillURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Alternate".write(to: skillURL, atomically: true, encoding: .utf8)

        var dashboard = SkillDashboard.reviewFixture
        dashboard.repoPath = root.path
        dashboard.fleet.selectedSkillPath = skillPath
        let gate = RefreshLoadGate(dashboard: dashboard, blockOnCall: 2)
        let source = DashboardDataSource(environment: [:], liveLoadAsync: { await gate.load() })
        let model = DashboardModel(dashboard: dashboard, autorefresh: false, source: source)

        await model.refresh()
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 2)],
            ofItemAtPath: skillURL.path
        )

        let activeRefresh = Task { @MainActor in await model.refresh() }
        await gate.waitForBlockedLoad()
        await model.refreshIfSelectedSkillChanged()
        await gate.releaseBlockedLoad()
        await activeRefresh.value
        try? await Task.sleep(for: .milliseconds(50))

        let loadCount = await gate.loadCount
        XCTAssertEqual(loadCount, 3)
    }

}

private actor RefreshLoadGate {
    private let dashboard: SkillDashboard
    private let blockOnCall: Int
    private var calls = 0
    private var blockedLoadStarted = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    init(dashboard: SkillDashboard = .reviewFixture, blockOnCall: Int = 1) {
        self.dashboard = dashboard
        self.blockOnCall = blockOnCall
    }

    var loadCount: Int { calls }

    func load() async -> SkillDashboard {
        calls += 1
        if calls == blockOnCall {
            blockedLoadStarted = true
            startWaiter?.resume()
            startWaiter = nil
            await withCheckedContinuation { releaseWaiter = $0 }
        }
        return dashboard
    }

    func waitForBlockedLoad() async {
        guard !blockedLoadStarted else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func releaseBlockedLoad() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }

}

private func registryMetadata(fixture: String, registryPath: String? = nil) throws -> TesslRegistryMetadata {
    let url = try XCTUnwrap(Bundle.module.url(forResource: fixture, withExtension: "json"))
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    return TesslRegistryMetadata(payload: JSONNode(object), registryPath: registryPath)
}

private func pipelineCandidate(activeStage: PipelineStage) -> PipelineCandidate {
    let fingerprint = "pipeline-presentation-candidate"
    return PipelineCandidate(
        fingerprint: fingerprint,
        governedInputPaths: ["Skills/example/SKILL.md"],
        observedAt: Date(timeIntervalSince1970: 0),
        stageReceipts: PipelineStage.allCases.map { stage in
            PipelineStageReceipt(
                stage: stage,
                candidateFingerprint: fingerprint,
                evidenceStatus: stage.number < activeStage.number
                    ? .passed
                    : (stage == activeStage ? .blocked : .unproven),
                stageScore: stage.number < activeStage.number ? 100 : nil,
                command: "inspect \(stage.title)",
                receiptPath: stage.number < activeStage.number ? "receipt:\(stage.rawValue)" : nil,
                modelProfile: "test",
                observedAt: stage.number < activeStage.number ? Date(timeIntervalSince1970: 0) : nil,
                nextAction: "Inspect \(stage.title)"
            )
        }
    )
}

private func pixelDifference(_ lhsURL: URL, _ rhsURL: URL) throws -> Double {
    try pixelDifference(Data(contentsOf: lhsURL), Data(contentsOf: rhsURL))
}

private func pixelDifference(_ lhsData: Data, _ rhsData: Data) throws -> Double {
    let lhs = try XCTUnwrap(NSBitmapImageRep(data: lhsData))
    let rhs = try XCTUnwrap(NSBitmapImageRep(data: rhsData))
    XCTAssertEqual(lhs.pixelsWide, rhs.pixelsWide)
    XCTAssertEqual(lhs.pixelsHigh, rhs.pixelsHigh)
    let lhsData = try XCTUnwrap(lhs.bitmapData)
    let rhsData = try XCTUnwrap(rhs.bitmapData)
    let count = min(lhs.bytesPerRow * lhs.pixelsHigh, rhs.bytesPerRow * rhs.pixelsHigh)
    guard count > 0 else { return 1 }
    var total = 0
    for index in 0..<count {
        total += abs(Int(lhsData[index]) - Int(rhsData[index]))
    }
    return Double(total) / Double(count * 255)
}
