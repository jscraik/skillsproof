import Foundation
@testable import SkillsBar
import SkillsBarCore
import XCTest

final class PipelineEvidenceLoaderTests: XCTestCase {
    private let selectedSkillPath = "Skills/example/SKILL.md"
    private let digest = "sha256:" + String(repeating: "a", count: 64)
    private let otherDigest = "sha256:" + String(repeating: "b", count: 64)

    func testLiveProductionLoaderWhenExplicitlyEnabled() throws {
        guard ProcessInfo.processInfo.environment["SKILLSBAR_LIVE_INTEGRATION"] == "1" else {
            throw XCTSkip("Set SKILLSBAR_LIVE_INTEGRATION=1 to run against the configured agent-skills and Tessl surfaces.")
        }

        let dashboard = try DashboardLoader().loadSync()

        XCTAssertEqual(dashboard.pipeline.orderedReceipts.count, 9)
        XCTAssertEqual(dashboard.pipeline.orderedReceipts.first?.stage, .candidateBaseline)
        XCTAssertEqual(
            dashboard.pipeline.orderedReceipts.first?.evidenceStatus,
            .passed
        )
        XCTAssertEqual(
            dashboard.pipeline.orderedReceipts.first?.nextAction,
            "Canonical package digest established"
        )
        XCTAssertEqual(
            dashboard.pipeline.orderedReceipts.first { $0.stage == .mechanicalValidation }?.evidenceStatus,
            .passed
        )
        XCTAssertEqual(
            dashboard.pipeline.orderedReceipts.first { $0.stage == .mechanicalValidation }?.nextAction,
            "Package verify passed · strict audit passed"
        )
        XCTAssertNotNil(dashboard.pipeline.activeReceipt)
        XCTAssertTrue(dashboard.localEvidenceCommand.contains("sdk package build"))
        XCTAssertTrue(dashboard.localEvidenceCommand.contains("skills audit"))
        XCTAssertTrue(dashboard.localEvidenceCommand.contains("scorer-calibration"))
    }

    func testLocalRefreshUsesAllRequiredReadOnlySDKChecks() {
        let command = DashboardLoader.localEvidenceCommand(
            root: URL(fileURLWithPath: "/tmp/agent-skills"),
            skillPath: selectedSkillPath
        )

        XCTAssertTrue(command.contains("sdk package build"))
        XCTAssertTrue(command.contains("skills package verify"))
        XCTAssertTrue(command.contains("skills audit"))
        XCTAssertTrue(command.contains("sdk security risk-modes"))
        XCTAssertTrue(command.contains("sdk eval scenario-quality"))
        XCTAssertTrue(command.contains("sdk eval scorer-quality"))
        XCTAssertTrue(command.contains("sdk eval scorer-calibration"))
        XCTAssertFalse(command.contains("oss-local"))
        XCTAssertFalse(command.contains("oss-cloud"))
        XCTAssertFalse(command.contains("tessl-live"))
        XCTAssertEqual(
            DashboardLoader.impactCommand(for: selectedSkillPath),
            "./bin/ask sdk eval scenario-quality 'Skills/example' --preview --json --robot"
        )
    }

    func testLocalEvidenceCacheReusesOnlyTheExactPackageDigest() {
        let cache = LocalEvidenceCache()
        let checks = makeChecks(digest: digest)
        let key = "/tmp/agent-skills::\(selectedSkillPath)"

        cache.store(checks, packageDigest: digest, for: key)

        XCTAssertNotNil(cache.entry(for: key, packageDigest: digest))
        XCTAssertNil(cache.entry(for: key, packageDigest: otherDigest))
        XCTAssertNil(cache.entry(for: "another-skill", packageDigest: digest))
    }

    func testTesslSessionCacheKeepsVersionsSeparateByExecutable() {
        let cache = TesslSessionCache()

        cache.store(version: "0.42.0", for: "/tmp/tessl-a")

        XCTAssertEqual(cache.version(for: "/tmp/tessl-a"), "0.42.0")
        XCTAssertNil(cache.version(for: "/tmp/tessl-b"))
    }

    func testCandidateIdentityFailureExplainsAutomaticCommandFailure() throws {
        try withRepo { root in
            let failedBuild = CommandResult(
                exitCode: 1,
                stdout: "",
                stderr: "SDK runtime unavailable"
            )
            let receipts = makeLoader(root: root, packageBuild: failedBuild).stageReceipts()
            let identity = try XCTUnwrap(receipts.first)

            XCTAssertEqual(identity.stage, .candidateBaseline)
            XCTAssertEqual(identity.evidenceStatus, .blocked)
            XCTAssertEqual(
                identity.nextAction,
                "Automatic identity command failed: SDK runtime unavailable"
            )
        }
    }

