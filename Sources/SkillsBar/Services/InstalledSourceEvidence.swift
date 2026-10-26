import Foundation
import CryptoKit
import SkillsBarCore

/// Presentation adapter only. Skills SDK owns capture and evidence verification.
enum InstalledSourceEvidence {
    struct Link: Codable {
        let schema_version: String
        let installed_root: String
        let source_root: String
        let source_revision: String
        let sdk_executable: String
        let validation_path: String
        let validation_sha256: String
        var source_review_path: String? = nil
        var source_review_sha256: String? = nil
        var package_kind: String? = nil
    }

    struct Capture: Decodable {
        struct Candidate: Codable, Equatable {
            let schema_version: String
            let package_id: String
            let source_revision: String
            let content_sha256: String
        }
        struct Manifest: Decodable, Equatable {
            let name: String
            let version: String
        }
        struct Skill: Decodable {
            struct Validation: Decodable { let candidate: Candidate }
            let path: String
            let validation: Validation?
        }
        let schema_version: String
        let status: String
        let candidate: Candidate
        let manifest: Manifest
        let mode_manifest_sha256: String
        let mutation_performed: Bool
        let execution_authorized: Bool
        let release_ready: Bool
        let skills: [Skill]
    }

    struct Observation {
        let status: PipelineEvidenceStatus
        let detail: String
        let capture: Capture?
        let command: String
        let link: Link
        var sourceReview: SourceReview? = nil
        var validationApproved = false

        /// A portable structural capture is partial evidence for the full lifecycle gates.
        var lifecycleStatus: PipelineEvidenceStatus {
            status == .passed ? .reviewRequired : status
        }

        var identityStatus: PipelineEvidenceStatus {
            status == .passed && sourceReview != nil ? .passed : lifecycleStatus
        }

        var validationStatus: PipelineEvidenceStatus {
            guard status == .passed else { return lifecycleStatus }
            if sourceReview?.validation_findings.isEmpty == false { return .blocked }
            return validationApproved ? .passed : lifecycleStatus
        }
    }

    /// Supplied source review, not an SDK aggregate result or authenticated rights proof.
    struct SourceReview: Codable {
        let schema_version: String
        let candidate: Capture.Candidate
        let mode_manifest_sha256: String
        let owner: String
        let maintainer: String
        let rights_basis: String
        let source_reference: String
        let revision_boundary: String
        let reviewer: String
        let evidence: [Evidence]
        let validation_findings: [String]
        var validation_proof: ValidationProof? = nil

        struct Evidence: Codable {
            let path: String
            let sha256: String
        }

        struct ValidationProof: Codable {
            let rationale: String
            let presentation: Evidence
            let content_reviews: [Evidence]
        }
    }

    static func directory(home: URL) -> URL {
        home.appendingPathComponent(".codex/usage-data/skillsbar/source-links")
    }

    static func link(skill: URL, home: URL) -> Link? {
        let selected = skill.standardizedFileURL.resolvingSymlinksInPath()
        // Home skill roots and plugin children both contain /skills/name/SKILL.md.
        // Prefer an explicitly linked standalone root before the containing plugin.
        if let standalone = readLink(root: selected.deletingLastPathComponent(), home: home, kind: "skill") {
            return standalone
        }
        guard selected.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "skills" else { return nil }
        return readLink(root: selected.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(), home: home, kind: nil)
    }

