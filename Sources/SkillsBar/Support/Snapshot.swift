import AppKit
import Foundation
import SwiftUI

enum SnapshotRequest {
    static var outputPath: String? {
        #if DEBUG
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) else {
            return nil
        }
        return args[index + 1]
        #else
        return nil
        #endif
    }

    static func configuration(arguments: [String] = CommandLine.arguments) -> SnapshotConfiguration {
        SnapshotConfiguration(colorScheme: arguments.contains("--snapshot-dark") ? .dark : nil)
    }
}

struct SnapshotConfiguration {
    var dynamicTypeSize: DynamicTypeSize = .large
    var reduceTransparency = false
    var increasedContrast = false
    /// `nil` inherits the host appearance. Snapshot tests set an explicit
    /// scheme so light and dark rendering stay independently verifiable.
    var colorScheme: ColorScheme? = nil

    static let `default` = SnapshotConfiguration()
}

private struct ReduceTransparencyOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

private struct IncreasedContrastOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

private struct SnapshotModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var skillsBarReduceTransparencyOverride: Bool? {
        get { self[ReduceTransparencyOverrideKey.self] }
        set { self[ReduceTransparencyOverrideKey.self] = newValue }
    }

    var skillsBarIncreasedContrastOverride: Bool? {
        get { self[IncreasedContrastOverrideKey.self] }
        set { self[IncreasedContrastOverrideKey.self] = newValue }
    }

    var skillsBarSnapshotMode: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}

enum SnapshotRenderer {
    /// Visual comparison only; never used by the live evidence loader.
    static var focusReferenceDashboard: SkillDashboard {
        var dashboard = SkillDashboard.reviewNoCLIFixture
        let observed = Date().addingTimeInterval(-180)
        let fingerprint = "focus-reference-only"
        dashboard.pipeline = PipelineCandidate(
            fingerprint: fingerprint,
            governedInputPaths: [],
            observedAt: observed,
            stageReceipts: PipelineStage.allCases.map { stage in
                PipelineStageReceipt(
                    stage: stage,
                    candidateFingerprint: fingerprint,
                    evidenceStatus: stage.number < 3 ? .passed : (stage.number == 3 ? .reviewRequired : (stage.number == 4 ? .held : .unproven)),
                    stageScore: stage.number < 3 ? 100 : nil,
                    command: "skills security risk-modes",
                    receiptPath: nil,
                    modelProfile: nil,
                    observedAt: observed,
                    nextAction: "Review findings · full governed security receipt is missing or malformed"
                )
            }
        )
        dashboard.tessl.registryScore = nil
        dashboard.tessl.registryVersion = nil
        dashboard.tessl.registryQualityScore = nil
        dashboard.tessl.registryImpactScore = nil
        dashboard.tessl.registrySecurityLabel = nil
        dashboard.tessl.dataOrigin = .unavailable
        dashboard.refreshedAt = observed
        return dashboard
    }

    @MainActor
    static func render(to outputURL: URL, configuration: SnapshotConfiguration = .default) {
        do {
            _ = NSApplication.shared
            let dashboard = CommandLine.arguments.contains("--snapshot-focus-reference")
                ? focusReferenceDashboard : try DashboardDataSource().loadSync()
            try render(dashboard: dashboard, configuration: configuration, to: outputURL)
            print("Wrote snapshot \(outputURL.path)")
        } catch {
            fputs("Snapshot failed: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }

    @MainActor
    static func render(dashboard: SkillDashboard, to outputURL: URL) throws {
        try render(dashboard: dashboard, configuration: .default, to: outputURL)
    }

    @MainActor
    static func render(
        dashboard: SkillDashboard,
        configuration: SnapshotConfiguration,
        to outputURL: URL
    ) throws {
        // Preserve fixture selection in snapshot mode so a review fixture cannot
        // silently become a live dashboard during model construction.
        let source = DashboardDataSource()
        let model = DashboardModel(dashboard: dashboard, autorefresh: false, source: source)
        let view = DashboardView(model: model)
            .frame(width: MenuBarTemplateMetrics.width, height: MenuBarTemplateMetrics.preferredHeight)
            .environment(\.dynamicTypeSize, configuration.dynamicTypeSize)
            .environment(\.skillsBarReduceTransparencyOverride, configuration.reduceTransparency)
            .environment(\.skillsBarIncreasedContrastOverride, configuration.increasedContrast)
            .environment(\.skillsBarSnapshotMode, true)
            .preferredColorScheme(configuration.colorScheme)
        let hostingView = NSHostingView(rootView: view)
        switch configuration.colorScheme {
        case .light:
            hostingView.appearance = NSAppearance(named: .aqua)
        case .dark:
            hostingView.appearance = NSAppearance(named: .darkAqua)
        case nil:
            break
        @unknown default:
            break
        }
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: MenuBarTemplateMetrics.width, height: MenuBarTemplateMetrics.preferredHeight)
        )
        hostingView.layoutSubtreeIfNeeded()
        // AppKit material layers can complete after the first layout pass in a
        // headless process. Give them a bounded settle window before capture.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.20))
        hostingView.layoutSubtreeIfNeeded()
        hostingView.needsDisplay = true
        hostingView.displayIfNeeded()
        // Keep the regression canvas in points, independent of the attached
        // display's Retina scale, so local and headless renders agree.
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(hostingView.bounds.width),
            pixelsHigh: Int(hostingView.bounds.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw SnapshotError.bitmapUnavailable
        }
        bitmap.size = hostingView.bounds.size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.pngUnavailable
        }
        try data.write(to: outputURL)
    }
}

enum SnapshotError: LocalizedError {
    case bitmapUnavailable
    case pngUnavailable

    var errorDescription: String? {
        switch self {
        case .bitmapUnavailable: return "Could not allocate snapshot bitmap."
        case .pngUnavailable: return "Could not encode snapshot PNG."
        }
    }
}
