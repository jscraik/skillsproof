import Foundation
import SwiftUI

@main
struct SkillsBarApp: App {
    @StateObject private var model = DashboardModel()

    init() {
        if CommandLine.arguments.contains("--check-release-safety") {
            #if DEBUG
            Foundation.exit(1)
            #else
            let safe = !DashboardDataSource().usesReviewFixture
                && !SkillsBarDemoMode.isEnabled()
                && DashboardLoader().tesslFixtureSignal(registryPath: "release-check") == nil
                && SnapshotRequest.outputPath == nil
                && AppResources.url(forResource: "TesslWordmark", withExtension: "png") != nil
                && AppResources.url(forResource: "verify_validation_receipts", withExtension: "py") != nil
            print(safe ? "Release safety checks passed" : "Release safety checks failed")
            Foundation.exit(safe ? 0 : 1)
            #endif
        }
        if let outputPath = SnapshotRequest.outputPath {
            SnapshotRenderer.render(
                to: URL(fileURLWithPath: outputPath),
                configuration: SnapshotRequest.configuration()
            )
            Foundation.exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView(model: model)
                .frame(width: MenuBarTemplateMetrics.width, height: MenuBarTemplateMetrics.height)
        } label: {
            SkillsMenuBarIconView(status: model.menuBarStatus)
                .equatable()
                .accessibilityLabel("\(model.menuTitle), \(model.menuBarStatus.label)")
        }
        .menuBarExtraStyle(.window)
    }
}