    func testCandidateIdentityFailureExplainsUnreadableAutomaticOutput() throws {
        try withRepo { root in
            let unreadableBuild = CommandResult(exitCode: 0, stdout: "not json", stderr: "")
            let receipts = makeLoader(root: root, packageBuild: unreadableBuild).stageReceipts()

            XCTAssertEqual(
                receipts.first?.nextAction,
                "Automatic identity command returned unreadable JSON"
            )
        }
    }

    func testMissingDurableReceiptsNeverInventsDownstreamProof() throws {
        try withRepo { root in
            let receipts = makeLoader(root: root).stageReceipts()

            XCTAssertEqual(receipts.prefix(4).map(\.evidenceStatus), [.passed, .passed, .passed, .passed])
            XCTAssertEqual(receipts.dropFirst(4).map(\.evidenceStatus), Array(repeating: .unproven, count: 5))
        }
    }

    func testCandidateIdentityAcceptsSuccessAfterUnfinishedLogQuote() throws {
        try withRepo { root in
            var build = makeChecks(digest: digest).packageBuild
            build.stdout = "warning \"unfinished\n" + build.stdout
            let identity = makeLoader(root: root, packageBuild: build).stageReceipts().first

            XCTAssertEqual(identity?.evidenceStatus, .passed)
            XCTAssertEqual(identity?.nextAction, "Canonical package digest established")
        }
    }

    func testCleanRiskTaxonomyCannotPassWithoutFullGovernedSecurityReceipt() throws {
        try withRepo { root in
            try FileManager.default.removeItem(at: securityReceiptURL(root))

            let security = makeLoader(root: root).stageReceipts().first { $0.stage == .securityReview }

            XCTAssertEqual(security?.evidenceStatus, .unproven)
            XCTAssertTrue(security?.nextAction.contains("missing or malformed") == true)
        }
    }

    func testCompleteCandidateBoundEvidenceCanProveAllNineStages() throws {
        try withRepo { root in
            try writeGateChain(
                root: root,
                gates: ["oss_local", "oss_cloud", "tessl_local_proof", "tessl_dry_run", "handoff_readiness"],
                digest: digest,
                scenarioIDs: ["scenario-a", "scenario-b"]
            )
            try writeReleaseReceipt(
                root: root,
                gate: "tessl_live_registry",
                digest: digest,
                scenarioIDs: ["scenario-a", "scenario-b"]
            )
            try writeRuntimeCard(root: root, digest: digest, status: "pass")

            let receipts = makeLoader(root: root).stageReceipts()

            XCTAssertEqual(receipts.map(\.evidenceStatus), Array(repeating: .passed, count: 9))
            XCTAssertTrue(receipts.dropFirst(4).allSatisfy { $0.receiptPath != nil })
        }
    }

    func testDigestMismatchMarksTheReceiptStale() throws {
        try withRepo { root in
            try writeGateChain(root: root, gates: ["oss_local"], digest: otherDigest, scenarioIDs: ["scenario-a"])

            let local = makeLoader(root: root).stageReceipts().first { $0.stage == .ossLocal }

            XCTAssertEqual(local?.evidenceStatus, .stale)
            XCTAssertTrue(local?.nextAction.contains("different package digest") == true)
        }
    }

