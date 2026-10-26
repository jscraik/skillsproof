import Foundation
import SkillsBarCore

struct DashboardLoader {
    var environment: [String: String] = ProcessInfo.processInfo.environment
    var homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    var storedSkillPath: String? = UserDefaults.standard.string(forKey: selectedSkillDefaultsKey)
    var installedRegistryLookup: (@Sendable (URL, String) -> TesslSignal)? = nil
    struct CandidateEvidenceBinding<Value> {
        let candidateFingerprint: String
        let evidence: Value
    }

    static var defaultRepoRoot: URL { resolvedDefaultRepoRoot() }

    static func resolvedDefaultRepoRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let loader = DashboardLoader(environment: environment, homeDirectory: homeDirectory, storedSkillPath: nil)
        return (try? loader.findRepoRoot()) ?? homeDirectory
    }
    static let defaultSkillPath = "Skills/agent-ops/improve-agent-native/SKILL.md"
    static let selectedSkillDefaultsKey = "selectedSkillPath"
    static let packageCommand = "./bin/ask skills package verify Skills/agent-ops/improve-agent-native --json --robot"
    static let packageBuildCommand = "./bin/ask sdk package build Skills/agent-ops/improve-agent-native --json --robot"
    static let strictAuditCommand = "./bin/ask skills audit Skills/agent-ops/improve-agent-native --level strict --json --robot"
    static let impactCommand = "./bin/ask sdk eval scenario-quality Skills/agent-ops/improve-agent-native --preview --json --robot"
    static let scorerQualityCommand = "./bin/ask sdk eval scorer-quality Skills/agent-ops/improve-agent-native --preview --json --robot"
    static let scorerCalibrationCommand = "./bin/ask sdk eval scorer-calibration Skills/agent-ops/improve-agent-native --preview --json --robot"
    static let securityCommand = "./bin/ask sdk security risk-modes Skills/agent-ops/improve-agent-native --preview --json --robot"
    static let allSkillsInventoryCommand = "find Skills -name SKILL.md -print | sort"
    private static let localEvidenceCache = LocalEvidenceCache()
    static func packageCommand(for skillPath: String) -> String {
        "./bin/ask skills package verify \(shellQuoted(skillPath)) --json --robot"
    }

    static func packageBuildCommand(for skillPath: String) -> String {
        "./bin/ask sdk package build \(shellQuoted(skillPackagePath(for: skillPath))) --json --robot"
    }

    static func strictAuditCommand(for skillPath: String) -> String {
        "./bin/ask skills audit \(shellQuoted(skillPackagePath(for: skillPath))) --level strict --json --robot"
    }

    static func impactCommand(for skillPath: String) -> String {
        "./bin/ask sdk eval scenario-quality \(shellQuoted(skillPackagePath(for: skillPath))) --preview --json --robot"
    }

    static func scorerQualityCommand(for skillPath: String) -> String {
        "./bin/ask sdk eval scorer-quality \(shellQuoted(skillPath)) --preview --json --robot"
    }

    static func scorerCalibrationCommand(for skillPath: String) -> String {
        "./bin/ask sdk eval scorer-calibration \(shellQuoted(skillPath)) --preview --json --robot"
    }

    static func securityCommand(for skillPath: String) -> String {
        "./bin/ask sdk security risk-modes \(shellQuoted(skillPath)) --preview --json --robot"
    }

    static func sdkStartCommand(for skillPath: String) -> String {
        "./bin/ask sdk start \(shellQuoted(skillPackagePath(for: skillPath))) --json --robot"
    }

    static func mechanicalEvidenceCommand(for skillPath: String) -> String {
        labelledCommand([
            ("package verify", packageCommand(for: skillPath)),
            ("strict audit", strictAuditCommand(for: skillPath))
        ])
    }

    static func evalPreparationCommand(for skillPath: String) -> String {
        labelledCommand([
            ("scenario quality", impactCommand(for: skillPath)),
            ("scorer quality", scorerQualityCommand(for: skillPath)),
            ("scorer calibration", scorerCalibrationCommand(for: skillPath))
        ])
    }

    static func localEvidenceCommand(root: URL, skillPath: String = defaultSkillPath) -> String {
        copyCommand(root: root, command: labelledCommand([
            ("candidate package digest", packageBuildCommand(for: skillPath)),
            ("quality package verify", packageCommand(for: skillPath)),
            ("quality strict audit", strictAuditCommand(for: skillPath)),
            ("impact scenario-quality", impactCommand(for: skillPath)),
            ("impact scorer-quality", scorerQualityCommand(for: skillPath)),
            ("impact scorer-calibration", scorerCalibrationCommand(for: skillPath)),
            ("security risk-modes", securityCommand(for: skillPath))
        ]))
    }

    static func copyCommand(root: URL, command: String) -> String {
        "cd \(shellQuoted(root.path)) && \(command)"
    }

    static func tesslCommand(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String {
        if let configured = environment["TESSL_BIN"], !configured.isEmpty {
            return shellQuoted(configured)
        }
        let localBinary = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/tessl")
        if fileManager.isExecutableFile(atPath: localBinary.path) {
            return shellQuoted(localBinary.path)
        }
        return "tessl"
    }

    static func tesslVisibility(fromPluginInfo output: String) -> String? {
        guard let line = output.split(separator: "\n").first(where: {
            $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("visibility")
        }) else { return nil }
        let value = line.dropFirst("Visibility".count).trimmingCharacters(in: .whitespaces).lowercased()
        return value == "private" || value == "public" ? value : nil
    }

    static var selectionIsPinnedByEnvironment: Bool {
        let environment = ProcessInfo.processInfo.environment
        return !(environment["AGENT_SKILL_PATH"] ?? environment["SELECTED_SKILL_PATH"] ?? "").isEmpty
    }

    static func discoverSkillPaths(root: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root.appendingPathComponent("Skills"),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.lastPathComponent == "SKILL.md" }
            .compactMap { url in
                let components = url.pathComponents
                guard let skillsIndex = components.lastIndex(of: "Skills") else { return nil }
                return components[skillsIndex...].joined(separator: "/")
            }
            .sorted()
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func skillPackagePath(for skillPath: String) -> String {
        skillPath.hasSuffix("/SKILL.md")
            ? String(skillPath.dropLast("/SKILL.md".count))
            : skillPath
    }

    private static func labelledCommand(_ steps: [(String, String)]) -> String {
        steps.map { label, command in
            "printf '\\n== \(label) ==\\n'; \(command)"
        }.joined(separator: "; ")
    }

    func load(
        onLocalEvidence: (@MainActor (SkillDashboard) -> Void)? = nil
    ) async throws -> SkillDashboard {
        let root = try findRepoRoot()
        let selectedSkillPath = try findSelectedSkillPath(root: root)
        if selectedSkillPath.hasPrefix("/") {
            return try await Task.detached(priority: .utility) {
                try installedDashboard(root: root, skillPath: selectedSkillPath)
            }.value
        }
        let metadata = try SkillMetadata.load(from: root.appendingPathComponent(selectedSkillPath))
        let registryPath = "jscraik/\(metadata.name)"
        let packageBuildCommand = Self.packageBuildCommand(for: selectedSkillPath)
        let strictAuditCommand = Self.strictAuditCommand(for: selectedSkillPath)
        let packageCommand = Self.packageCommand(for: selectedSkillPath)
        let impactCommand = Self.impactCommand(for: selectedSkillPath)
        let scorerQualityCommand = Self.scorerQualityCommand(for: selectedSkillPath)
        let scorerCalibrationCommand = Self.scorerCalibrationCommand(for: selectedSkillPath)
        let securityCommand = Self.securityCommand(for: selectedSkillPath)

        async let tesslResult = tesslSignal(root: root, registryPath: registryPath)

        let fingerprint = Self.candidateFingerprint(root: root, selectedSkillPath: selectedSkillPath)
        let packageBuildResult = await run(root: root, command: packageBuildCommand)
        let cacheKey = "\(root.standardizedFileURL.path)::\(selectedSkillPath)"
        let digest = Self.packageDigest(from: packageBuildResult, selectedSkillPath: selectedSkillPath)
        let cachedChecks = digest.flatMap {
            Self.localEvidenceCache.entry(for: cacheKey, packageDigest: $0)?.checks
        }
        let checks: PipelineEvidenceLoader.LocalChecks
        if let cachedChecks, Self.canReuse(cachedChecks) {
            checks = PipelineEvidenceLoader.LocalChecks(
                packageBuild: packageBuildResult,
                strictAudit: cachedChecks.strictAudit,
                packageVerify: cachedChecks.packageVerify,
                securityRiskModes: cachedChecks.securityRiskModes,
                scenarioQuality: cachedChecks.scenarioQuality,
                scorerQuality: cachedChecks.scorerQuality,
                scorerCalibration: cachedChecks.scorerCalibration
            )
        } else {
            async let strictAuditResult = run(root: root, command: strictAuditCommand)
            async let packageResult = run(root: root, command: packageCommand)
            async let scenarioResult = run(root: root, command: impactCommand)
            async let scorerQualityResult = run(root: root, command: scorerQualityCommand)
            async let scorerCalibrationResult = run(root: root, command: scorerCalibrationCommand)
            async let securityResult = run(root: root, command: securityCommand)
            checks = await PipelineEvidenceLoader.LocalChecks(
                packageBuild: packageBuildResult,
                strictAudit: strictAuditResult,
                packageVerify: packageResult,
                securityRiskModes: securityResult,
                scenarioQuality: scenarioResult,
                scorerQuality: scorerQualityResult,
                scorerCalibration: scorerCalibrationResult
            )
            if let digest {
                Self.localEvidenceCache.store(checks, packageDigest: digest, for: cacheKey)
            }
        }
        let quality = qualitySignal(from: checks.packageVerify, root: root, command: packageCommand)
        let impact = impactSignal(from: checks.scenarioQuality, root: root, command: impactCommand)
        let securitySignal = securitySignal(from: checks.securityRiskModes, root: root, command: securityCommand)
        let fleet = fleetSignal(root: root, selectedSkillPath: selectedSkillPath)
        if let onLocalEvidence {
            let cachedTessl = TesslRegistryCache().load(registryPath: registryPath)?.cachedSignal
                ?? Self.pendingTesslSignal(registryPath: registryPath)
            let localDashboard = makeDashboard(
                metadata: metadata,
                registryPath: registryPath,
                root: root,
                selectedSkillPath: selectedSkillPath,
                fingerprint: fingerprint,
                checks: checks,
                quality: quality,
                impact: impact,
                security: securitySignal,
                tessl: cachedTessl,
                fleet: fleet
            )
            await onLocalEvidence(localDashboard)
        }
        let tessl = await tesslResult
        return makeDashboard(
            metadata: metadata,
            registryPath: registryPath,
            root: root,
            selectedSkillPath: selectedSkillPath,
            fingerprint: fingerprint,
            checks: checks,
            quality: quality,
            impact: impact,
            security: securitySignal,
            tessl: tessl,
            fleet: fleet
        )
    }

    private func makeDashboard(
        metadata: SkillMetadata,
        registryPath: String,
        root: URL,
        selectedSkillPath: String,
        fingerprint: String,
        checks: PipelineEvidenceLoader.LocalChecks,
        quality: MetricSignal,
        impact: MetricSignal,
        security: SecuritySignal,
        tessl: TesslSignal,
        fleet: FleetSignal
    ) -> SkillDashboard {
        let pipeline = Self.productionPipelineCandidate(
            root: root,
            selectedSkillPath: selectedSkillPath,
            evidenceFingerprint: fingerprint,
            checks: checks,
            tessl: tessl
        )
        return SkillDashboard(
            displayName: metadata.name,
            version: metadata.version,
            description: metadata.description,
            registryPath: registryPath,
            repoPath: root.path,
            installCommand: "tessl install \(registryPath)",
            localEvidenceCommand: Self.localEvidenceCommand(root: root, skillPath: selectedSkillPath),
            reviewedText: "Local SDK evidence",
            deltaText: tessl.ok ? "Tessl" : "Local SDK",
            quality: quality,
            impact: impact,
            security: security,
            tessl: tessl,
            fleet: fleet,
            pipeline: pipeline,
            refreshedAt: Date(),
            error: nil
        )
    }

    private static func pendingTesslSignal(registryPath: String) -> TesslSignal {
        TesslSignal(
            ok: false,
            cliAvailable: true,
            authenticated: false,
            displayStatus: "Refreshing",
            detail: "Refreshing the live Tessl registry observation; local evidence is current independently.",
            cliVersion: nil,
            registryScore: nil,
            registryVersion: nil,
            registryQualityScore: nil,
            registryImpactScore: nil,
            registrySecurityLabel: nil,
            registryEvalCount: nil,
            registryImprovementMultiplier: nil,
            registryVisibility: nil,
            recoveryCommand: "tessl search --type skills \(registryPath)"
        )
    }

    private static func canReuse(_ checks: PipelineEvidenceLoader.LocalChecks) -> Bool {
        [
            checks.strictAudit,
            checks.packageVerify,
            checks.securityRiskModes,
            checks.scenarioQuality,
            checks.scorerQuality,
            checks.scorerCalibration
        ].allSatisfy { $0.exitCode == 0 }
    }

    func loadSync() throws -> SkillDashboard {
        let root = try findRepoRoot()
        let selectedSkillPath = try findSelectedSkillPath(root: root)
        if selectedSkillPath.hasPrefix("/") {
            return try installedDashboard(root: root, skillPath: selectedSkillPath)
        }
        let metadata = try SkillMetadata.load(from: root.appendingPathComponent(selectedSkillPath))
        let registryPath = "jscraik/\(metadata.name)"
        let packageBuildCommand = Self.packageBuildCommand(for: selectedSkillPath)
        let strictAuditCommand = Self.strictAuditCommand(for: selectedSkillPath)
        let packageCommand = Self.packageCommand(for: selectedSkillPath)
        let impactCommand = Self.impactCommand(for: selectedSkillPath)
        let scorerQualityCommand = Self.scorerQualityCommand(for: selectedSkillPath)
        let scorerCalibrationCommand = Self.scorerCalibrationCommand(for: selectedSkillPath)
        let securityCommand = Self.securityCommand(for: selectedSkillPath)
        let boundEvidence = Self.collectEvidence(root: root, selectedSkillPath: selectedSkillPath) {
            PipelineEvidenceLoader.LocalChecks(
                packageBuild: Shell.run(packageBuildCommand, cwd: root, timeout: 45),
                strictAudit: Shell.run(strictAuditCommand, cwd: root, timeout: 45),
                packageVerify: Shell.run(packageCommand, cwd: root, timeout: 45),
                securityRiskModes: Shell.run(securityCommand, cwd: root, timeout: 45),
                scenarioQuality: Shell.run(impactCommand, cwd: root, timeout: 45),
                scorerQuality: Shell.run(scorerQualityCommand, cwd: root, timeout: 45),
                scorerCalibration: Shell.run(scorerCalibrationCommand, cwd: root, timeout: 45)
            )
        }
        let checks = boundEvidence.evidence
        let quality = qualitySignal(from: checks.packageVerify, root: root, command: packageCommand)
        let impact = impactSignal(from: checks.scenarioQuality, root: root, command: impactCommand)
        let security = securitySignal(from: checks.securityRiskModes, root: root, command: securityCommand)
        let tessl = tesslSignalSync(root: root, registryPath: registryPath)
        let pipeline = Self.productionPipelineCandidate(
            root: root,
            selectedSkillPath: selectedSkillPath,
            evidenceFingerprint: boundEvidence.candidateFingerprint,
            checks: checks,
            tessl: tessl
        )
        return SkillDashboard(
            displayName: metadata.name,
            version: metadata.version,
            description: metadata.description,
            registryPath: registryPath,
            repoPath: root.path,
            installCommand: "tessl install \(registryPath)",
            localEvidenceCommand: Self.localEvidenceCommand(root: root, skillPath: selectedSkillPath),
            reviewedText: "Local SDK evidence",
            deltaText: "Local SDK",
            quality: quality,
            impact: impact,
            security: security,
            tessl: tessl,
            fleet: fleetSignal(root: root, selectedSkillPath: selectedSkillPath),
            pipeline: pipeline,
            refreshedAt: Date(),
            error: nil
        )
    }

    static func pipelineCandidate(
        root: URL,
        selectedSkillPath: String,
        evidenceFingerprint: String,
        quality: MetricSignal,
        security: SecuritySignal,
        impact: MetricSignal = MetricSignal(
            score: nil,
            detail: "Scenario readiness unavailable.",
            source: "Local SDK scenario-quality",
            command: ""
        ),
        observedAt: Date = Date()
    ) -> PipelineCandidate {
        let governedInputs = governedInputURLs(root: root, selectedSkillPath: selectedSkillPath)
        let governedPaths = governedInputs.map {
            $0.path.replacingOccurrences(of: root.path + "/", with: "")
        }
        let identityCommand = copyCommand(root: root, command: Self.sdkStartCommand(for: selectedSkillPath))
        let packageCommand = copyCommand(root: root, command: Self.packageCommand(for: selectedSkillPath))
        let impactCommand = copyCommand(root: root, command: Self.impactCommand(for: selectedSkillPath))
        let securityCommand = copyCommand(root: root, command: Self.securityCommand(for: selectedSkillPath))
        guard !governedInputs.isEmpty,
              let fingerprint = PipelineCandidate.fingerprint(for: governedInputs, root: root) else {
            return .unproven(
                fingerprint: "unreadable-candidate",
                governedInputPaths: governedPaths,
                observedAt: observedAt,
                commands: [
                    .candidateBaseline: identityCommand,
                    .mechanicalValidation: packageCommand,
                    .securityReview: securityCommand,
                    .evalPreparation: impactCommand
                ]
            )
        }
        let mechanicalStatus: PipelineEvidenceStatus
        if quality.score == 100 {
            mechanicalStatus = .passed
        } else if quality.score != nil {
            mechanicalStatus = .reviewRequired
        } else {
            mechanicalStatus = .unproven
        }
        let preparationStatus: PipelineEvidenceStatus = impact.score == nil ? .unproven : .passed
        let securityStatus: PipelineEvidenceStatus
        switch security.disposition {
        case .passed: securityStatus = .passed
        case .advisory, .flagged: securityStatus = .reviewRequired
        case .failed: securityStatus = .blocked
        case .pending: securityStatus = .unproven
        }

        return PipelineCandidate(
            fingerprint: fingerprint,
            governedInputPaths: governedPaths,
            observedAt: observedAt,
            stageReceipts: [
                PipelineStageReceipt(
                    stage: .candidateBaseline,
                    candidateFingerprint: evidenceFingerprint,
                    evidenceStatus: .reviewRequired,
                    stageScore: nil,
                    command: identityCommand,
                    receiptPath: nil,
                    modelProfile: "local-identity",
                    observedAt: observedAt,
                    nextAction: "Canonical package digest missing"
                ),
                PipelineStageReceipt(
                    stage: .mechanicalValidation,
                    candidateFingerprint: evidenceFingerprint,
                    evidenceStatus: mechanicalStatus,
                    stageScore: quality.score == nil ? nil : 50,
                    command: packageCommand,
                    receiptPath: nil,
                    modelProfile: "local-package",
                    observedAt: quality.score == nil ? nil : observedAt,
                    nextAction: quality.score == 100
                        ? "Package verify passed · Strict audit missing"
                        : "Package verification unavailable · Strict audit missing"
                ),
                PipelineStageReceipt(
                    stage: .securityReview,
                    candidateFingerprint: evidenceFingerprint,
                    evidenceStatus: securityStatus,
                    stageScore: security.score,
                    command: securityCommand,
                    receiptPath: nil,
                    modelProfile: "local-security",
                    observedAt: security.score == nil ? nil : observedAt,
                    nextAction: security.score == nil
                        ? "Risk taxonomy unavailable · full receipt missing"
                        : "Risk taxonomy observed early · full receipt missing"
                ),
                PipelineStageReceipt(
                    stage: .evalPreparation,
                    candidateFingerprint: evidenceFingerprint,
                    evidenceStatus: preparationStatus,
                    stageScore: impact.score == nil ? nil : 50,
                    command: impactCommand,
                    receiptPath: nil,
                    modelProfile: "eval-preparation",
                    observedAt: impact.score == nil ? nil : observedAt,
                    nextAction: impact.score == nil
                        ? "Scenario readiness unavailable · scorer & calibration missing"
                        : "Scenario readiness \(impact.statusLabel) · scorer & calibration missing"
                ),
                unprovenReceipt(
                    .ossLocal,
                    fingerprint: fingerprint,
                    modelProfile: "oss-local",
                    nextAction: "Eval local profile · Unproven"
                ),
                unprovenReceipt(
                    .ossCloud,
                    fingerprint: fingerprint,
                    modelProfile: "oss-cloud",
                    nextAction: "Eval cloud profile · Same scenario IDs required"
                ),
                unprovenReceipt(
                    .tesslStaging,
                    fingerprint: fingerprint,
                    modelProfile: "tessl-staging",
                    nextAction: "Local proof · dry run · handoff"
                ),
                unprovenReceipt(
                    .tesslLiveRegistry,
                    fingerprint: fingerprint,
                    modelProfile: "tessl-live",
                    nextAction: "Publish receipt · registry visibility"
                ),
                unprovenReceipt(
                    .liveScoreAndRuntime,
                    fingerprint: fingerprint,
                    modelProfile: "live-runtime",
                    nextAction: "Installed digest · doctor · observed behavior"
                )
            ]
        )
    }

    static func productionPipelineCandidate(
        root: URL,
        selectedSkillPath: String,
        evidenceFingerprint: String,
        checks: PipelineEvidenceLoader.LocalChecks,
        tessl: TesslSignal,
        observedAt: Date = Date()
    ) -> PipelineCandidate {
        let governedInputs = governedInputURLs(root: root, selectedSkillPath: selectedSkillPath)
        let governedPaths = governedInputs.map {
            $0.path.replacingOccurrences(of: root.path + "/", with: "")
        }
        guard !governedInputs.isEmpty,
              let fingerprint = PipelineCandidate.fingerprint(for: governedInputs, root: root) else {
            return .unproven(fingerprint: "unreadable-candidate", governedInputPaths: governedPaths, observedAt: observedAt)
        }
        let evidence = PipelineEvidenceLoader(
            root: root,
            selectedSkillPath: selectedSkillPath,
            evidenceFingerprint: evidenceFingerprint,
            checks: checks,
            tessl: tessl,
            observedAt: observedAt
        )
        return PipelineCandidate(
            fingerprint: fingerprint,
            governedInputPaths: governedPaths,
            observedAt: observedAt,
            stageReceipts: evidence.stageReceipts()
        )
    }

    private static func unprovenReceipt(
        _ stage: PipelineStage,
        fingerprint: String,
        modelProfile: String,
        nextAction: String
    ) -> PipelineStageReceipt {
        PipelineStageReceipt(
            stage: stage,
            candidateFingerprint: fingerprint,
            evidenceStatus: .unproven,
            stageScore: nil,
            command: "",
            receiptPath: nil,
            modelProfile: modelProfile,
            observedAt: nil,
            nextAction: nextAction
        )
    }

    static func collectEvidence<Value>(
        root: URL,
        selectedSkillPath: String,
        _ collection: () throws -> Value
    ) rethrows -> CandidateEvidenceBinding<Value> {
        CandidateEvidenceBinding(
            candidateFingerprint: candidateFingerprint(root: root, selectedSkillPath: selectedSkillPath),
            evidence: try collection()
        )
    }

    private static func collectEvidenceAsync<Value>(
        root: URL,
        selectedSkillPath: String,
        _ collection: () async -> Value
    ) async -> CandidateEvidenceBinding<Value> {
        let fingerprint = candidateFingerprint(root: root, selectedSkillPath: selectedSkillPath)
        let evidence = await collection()
        return CandidateEvidenceBinding(
            candidateFingerprint: fingerprint,
            evidence: evidence
        )
    }

    private static func candidateFingerprint(root: URL, selectedSkillPath: String) -> String {
        PipelineCandidate.fingerprint(
            for: governedInputURLs(root: root, selectedSkillPath: selectedSkillPath),
            root: root
        ) ?? "unreadable-candidate"
    }

    private static func packageDigest(
        from result: CommandResult,
        selectedSkillPath: String
    ) -> String? {
        guard result.exitCode == 0,
              let payload = result.json,
              payload.string(at: ["status"]) == "success",
              payload.string(at: ["data", "skills_sdk_package_build", "status"]) == "built",
              payload.string(at: ["data", "skills_sdk_package_build", "canonical_source_path"]) == selectedSkillPath,
              payload.bool(at: ["data", "skills_sdk_package_build", "mutation_performed"]) == false,
              let digest = payload.string(at: ["data", "skills_sdk_package_build", "package_digest"]),
              digest.range(of: #"^sha256:[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return digest
    }

    private static func isContained(_ child: URL, beneath parent: URL) -> Bool {
        let parentPath = parent.path.hasSuffix("/") ? parent.path : parent.path + "/"
        return child.path == parent.path || child.path.hasPrefix(parentPath)
    }

    private static func governedInputURLs(root: URL, selectedSkillPath: String) -> [URL] {
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let skillsRoot = resolvedRoot.appendingPathComponent("Skills")
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let skillURL = resolvedRoot.appendingPathComponent(selectedSkillPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard isContained(skillURL, beneath: skillsRoot),
              FileManager.default.fileExists(atPath: skillURL.path) else { return [] }
        let skillDirectory = skillURL.deletingLastPathComponent()
        guard let enumerator = FileManager.default.enumerator(
            at: skillDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [skillURL] }
        let packageFiles = enumerator.compactMap { $0 as? URL }
            .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
            .filter { url in
                guard isContained(url, beneath: skillsRoot),
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                      values.isRegularFile == true else { return false }
                return url != skillURL
            }
        return ([skillURL] + packageFiles)
        .filter { FileManager.default.fileExists(atPath: $0.path) }
        .reduce(into: [URL]()) { result, url in
            if !result.contains(where: { $0.path == url.path }) { result.append(url) }
        }
        .sorted { $0.path < $1.path }
    }

    private func findRepoRoot() throws -> URL {
        if let explicit = environment["AGENT_SKILLS_ROOT"], !explicit.isEmpty {
            return URL(fileURLWithPath: explicit)
        }
        var candidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Skills/agent-ops/improve-agent-native/SKILL.md").path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        if !InstalledSkillDiscovery.paths(home: homeDirectory).isEmpty { return homeDirectory }
        throw SkillsBarError.missingRepoRoot
    }

    private func findSelectedSkillPath(root: URL) throws -> String {
        let rawPath = environment["AGENT_SKILL_PATH"]
            ?? environment["SELECTED_SKILL_PATH"]
            ?? storedSkillPath
            ?? InstalledSkillDiscovery.paths(home: homeDirectory).first
            ?? Self.defaultSkillPath
        let installedPaths = InstalledSkillDiscovery.paths(home: homeDirectory)
        if installedPaths.contains(rawPath) { return rawPath }
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let skillsRoot = resolvedRoot.appendingPathComponent("Skills")
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let candidateURL = rawPath.hasPrefix("/")
            ? URL(fileURLWithPath: rawPath)
            : resolvedRoot.appendingPathComponent(rawPath)
        let selectedURL = candidateURL.standardizedFileURL.resolvingSymlinksInPath()
        guard selectedURL.lastPathComponent == "SKILL.md",
              Self.isContained(selectedURL, beneath: skillsRoot),
              FileManager.default.fileExists(atPath: selectedURL.path) else {
            if let installed = installedPaths.first { return installed }
            let fallback = root.appendingPathComponent(Self.defaultSkillPath)
            guard FileManager.default.fileExists(atPath: fallback.path) else { throw SkillsBarError.missingRepoRoot }
            return Self.defaultSkillPath
        }
        let rootPrefix = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
        guard selectedURL.path.hasPrefix(rootPrefix) else { return Self.defaultSkillPath }
        return String(selectedURL.path.dropFirst(rootPrefix.count))
    }

    private func run(root: URL, command: String) async -> CommandResult {
        await Task.detached(priority: .utility) { Shell.run(command, cwd: root, timeout: 45) }.value
    }

    private func installedDashboard(root: URL, skillPath: String) throws -> SkillDashboard {
        let skillURL = URL(fileURLWithPath: skillPath)
        let metadata = try SkillMetadata.load(from: skillURL)
        let inspect = "sed -n '1,120p' \(Self.shellQuoted(skillPath))"
        let notice = "Installed copy found. Locate its checked source package to establish SDK evidence."
        var dashboard = SkillDashboard.placeholder
        dashboard.displayName = metadata.name
        dashboard.version = metadata.version
        dashboard.description = metadata.description
        dashboard.repoPath = root.path
        dashboard.registryPath = ""
        dashboard.installCommand = ""
        dashboard.localEvidenceCommand = inspect
        dashboard.reviewedText = "Installed skill inventory"
        dashboard.deltaText = "Installed copy"
        dashboard.quality = MetricSignal(score: nil, detail: notice, source: "Installed inventory", command: inspect)
        dashboard.impact = MetricSignal(score: nil, detail: notice, source: "Installed inventory", command: inspect)
        dashboard.security = SecuritySignal(score: nil, status: "Pending", detail: notice, sourceLabel: "Installed inventory", segmentCount: 0, inspectCommand: inspect)
        dashboard.tessl.displayStatus = "Not linked"
        dashboard.tessl.detail = "No registry identity established for this installed copy."
        dashboard.tessl.recoveryCommand = ""
        let paths = InstalledSkillDiscovery.paths(home: homeDirectory)
        dashboard.fleet = FleetSignal(
            skillCount: paths.count, groupCount: 0, largestGroupName: "installed", largestGroupCount: paths.count,
            metadataCount: 0, referencesCount: 0, evalsCount: 0,
            selectedSkillPath: skillPath, inventoryCommand: inspect
        )
        // A filesystem fingerprint distinguishes refreshes; it cannot clear a gate.
        let fingerprint = PipelineCandidate.fingerprint(for: [skillURL], root: skillURL.deletingLastPathComponent())
            ?? "unreadable-installed-copy"
        dashboard.pipeline = PipelineCandidate(
            fingerprint: fingerprint, governedInputPaths: [skillPath], observedAt: Date(),
            stageReceipts: PipelineStage.allCases.map { stage in
                PipelineStageReceipt(stage: stage, candidateFingerprint: fingerprint, evidenceStatus: .unproven,
                    stageScore: nil, command: inspect, receiptPath: nil, modelProfile: nil,
                    observedAt: nil, nextAction: notice)
            }
        )
        if let link = InstalledSourceEvidence.link(skill: skillURL, home: homeDirectory) {
            let observation = InstalledSourceEvidence.observe(link: link, skill: skillURL)
            let capture = observation.capture
            let boundFingerprint = capture.map { "sha256:" + $0.candidate.content_sha256 } ?? fingerprint
            dashboard.pipeline = PipelineCandidate(
                fingerprint: boundFingerprint, governedInputPaths: [skillPath], observedAt: Date(),
                stageReceipts: PipelineStage.allCases.map { stage in
                    let linked = stage == .candidateBaseline || stage == .mechanicalValidation
                    return PipelineStageReceipt(
                        stage: stage, candidateFingerprint: boundFingerprint,
                        evidenceStatus: stage == .candidateBaseline ? observation.identityStatus
                            : (stage == .mechanicalValidation ? observation.validationStatus : .unproven),
                        stageScore: nil, command: observation.command,
                        receiptPath: linked ? (observation.sourceReview != nil ? link.source_review_path : link.validation_path) : nil,
                        modelProfile: linked ? (observation.sourceReview != nil ? "skillsbar-source-review/v1" : (link.package_kind == "skill" ? "skills-sdk/runtime-copy-comparison/v1" : "skills-sdk/plugin-package-validation/v1")) : nil,
                        observedAt: linked && observation.status == .passed ? Date() : nil,
                        nextAction: linked
                            ? (stage == .candidateBaseline && capture != nil
                                ? (observation.sourceReview.map {
                                    "Exact SDK candidate binding verified · owner and maintainer: \($0.owner) · \($0.rights_basis). Supplied provenance recorded; \($0.revision_boundary)"
                                } ?? "SDK candidate binding verified against installed copy · provenance, rights and ownership evidence still required for Identity clearance")
                                : observation.detail + (observation.sourceReview.map {
                                    observation.validationApproved
                                        ? " Candidate-bound child content and plugin presentation checks passed; root documentation reviewed. Scorer calibration and evaluation remain separate."
                                        : " Source review finding: " + $0.validation_findings.joined(separator: " · ")
                                } ?? " Full Validation still requires applicable quality, reference and presentation evidence."))
                            : "No Skills SDK \(stage.title.lowercased()) receipt linked. Structural validation does not establish this proof."
                    )
                }
            )
            dashboard.localEvidenceCommand = observation.command
            dashboard.quality.detail = observation.detail
            dashboard.quality.source = link.package_kind == "skill" ? "Skills SDK standalone comparison" : "Skills SDK plugin structure"
            dashboard.quality.command = observation.command
            dashboard.security.detail = "No candidate-bound security and permission review is linked. Source binding and Validation do not establish Security."
            dashboard.security.sourceLabel = "Skills SDK security evidence required"
            dashboard.impact.detail = "No matched local or cloud evaluation evidence is linked for this candidate."
            dashboard.reviewedText = observation.status == .stale ? "Skills SDK source drift" : "Skills SDK checked source"
        }
        dashboard.refreshedAt = Date()
        // Registry observations are independent of installed-copy lifecycle proof.
        let requestedRegistryPath = "jscraik/\(metadata.name)"
        let registry = installedRegistryLookup?(root, requestedRegistryPath)
            ?? tesslSignalSync(root: root, registryPath: requestedRegistryPath)
        dashboard.tessl = registry
        if registry.registryVersion != nil || registry.registryScore != nil {
            dashboard.registryPath = requestedRegistryPath
        }
        return dashboard
    }

    private func fleetSignal(root: URL, selectedSkillPath: String) -> FleetSignal {
        let skillsRoot = root.appendingPathComponent("Skills")
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: skillsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return FleetSignal(
                skillCount: 0,
                groupCount: 0,
                largestGroupName: "missing",
                largestGroupCount: 0,
                metadataCount: 0,
                referencesCount: 0,
                evalsCount: 0,
                selectedSkillPath: selectedSkillPath,
                inventoryCommand: Self.copyCommand(root: root, command: Self.allSkillsInventoryCommand)
            )
        }

        var groups: [String: Int] = [:]
        var skillCount = 0
        var metadataCount = 0
        var referencesCount = 0
        var evalsCount = 0
        for case let url as URL in enumerator where url.lastPathComponent == "SKILL.md" {
            skillCount += 1
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if text.contains("\nmetadata:") || text.hasPrefix("metadata:") {
                metadataCount += 1
            }
            let referencesURL = url.deletingLastPathComponent().appendingPathComponent("references")
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: referencesURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                referencesCount += 1
                if fileManager.fileExists(atPath: referencesURL.appendingPathComponent("evals.yaml").path) {
                    evalsCount += 1
                }
            }
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            let parts = relative.split(separator: "/")
            let group = parts.dropFirst().first.map(String.init) ?? "unknown"
            groups[group, default: 0] += 1
        }
        let largest = groups.sorted { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key < rhs.key }
            return lhs.value > rhs.value
        }.first

        return FleetSignal(
            skillCount: skillCount,
            groupCount: groups.count,
            largestGroupName: largest?.key ?? "none",
            largestGroupCount: largest?.value ?? 0,
            metadataCount: metadataCount,
            referencesCount: referencesCount,
            evalsCount: evalsCount,
            selectedSkillPath: selectedSkillPath,
            inventoryCommand: Self.copyCommand(root: root, command: Self.allSkillsInventoryCommand)
        )
    }

    private func tesslSignal(root: URL, registryPath: String) async -> TesslSignal {
        await Task.detached(priority: .utility) {
            tesslSignalSync(root: root, registryPath: registryPath)
        }.value
    }

    private func tesslSignalSync(root: URL, registryPath: String) -> TesslSignal {
        if let fixture = tesslFixtureSignal(registryPath: registryPath) {
            return fixture
        }

        let tessl = Self.tesslCommand(environment: environment)
        let cachedRegistry = TesslRegistryCache().load(registryPath: registryPath)?.cachedSignal
        let cachedVersion = TesslSessionCache.shared.version(for: tessl) ?? cachedRegistry?.cliVersion
        let version: String
        if let cachedVersion {
            version = cachedVersion
        } else {
            let versionResult = Shell.run("\(tessl) --version", cwd: root, timeout: 5)
            guard versionResult.exitCode == 0 else {
                if let cached = TesslRegistryCache().load(registryPath: registryPath) {
                    return cached.cachedSignal
                }
                return TesslSignal(
                    ok: false,
                    cliAvailable: false,
                    authenticated: false,
                    displayStatus: "CLI missing",
                    detail: "Tessl CLI was not found on PATH.",
                    cliVersion: nil,
                    registryScore: nil,
                    registryVersion: nil,
                    registryQualityScore: nil,
                    registryImpactScore: nil,
                    registrySecurityLabel: nil,
                    registryEvalCount: nil,
                    registryImprovementMultiplier: nil,
                    registryVisibility: nil,
                    recoveryCommand: "tessl doctor"
                )
            }
            version = versionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            TesslSessionCache.shared.store(version: version, for: tessl)
        }

        let searchCommand = "\(tessl) search --json --type skills \(Self.shellQuoted(registryPath))"
        let search = Shell.run(searchCommand, cwd: root, timeout: 20)
        guard search.exitCode == 0 else {
            let cliMissing = search.exitCode == 127
                || search.combinedOutput.localizedCaseInsensitiveContains("not found")
            if cliMissing, let cachedRegistry {
                return cachedRegistry
            }
            let authExpired = search.combinedOutput.localizedCaseInsensitiveContains("401")
                || search.combinedOutput.localizedCaseInsensitiveContains("login")
                || search.combinedOutput.localizedCaseInsensitiveContains("auth")
            return TesslSignal(
                ok: false,
                cliAvailable: !cliMissing,
                authenticated: !cliMissing && !authExpired,
                displayStatus: cliMissing ? "CLI missing" : (authExpired ? "Auth expired" : "Search blocked"),
                detail: search.shortFailure,
                cliVersion: version.isEmpty ? nil : version,
                registryScore: nil,
                registryVersion: nil,
                registryQualityScore: nil,
                registryImpactScore: nil,
                registrySecurityLabel: nil,
                registryEvalCount: nil,
                registryImprovementMultiplier: nil,
                registryVisibility: nil,
                recoveryCommand: cliMissing
                    ? "tessl --version"
                    : (authExpired ? "tessl login" : "tessl search --type skills \(registryPath)")
            )
        }
        let metadata = TesslRegistryMetadata(payload: search.json, registryPath: registryPath)
        let detailVisibility: String?
        if metadata.visibility == nil {
            let detail = Shell.run("\(tessl) plugin info \(Self.shellQuoted(registryPath))", cwd: root, timeout: 20)
            detailVisibility = detail.exitCode == 0 ? Self.tesslVisibility(fromPluginInfo: detail.stdout) : nil
        } else {
            detailVisibility = nil
        }

        let signal = TesslSignal(
            ok: true,
            cliAvailable: true,
            authenticated: true,
            displayStatus: metadata.score == nil ? "Connected" : "Scored",
            detail: metadata.score.map { "Registry returned score \($0); local evidence remains separate." } ?? "Registry search returned metadata for this authenticated Tessl session.",
            cliVersion: version.isEmpty ? nil : version,
            registryScore: metadata.score,
            registryVersion: metadata.version,
            registryQualityScore: metadata.qualityScore,
            registryImpactScore: metadata.impactScore,
            registrySecurityLabel: metadata.securityLabel,
            registryEvalCount: metadata.evalCount,
            registryImprovementMultiplier: metadata.improvementMultiplier,
            registryVisibility: detailVisibility ?? metadata.visibility,
            dataOrigin: .liveCLI,
            recoveryCommand: "tessl install \(registryPath)"
        )
        TesslRegistryCache().save(registryPath: registryPath, signal: signal)
        return signal
    }

    func tesslFixtureSignal(registryPath: String) -> TesslSignal? {
        #if DEBUG
        guard environment["TESSL_REGISTRY_FIXTURE"] == "1"
                || environment["TESSL_REGISTRY_FIXTURE_SCORE"] != nil
                || environment["TESSL_REGISTRY_FIXTURE_MODE"] != nil else { return nil }
        let mode = environment["TESSL_REGISTRY_FIXTURE_MODE"] ?? "live"
        let rawScore = environment["TESSL_REGISTRY_FIXTURE_SCORE"]
        let score = rawScore.flatMap(Int.init).flatMap { (0...100).contains($0) ? $0 : nil }
        return TesslSignal(
            ok: mode != "cached",
            cliAvailable: mode != "cached",
            authenticated: mode != "cached",
            displayStatus: mode == "cached" ? "CLI unavailable" : (score == nil ? "Connected" : "Scored"),
            detail: mode == "cached"
                ? "The Tessl CLI is unavailable; showing the last known registry snapshot."
                : (score.map { "Fixture registry score \($0); local evidence remains separate." } ?? "Fixture registry metadata connected; local evidence remains separate."),
            cliVersion: mode == "cached" ? nil : (environment["TESSL_REGISTRY_FIXTURE_CLI_VERSION"] ?? "fixture"),
            registryScore: score,
            registryVersion: environment["TESSL_REGISTRY_FIXTURE_VERSION"],
            registryQualityScore: environment["TESSL_REGISTRY_FIXTURE_QUALITY"].flatMap(Int.init),
            registryImpactScore: environment["TESSL_REGISTRY_FIXTURE_IMPACT"].flatMap(Int.init),
            registrySecurityLabel: environment["TESSL_REGISTRY_FIXTURE_SECURITY"],
            registryEvalCount: environment["TESSL_REGISTRY_FIXTURE_EVALS"].flatMap(Int.init),
            registryImprovementMultiplier: environment["TESSL_REGISTRY_FIXTURE_MULTIPLIER"].flatMap(Double.init),
            registryVisibility: environment["TESSL_REGISTRY_FIXTURE_VISIBILITY"] ?? "Private",
            dataOrigin: .fixture,
            recoveryCommand: "tessl install \(registryPath)"
        )
        #else
        return nil
        #endif
    }

    private func qualitySignal(from result: CommandResult, root: URL, command rawCommand: String) -> MetricSignal {
        let command = Self.copyCommand(root: root, command: rawCommand)
        guard result.exitCode == 0, let payload = result.json else {
            return MetricSignal(
                score: nil,
                detail: "Blocked: \(result.shortFailure)",
                source: "Local SDK package verify",
                command: command
            )
        }
        let status = payload.firstString(for: ["status"]) ?? "unknown"
        return MetricSignal(
            score: status == "success" ? 100 : 70,
            detail: "Package verify reported \(status).",
            source: "Local SDK package verify",
            command: command
        )
    }

    private func impactSignal(from result: CommandResult, root: URL, command rawCommand: String) -> MetricSignal {
        let command = Self.copyCommand(root: root, command: rawCommand)
        guard result.exitCode == 0, let payload = result.json else {
            return MetricSignal(
                score: nil,
                detail: "Blocked: \(result.shortFailure)",
                source: "Local SDK scenario-quality",
                command: command
            )
        }
        let total = payload.firstInt(for: ["scenario_count", "case_count", "total"])
        let ready = payload.firstInt(for: ["promotion_ready_count", "passed_count", "ready_count"])
        if let total, let ready, total > 0 {
            let score = Int((Double(ready) / Double(total) * 100.0).rounded())
            return MetricSignal(
                score: score,
                detail: "\(ready)/\(total) eval scenarios available.",
                source: "Local SDK scenario-quality",
                command: command,
                statusOverride: "\(ready)/\(total)"
            )
        }
        let status = payload.firstString(for: ["status"]) ?? "success"
        return MetricSignal(
            score: nil,
            detail: "Inspect: scenario-quality returned \(status), but count fields were unavailable.",
            source: "Local SDK scenario-quality",
            command: command
        )
    }

    private func securitySignal(from result: CommandResult, root: URL, command rawCommand: String) -> SecuritySignal {
        let inspectCommand = Self.copyCommand(root: root, command: rawCommand)
        guard result.exitCode == 0, let payload = result.json else {
            return SecuritySignal(
                score: nil,
                status: "Pending",
                detail: "Blocked: \(result.shortFailure)",
                sourceLabel: "Local SDK",
                segmentCount: 0,
                inspectCommand: inspectCommand
            )
        }
        let receiptPath = ["data", "skills_sdk_risk_mode_taxonomy", "receipt"]
        let status = payload.string(at: receiptPath + ["status"]) ?? payload.firstString(for: ["status"]) ?? "success"
        let detectedModes = Set(payload.stringArray(at: receiptPath + ["detected_modes"]))
        let detectedRows = payload.arrayOfDictionaries(at: receiptPath + ["mode_results"]).filter { row in
            guard (row["status"] as? String) == "detected" else { return false }
            guard !detectedModes.isEmpty, let mode = row["mode"] as? String else { return true }
            return detectedModes.contains(mode)
        }
        let severities = detectedRows.compactMap { $0["severity"] as? String }
        if !detectedRows.isEmpty {
            let score = securityScore(for: severities)
            let detail = "\(detectedRows.count) risk modes: \(severitySummary(for: severities))."
            return SecuritySignal(
                score: score,
                status: "Flagged",
                detail: detail,
                sourceLabel: "Local SDK risk-modes",
                segmentCount: min(max(detectedRows.count, 1), 5),
                inspectCommand: inspectCommand
            )
        }
        let detail = "No risk mode signals detected."
        return SecuritySignal(
            score: status == "success" ? 100 : 70,
            status: status == "success" ? "Passed" : status.capitalized,
            detail: detail,
            sourceLabel: "Local SDK risk-modes",
            segmentCount: status == "success" ? 4 : 2,
            inspectCommand: inspectCommand
        )
    }

    private func securityScore(for severities: [String]) -> Int {
        let penalty = severities.reduce(0) { total, severity in
            switch severity.lowercased() {
            case "critical": return total + 35
            case "high": return total + 15
            case "medium": return total + 8
            case "low": return total + 4
            default: return total + 10
            }
        }
        return max(0, 100 - penalty)
    }

    private func severitySummary(for severities: [String]) -> String {
        let grouped = Dictionary(grouping: severities.map { $0.lowercased() }, by: { $0 })
        let order = ["critical", "high", "medium", "low"]
        let parts = order.compactMap { severity -> String? in
            guard let count = grouped[severity]?.count, count > 0 else { return nil }
            return "\(count) \(severity)"
        }
        return parts.isEmpty ? "severity unavailable" : parts.joined(separator: ", ")
    }
}

struct SkillMetadata {
    var name: String
    var version: String
    var description: String

    static func load(from url: URL) throws -> SkillMetadata {
        let text = try String(contentsOf: url, encoding: .utf8)
        return SkillMetadata(
            name: value("name", in: text) ?? "improve-agent-native",
            version: metadataVersion(in: text) ?? "unknown",
            description: value("description", in: text) ?? "No description found."
        )
    }

    private static func value(_ key: String, in text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            if raw.hasPrefix("\(key):") {
                return clean(raw.replacingOccurrences(of: "\(key):", with: ""))
            }
        }
        return nil
    }

    private static func metadataVersion(in text: String) -> String? {
        var inMetadata = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            if raw == "metadata:" { inMetadata = true; continue }
            if inMetadata, raw.hasPrefix("  version:") {
                return clean(raw.replacingOccurrences(of: "  version:", with: ""))
            }
            if inMetadata, !raw.hasPrefix(" ") { inMetadata = false }
        }
        return nil
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}

enum SkillsBarError: LocalizedError {
    case missingRepoRoot
    var errorDescription: String? {
        "Could not find agent-skills data repo. Set AGENT_SKILLS_ROOT."
    }
}