    private static func readLink(root: URL, home: URL, kind: String?) -> Link? {
        let key = SHA256.hash(data: Data(root.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let url = directory(home: home).appendingPathComponent(key + ".json")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 65_536,
              let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(Link.self, from: data),
              record.schema_version == "skillsbar-source-link/v1",
              record.package_kind == kind,
              [record.installed_root, record.source_root, record.sdk_executable, record.validation_path].allSatisfy({ $0.hasPrefix("/") }),
              URL(fileURLWithPath: record.installed_root).standardizedFileURL.resolvingSymlinksInPath() == root,
              record.source_revision.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
              isDigest(record.validation_sha256) else { return nil }
        return record
    }

    static func watchDirectories(skill: URL, home: URL) -> [URL] {
        guard let record = link(skill: skill, home: home) else { return [directory(home: home)] }
        var directories = [directory(home: home), URL(fileURLWithPath: record.source_root), URL(fileURLWithPath: record.installed_root)]
        if let path = record.source_review_path {
            directories.append(URL(fileURLWithPath: path).deletingLastPathComponent())
        }
        return directories
    }

    static func observe(
        link: Link, skill: URL,
        run: (String, URL) -> CommandResult = { Shell.run($0, cwd: $1, timeout: 45) }
    ) -> Observation {
        let source = URL(fileURLWithPath: link.source_root)
        let installed = URL(fileURLWithPath: link.installed_root)
        if link.package_kind == "skill" {
            return observeSkill(link: link, skill: skill, source: source, installed: installed, run: run)
        }
        let policy = " --source-revision \(quote(link.source_revision)) --require-version --require-description --json --robot --verify-evidence \(quote(link.validation_path))"
        let command: (URL) -> String = { root in
            "\(quote(link.sdk_executable)) validate-plugin \(quote(root.path))" + policy
        }
        let sourceCommand = command(source)
        func result(_ status: PipelineEvidenceStatus, _ detail: String, _ capture: Capture? = nil) -> Observation {
            Observation(status: status, detail: detail, capture: capture, command: sourceCommand, link: link)
        }
        guard captureHash(link.validation_path) == link.validation_sha256 else {
            return result(.stale, "Linked SDK capture is missing or changed; relink checked source")
        }
        let checkedSource = run(sourceCommand, source)
        let checkedInstalled = run(command(installed), installed)
        guard checkedSource.exitCode == 0, checkedInstalled.exitCode == 0,
              let sourceData = checkedSource.stdout.data(using: .utf8),
              let installedData = checkedInstalled.stdout.data(using: .utf8),
              let sourceCapture = try? JSONDecoder().decode(Capture.self, from: sourceData),
              let runtimeCapture = try? JSONDecoder().decode(Capture.self, from: installedData),
              valid(sourceCapture, revision: link.source_revision), valid(runtimeCapture, revision: link.source_revision),
              sourceCapture.candidate == runtimeCapture.candidate,
              sourceCapture.manifest == runtimeCapture.manifest,
              sourceCapture.mode_manifest_sha256 == runtimeCapture.mode_manifest_sha256,
              sourceCapture.skills.map(\.path).sorted() == runtimeCapture.skills.map(\.path).sorted(),
              sourceCapture.skills.contains(where: {
                  installed.appendingPathComponent($0.path + "/SKILL.md").standardizedFileURL == skill.standardizedFileURL.resolvingSymlinksInPath()
              }),
              captureHash(link.validation_path) == link.validation_sha256 else {
            return result(.stale, "Skills SDK could not verify source and installed copy against the linked capture; inspect or relink")
        }
        var observation = result(.passed, "Skills SDK structural validation passed · exact installed bytes and permissions match checked source · \(sourceCapture.skills.count) skill checked. Security and eval proof remain separate.", sourceCapture)
        if link.source_review_path != nil || link.source_review_sha256 != nil {
            guard let path = link.source_review_path, let digest = link.source_review_sha256,
                  path.hasPrefix("/"), isDigest(digest), captureHash(path) == digest,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let review = try? JSONDecoder().decode(SourceReview.self, from: data),
                  review.schema_version == "skillsbar-source-review/v1",
                  review.candidate == sourceCapture.candidate,
                  review.mode_manifest_sha256 == sourceCapture.mode_manifest_sha256,
                  [review.owner, review.maintainer, review.rights_basis, review.source_reference,
                   review.revision_boundary, review.reviewer].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  !review.evidence.isEmpty,
                  review.evidence.allSatisfy({ $0.path.hasPrefix("/") && isDigest($0.sha256) && captureHash($0.path) == $0.sha256 }),
                  captureHash(path) == digest else {
                return result(.stale, "Linked source review is invalid, changed or belongs to another candidate; renew the source review", sourceCapture)
            }
            observation.sourceReview = review
            if let proof = review.validation_proof {
                guard validValidationProof(proof, review: review, capture: sourceCapture),
                      let bridge = AppResources.url(forResource: "verify_validation_receipts", withExtension: "py") else {
                    return result(.stale, "Validation evidence is incomplete or belongs to another candidate; renew the source review", sourceCapture)
                }
                let python = URL(fileURLWithPath: link.sdk_executable).deletingLastPathComponent().appendingPathComponent("python")
                let arguments = [python.path, "-I", bridge.path, source.path, link.source_revision, proof.presentation.path]
                    + proof.content_reviews.map(\.path)
                let verified = run(arguments.map(quote).joined(separator: " "), source)
                guard verified.exitCode == 0, verified.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "pass",
                      captureHash(path) == digest,
                      review.evidence.allSatisfy({ captureHash($0.path) == $0.sha256 }) else {
                    return result(.stale, "Skills SDK rejected complete retained validation evidence or fresh reassessment; renew the source review", sourceCapture)
                }
                observation.validationApproved = true
            }
        }
        return observation
    }

    /// Standalone comparison is partial structure/binding evidence, never whole-plugin clearance.
    private static func observeSkill(
        link: Link, skill: URL, source: URL, installed: URL,
        run: (String, URL) -> CommandResult
    ) -> Observation {
        let command = [link.sdk_executable, "compare-copy", source.path, installed.path,
                       "--source-revision", link.source_revision, "--json"].map(quote).joined(separator: " ")
        func result(_ status: PipelineEvidenceStatus, _ detail: String) -> Observation {
            Observation(status: status, detail: detail, capture: nil, command: command, link: link)
        }
        guard installed.appendingPathComponent("SKILL.md").standardizedFileURL == skill.standardizedFileURL.resolvingSymlinksInPath(),
              captureHash(link.validation_path) == link.validation_sha256,
              let retainedData = try? Data(contentsOf: URL(fileURLWithPath: link.validation_path)),
              let retained = try? JSONSerialization.jsonObject(with: retainedData) as? NSDictionary else {
            return result(.stale, "Linked standalone SDK comparison is missing or changed; relink checked source")
        }
        let fresh = run(command, source)
        guard [0, 2].contains(fresh.exitCode), let data = fresh.stdout.data(using: .utf8),
              let current = try? JSONSerialization.jsonObject(with: data) as? NSDictionary,
              current == retained,
              current["schema_version"] as? String == "runtime-copy-comparison/v1",
              captureHash(link.validation_path) == link.validation_sha256 else {
            return result(.stale, "Skills SDK comparison changed or could not run; refresh the linked standalone receipts")
        }
        let paths = current["different_paths"] as? [String] ?? []
        if fresh.exitCode == 2, current["status"] as? String == "drift", !paths.isEmpty {
            return result(.stale, "SDK source/runtime drift: " + paths.joined(separator: ", ")
                + ". Source receipts cannot clear this installed candidate. Inspect the comparison receipt; source and runtime validation are recorded separately.")
        }
        guard fresh.exitCode == 0, current["status"] as? String == "pass", paths.isEmpty else {
            return result(.blocked, "Skills SDK did not establish an exact standalone source/runtime match; inspect linked receipts")
        }
        return result(.reviewRequired, "SDK standalone source/runtime bytes match. Full managed Identity and Validation still require provenance, ownership and plugin-level evidence; other gates require their own receipts.")
    }

    private struct ContentReceipt: Decodable {
        let schema_version: String
        let status: String
        let candidate: Capture.Candidate
        let mutation_performed: Bool
        let promotion_authorized: Bool
    }

    private struct PresentationReceipt: Decodable {
        let schema_version: String
        let status: String
        let candidate: Capture.Candidate
        let mode_manifest_sha256: String
        let mutation_performed: Bool
        let execution_authorized: Bool
        let release_ready: Bool
    }

    private static func validValidationProof(_ proof: SourceReview.ValidationProof, review: SourceReview, capture: Capture) -> Bool {
        func read<T: Decodable>(_ evidence: SourceReview.Evidence, as type: T.Type) -> T? {
            guard review.evidence.contains(where: { $0.path == evidence.path && $0.sha256 == evidence.sha256 }),
                  captureHash(evidence.path) == evidence.sha256,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: evidence.path)) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
        guard !proof.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              review.validation_findings.isEmpty,
              let presentation = read(proof.presentation, as: PresentationReceipt.self),
              presentation.schema_version == "plugin-presentation-check/v1", presentation.status == "pass",
              presentation.candidate == capture.candidate,
              presentation.mode_manifest_sha256 == capture.mode_manifest_sha256,
              !presentation.mutation_performed, !presentation.execution_authorized, !presentation.release_ready,
              proof.content_reviews.count == capture.skills.count else { return false }
        var remaining = capture.skills.compactMap { $0.validation?.candidate }
        guard remaining.count == capture.skills.count else { return false }
        for evidence in proof.content_reviews {
            guard let content = read(evidence, as: ContentReceipt.self),
                  content.schema_version == "content-review/v1", content.status == "pass",
                  !content.mutation_performed, !content.promotion_authorized,
                  let index = remaining.firstIndex(of: content.candidate) else { return false }
            remaining.remove(at: index)
        }
        return remaining.isEmpty
    }

    private static func valid(_ capture: Capture, revision: String) -> Bool {
        capture.schema_version == "plugin-package-validation/v1" && capture.status == "pass"
            && capture.candidate.schema_version == "package-candidate/v1"
            && capture.candidate.source_revision == revision && isDigest(capture.candidate.content_sha256)
            && isDigest(capture.mode_manifest_sha256) && !capture.mutation_performed
            && !capture.execution_authorized && !capture.release_ready
    }

    private static func captureHash(_ path: String) -> String? {
        guard let size = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 16 * 1024 * 1024, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func isDigest(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    private static func quote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