    func testGateChainRequiresEveryPrecedingGateToPass() throws {
        try withRepo { root in
            try writeGateChain(root: root, gates: ["oss_local"], digest: digest, scenarioIDs: ["scenario-a"])
            let gateChain = handoffDirectory(root).appendingPathComponent("gate-chain.json")
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: gateChain)) as? [String: Any])
            var gates = try XCTUnwrap(object["gates"] as? [[String: Any]])
            gates[0]["status"] = "blocked"
            object["gates"] = gates
            try writeJSON(object, to: gateChain)

            let local = makeLoader(root: root).stageReceipts().first { $0.stage == .ossLocal }

            XCTAssertEqual(local?.evidenceStatus, .unproven)
            XCTAssertTrue(local?.nextAction.contains("gate-chain") == true)
        }
    }

    func testEvalCloudRequiresTheSameScenarioIdentitiesAsEvalLocal() throws {
        try withRepo { root in
            try writeGateChain(
                root: root,
                gates: ["oss_local", "oss_cloud"],
                digest: digest,
                scenarioIDsByGate: [
                    "oss_local": ["scenario-a", "scenario-b"],
                    "oss_cloud": ["scenario-a", "scenario-c"]
                ]
            )

            let cloud = makeLoader(root: root).stageReceipts().first { $0.stage == .ossCloud }

            XCTAssertEqual(cloud?.evidenceStatus, .blocked)
            XCTAssertTrue(cloud?.nextAction.contains("do not match") == true)
        }
    }

    func testUnsafeReceiptPathIsRejected() throws {
        try withRepo { root in
            let handoff = handoffDirectory(root)
            try FileManager.default.createDirectory(at: handoff, withIntermediateDirectories: true)
            try writeJSON([
                "schema_version": "skills-sdk.gate-chain.v1",
                "gates": [[
                    "id": "oss_local",
                    "status": "pass",
                    "receipt_path": "../outside.json"
                ]]
            ], to: handoff.appendingPathComponent("gate-chain.json"))

            let local = makeLoader(root: root).stageReceipts().first { $0.stage == .ossLocal }

            XCTAssertEqual(local?.evidenceStatus, .unproven)
            XCTAssertNil(local?.receiptPath)
        }
    }

    func testLiveRegistryDataCannotPromotePublicationWithoutCandidateReceipt() throws {
        try withRepo { root in
            try writeGateChain(
                root: root,
                gates: ["oss_local", "oss_cloud", "tessl_local_proof", "tessl_dry_run", "handoff_readiness"],
                digest: digest,
                scenarioIDs: ["scenario-a"]
            )

            let publication = makeLoader(root: root).stageReceipts().first { $0.stage == .tesslLiveRegistry }

            XCTAssertEqual(publication?.evidenceStatus, .unproven)
            XCTAssertTrue(publication?.nextAction.contains("publication") == true)
        }
    }

    func testRuntimeCardForAnotherDigestIsStale() throws {
        try withRepo { root in
            try writeGateChain(
                root: root,
                gates: ["oss_local", "oss_cloud", "tessl_local_proof", "tessl_dry_run", "handoff_readiness"],
                digest: digest,
                scenarioIDs: ["scenario-a"]
            )
            try writeReleaseReceipt(root: root, gate: "tessl_live_registry", digest: digest, scenarioIDs: ["scenario-a"])
            try writeRuntimeCard(root: root, digest: otherDigest, status: "pass")

            let runtime = makeLoader(root: root).stageReceipts().first { $0.stage == .liveScoreAndRuntime }

            XCTAssertEqual(runtime?.evidenceStatus, .stale)
        }
    }

    /// Verifies that a malformed package digest blocks identity and leaves downstream evidence unproven.
    func testMalformedCanonicalDigestBlocksIdentityAndDownstreamEvidence() throws {
        try withRepo { root in
            let checks = makeChecks(digest: "not-a-digest")
            let receipts = makeLoader(root: root, checks: checks).stageReceipts()

            XCTAssertEqual(receipts.first?.evidenceStatus, .blocked)
            XCTAssertTrue(receipts.dropFirst().allSatisfy { $0.evidenceStatus == .unproven })
        }
    }

    /// Verifies that changing the skill during collection makes the first four receipts stale and the posture score zero.
    func testProductionCandidateRejectsInputsChangedDuringCollection() throws {
        try withRepo { root in
            let bound = try DashboardLoader.collectEvidence(root: root, selectedSkillPath: selectedSkillPath) {
                try "# Changed while checking".write(
                    to: root.appendingPathComponent(selectedSkillPath), atomically: true, encoding: .utf8
                )
                return makeChecks(digest: digest)
            }

            let candidate = DashboardLoader.productionPipelineCandidate(
                root: root, selectedSkillPath: selectedSkillPath,
                evidenceFingerprint: bound.candidateFingerprint, checks: bound.evidence,
                tessl: SkillDashboard.reviewFixture.tessl
            )

            XCTAssertNotEqual(candidate.fingerprint, bound.candidateFingerprint)
            XCTAssertTrue(candidate.orderedReceipts.prefix(4).allSatisfy { $0.evidenceStatus == .stale })
            XCTAssertEqual(candidate.postureScore, 0)
        }
    }

    /// Verifies that stable input passes the first four stages and removing it leaves every receipt unproven.
    func testProductionCandidateAcceptsStableInputAndRejectsRemovedInput() throws {
        try withRepo { root in
            let bound = DashboardLoader.collectEvidence(root: root, selectedSkillPath: selectedSkillPath) {
                makeChecks(digest: digest)
            }
            /// Rebuilds the candidate from current files using the evidence captured before any input removal.
            func candidate() -> PipelineCandidate {
                DashboardLoader.productionPipelineCandidate(
                    root: root, selectedSkillPath: selectedSkillPath,
                    evidenceFingerprint: bound.candidateFingerprint, checks: bound.evidence,
                    tessl: SkillDashboard.reviewFixture.tessl
                )
            }

            XCTAssertEqual(
                candidate().orderedReceipts.prefix(4).map(\.evidenceStatus),
                Array(repeating: .passed, count: 4)
            )

            try FileManager.default.removeItem(at: root.appendingPathComponent(selectedSkillPath))

            XCTAssertEqual(candidate().fingerprint, "unreadable-candidate")
            XCTAssertTrue(candidate().orderedReceipts.allSatisfy { $0.evidenceStatus == .unproven })
        }
    }

    /// Creates a loader with deterministic observation time, live Tessl fixture state, and optional check overrides.
    private func makeLoader(
        root: URL,
        checks: PipelineEvidenceLoader.LocalChecks? = nil,
        packageBuild: CommandResult? = nil
    ) -> PipelineEvidenceLoader {
        var tessl = SkillDashboard.reviewFixture.tessl
        tessl.ok = true
        tessl.cliAvailable = true
        tessl.authenticated = true
        tessl.dataOrigin = .liveCLI
        return PipelineEvidenceLoader(
            root: root,
            selectedSkillPath: selectedSkillPath,
            evidenceFingerprint: "candidate-fingerprint",
            checks: checks ?? makeChecks(digest: digest, packageBuild: packageBuild),
            tessl: tessl,
            observedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func makeChecks(
        digest: String,
        packageBuild: CommandResult? = nil
    ) -> PipelineEvidenceLoader.LocalChecks {
        PipelineEvidenceLoader.LocalChecks(
            packageBuild: packageBuild ?? result([
                "status": "success",
                "data": ["skills_sdk_package_build": [
                    "status": "built",
                    "canonical_source_path": selectedSkillPath,
                    "version": "0.2.0",
                    "package_digest": digest,
                    "mutation_performed": false
                ]]
            ]),
            strictAudit: result([
                "status": "success",
                "data": [
                    "diagnostics": ["exit_code": 0],
                    "security_gate": ["exit_code": 0],
                    "family_benchmarks": ["exit_code": 0],
                    "openclaw_guard": ["exit_code": 0]
                ]
            ]),
            packageVerify: result([
                "status": "success",
                "data": ["skill_package_verification": [
                    "status": "pass",
                    "checks": [["status": "pass"], ["status": "pass"]]
                ]]
            ]),
            securityRiskModes: result([
                "status": "success",
                "data": ["skills_sdk_risk_mode_taxonomy": [
                    "package_digest": digest,
                    "receipt": ["status": "pass", "mode_results": []]
                ]]
            ]),
            scenarioQuality: result([
                "status": "success",
                "data": ["skills_sdk_eval_scenario_quality": [
                    "status": "preview",
                    "blocked_count": 0,
                    "scenario_count": 2,
                    "promotion_ready_count": 2
                ]]
            ]),
            scorerQuality: previewResult(key: "skills_sdk_eval_scorer_quality"),
            scorerCalibration: previewResult(key: "skills_sdk_eval_scorer_calibration")
        )
    }

    private func previewResult(key: String) -> CommandResult {
        result([
            "status": "success",
            "data": [key: ["status": "preview", "ready": true, "blocked_count": 0]]
        ])
    }

    private func result(_ object: [String: Any]) -> CommandResult {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            XCTFail("Test fixture must serialize as JSON")
            return CommandResult(exitCode: 1, stdout: "", stderr: "fixture serialization failed")
        }
        return CommandResult(exitCode: 0, stdout: String(decoding: data, as: UTF8.self), stderr: "")
    }

    private func withRepo(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skillsbar-production-evidence-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let skill = root.appendingPathComponent(selectedSkillPath)
        try FileManager.default.createDirectory(at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "---\nname: example\ndescription: Test\n---\n".write(to: skill, atomically: true, encoding: .utf8)
        try writeSecurityReceipt(root: root, digest: digest)
        try body(root)
    }

    private func writeSecurityReceipt(root: URL, digest: String) throws {
        try writeJSON(
            [
                "status": "success",
                "data": ["skills_sdk_security_lane": [
                    "receipt": [
                        "schema_version": "skills-sdk.security-lane-receipt.v0",
                        "status": "pass",
                        "package_digest": digest,
                        "security_lane_digest": "sha256:" + String(repeating: "c", count: 64),
                        "execution_performed": false,
                        "network_accessed": false,
                        "credentials_accessed": false,
                        "mutation_performed": false
                    ]
                ]]
            ],
            to: securityReceiptURL(root)
        )
    }

    private func securityReceiptURL(_ root: URL) -> URL {
        root.appendingPathComponent(
            ".harness/evidence/skills-sdk/oss-security/example-security-lane-receipt.json"
        )
    }

    private func writeGateChain(
        root: URL,
        gates: [String],
        digest: String,
        scenarioIDs: [String]
    ) throws {
        try writeGateChain(
            root: root,
            gates: gates,
            digest: digest,
            scenarioIDsByGate: Dictionary(uniqueKeysWithValues: gates.map { ($0, scenarioIDs) })
        )
    }

    private func writeGateChain(
        root: URL,
        gates: [String],
        digest: String,
        scenarioIDsByGate: [String: [String]]
    ) throws {
        let handoff = handoffDirectory(root)
        try FileManager.default.createDirectory(at: handoff, withIntermediateDirectories: true)
        let canonical = [
            "sdk_start", "strict_audit", "package_verify", "security_risk_modes",
            "scenario_quality", "scorer_quality", "scorer_calibration", "oss_local",
            "oss_cloud", "tessl_local_proof", "tessl_dry_run", "handoff_readiness"
        ]
        let lastIndex = try XCTUnwrap(gates.compactMap { canonical.firstIndex(of: $0) }.max())
        var rows: [[String: Any]] = []
        for gate in canonical.prefix(lastIndex + 1) {
            let receipt: String
            if gates.contains(gate) {
                receipt = try writeReleaseReceipt(
                    root: root,
                    gate: gate,
                    digest: digest,
                    scenarioIDs: scenarioIDsByGate[gate] ?? []
                )
            } else {
                receipt = ".harness/evidence/handoff/example/not-inspected-\(gate).json"
            }
            rows.append([
                "id": gate,
                "status": "pass",
                "receipt_path": receipt
            ])
        }
        try writeJSON(
            ["schema_version": "skills-sdk.gate-chain.v1", "gates": rows],
            to: handoff.appendingPathComponent("gate-chain.json")
        )
    }

    @discardableResult
    private func writeReleaseReceipt(
        root: URL,
        gate: String,
        digest: String,
        scenarioIDs: [String]
    ) throws -> String {
        let handoff = handoffDirectory(root)
        try FileManager.default.createDirectory(at: handoff, withIntermediateDirectories: true)
        let evidenceRelative = ".harness/evidence/handoff/example/evidence-\(gate).json"
        var evidence: [String: Any] = [
            "status": "pass",
            "package_digest": digest,
            "scenario_ids": scenarioIDs
        ]
        if gate == "tessl_live_registry" {
            evidence["registry_package_digest"] = digest
        }
        try writeJSON(evidence, to: root.appendingPathComponent(evidenceRelative))
        let receiptRelative = ".harness/evidence/handoff/example/release-gate-\(gate).json"
        try writeJSON(
            [
                "schema_version": "skills-sdk.release-gate-receipt.v1",
                "gate": gate,
                "status": "pass",
                "what_this_proves": "This gate is candidate-bound.",
                "what_this_does_not_prove": "This gate does not prove later gates.",
                "evidence_refs": [evidenceRelative]
            ],
            to: root.appendingPathComponent(receiptRelative)
        )
        return receiptRelative
    }

    private func writeRuntimeCard(root: URL, digest: String, status: String) throws {
        let path = root.appendingPathComponent(
            ".harness/evidence/runtime-proof/example/codex/runtime-card.json"
        )
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeJSON(
            [
                "schema_version": 1,
                "skill_handle": "example",
                "runtime_target": "codex",
                "runtime_status": status,
                "package_digest": digest,
                "installed_digest": digest,
                "doctor_status": "pass",
                "observed_behavior_status": "pass"
            ],
            to: path
        )
    }

    private func handoffDirectory(_ root: URL) -> URL {
        root.appendingPathComponent(".harness/evidence/handoff/example")
    }

    private func writeJSON(_ object: Any, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }
}
