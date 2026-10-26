import AppKit
import SwiftUI

/// Native adoption of Guided evidence. All content comes from the live dashboard.
struct PrototypePopover: View {
    let dashboard: SkillDashboard
    let isRefreshing: Bool
    let isFixture: Bool
    let paths: [String]
    let selectedPath: String
    let pinned: Bool
    let onSelect: ((String) -> Void)?
    let onRefresh: (() -> Void)?
    @StateObject private var navigation: FocusNavigatorModel
    @State private var detail = false
    @State private var choosing = false

    init(dashboard: SkillDashboard, isRefreshing: Bool, isFixture: Bool,
         paths: [String], selectedPath: String, pinned: Bool,
         onSelect: ((String) -> Void)?, onRefresh: (() -> Void)?) {
        self.dashboard = dashboard
        self.isRefreshing = isRefreshing
        self.isFixture = isFixture
        self.paths = paths
        self.selectedPath = selectedPath
        self.pinned = pinned
        self.onSelect = onSelect
        self.onRefresh = onRefresh
        _navigation = StateObject(wrappedValue: FocusNavigatorModel(candidate: dashboard.pipeline))
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 4) {
                ReleaseHeader(dashboard: dashboard, isRefreshing: isRefreshing, isFixture: isFixture) {
                    Menu {
                        Button("Search skills…") { choosing = true }
                        Divider()
                        ReleaseUtilityActions(dashboard: dashboard)
                        Button("Close popover") { NSApp.keyWindow?.orderOut(nil) }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 36, height: 36)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .frame(width: 36, height: 36)
                    .background(.primary.opacity(0.06), in: Circle())
                    .accessibilityLabel("More SkillsProof actions")
                }
                Divider()
                navigationBar
                Divider()
                if choosing {
                    SkillSearchChooser(paths: paths, selectedPath: selectedPath, pinned: pinned || onSelect == nil) { path in
                        onSelect?(path)
                        choosing = false
                        detail = false
                    }
                    .frame(maxHeight: .infinity)
                    .layoutPriority(1)
                } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Color.clear.frame(height: 0).id("top")
                            if detail, let receipt = navigation.receipt(in: dashboard.pipeline) {
                                SelectedStageDetail(receipt: receipt, activeStage: dashboard.pipeline.activeReceipt?.stage,
                                                    stageCount: 9, securityBadge: dashboard.security.severityLine)
                                    .id(receipt.stage)
                            } else {
                                PipelineStageGrid(candidate: dashboard.pipeline, selection: navigation) { detail = true }
                                Text(dashboard.pipeline.orderedReceipts.statusSummary)
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }.padding(.trailing, 2)
                    }
                    .onChange(of: navigation.selectedStage) { _, _ in proxy.scrollTo("top", anchor: .top) }
                    .onChange(of: detail) { _, _ in proxy.scrollTo("top", anchor: .top) }
                    .onChange(of: choosing) { _, _ in proxy.scrollTo("top", anchor: .top) }
                }
                .frame(maxHeight: .infinity)
                .layoutPriority(1)
                }
                PrototypeRegistryCard(dashboard: dashboard, compact: geometry.size.height < 500)
                Divider()
                ReleaseFooter(dashboard: dashboard, isRefreshing: isRefreshing, onRefresh: onRefresh)
            }
        }
        .onChange(of: dashboard.pipeline) { previous, updated in
            navigation.reconcile(updated)
            if previous.fingerprint != updated.fingerprint { detail = false }
        }
        .onExitCommand {
            if choosing || detail {
                choosing = false
                detail = false
            } else {
                NSApp.keyWindow?.orderOut(nil)
            }
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 8) {
            if choosing || detail {
                Button { choosing = false; detail = false } label: {
                    Label("All gates", systemImage: "chevron.left")
                }.buttonStyle(.plain)
            } else {
                Text("Verification gates").font(.system(size: 16, weight: .medium))
            }
            Spacer()
            if detail && !choosing {
                Button { navigation.step(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(navigation.selectedStage.number == 1).accessibilityLabel("Previous gate")
                Text("\(navigation.selectedStage.number) / 9 · \(navigation.selectedStage.compactTitle)").monospacedDigit().font(.caption)
                Button { navigation.step(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(navigation.selectedStage.number == 9).accessibilityLabel("Next gate")
            } else if !choosing {
                Button { choosing = true } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search skills")
            }
        }.frame(minHeight: 28)
    }
}

extension Array where Element == PipelineStageReceipt {
    var statusSummary: String {
        let labels: [(PipelineEvidenceStatus, String)] = [(.passed, "passed"), (.reviewRequired, "needs review"), (.blocked, "blocked"), (.stale, "stale")]
        var parts = labels.compactMap { status, label -> String? in
            let count = filter { $0.evidenceStatus == status }.count
            return count == 0 ? nil : "\(count) \(label)"
        }
        let awaiting = filter { $0.evidenceStatus == .held || $0.evidenceStatus == .unproven }.count
        if awaiting > 0 { parts.append("\(awaiting) awaiting proof") }
        return parts.joined(separator: " · ")
    }
}

enum SkillSearch {
    static func matches(_ path: String, query: String) -> Bool {
        query.split(whereSeparator: \.isWhitespace).allSatisfy {
            (InstalledSkillDiscovery.displayName(path: path) + " " + path).localizedCaseInsensitiveContains(String($0))
        }
    }
}

private struct SkillSearchChooser: View {
    let paths: [String]
    let selectedPath: String
    let pinned: Bool
    let onSelect: (String) -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    private var matches: [String] { paths.filter { SkillSearch.matches($0, query: query) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search skills or plugins", text: $query)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityLabel("Search skills or plugins")
                    .onSubmit { if !pinned, let first = matches.first { onSelect(first) } }
                if !query.isEmpty {
                    Button { query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }.padding(9).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            Text(pinned ? "Selection pinned by environment" : "Selected: \(InstalledSkillDiscovery.displayName(path: selectedPath))")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
            if matches.isEmpty { Text("No matching skills").foregroundStyle(.primary) }
            ForEach(InstalledSkillDiscovery.menuGroups(paths: matches)) { group in
                Text(group.title).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                ForEach(group.paths, id: \.self) { path in
                    Button { onSelect(path) } label: {
                        HStack {
                            Text(InstalledSkillDiscovery.displayName(path: path)).lineLimit(2)
                            Spacer()
                            if path == selectedPath { Image(systemName: "checkmark") }
                        }.frame(maxWidth: .infinity, minHeight: 32, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(pinned)
                        .accessibilityAddTraits(path == selectedPath ? .isSelected : [])
                }
            }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
            }.id(query).accessibilityLabel("Matching skills")
        }.task { searchFocused = true }
            .accessibilityElement(children: .contain)
    }
}

private struct PrototypeRegistryCard: View {
    let dashboard: SkillDashboard
    let compact: Bool
    @State private var expanded = false
    private var presentation: TesslRegistryPresentation { TesslRegistryPresentation(dashboard: dashboard) }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                if let image = AppResources.url(forResource: "TesslWordmark", withExtension: "png").flatMap(NSImage.init(contentsOf:)) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 247.5, height: 71.1).fixedSize()
                        // Compensate for the banner's empty left margin without resizing its artwork.
                        .offset(x: -36)
                        .frame(width: 148, height: 40).clipped()
                        .accessibilityLabel("Tessl")
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(presentation.statusLabel).foregroundStyle(Color.advisoryAccent)
                    if presentation.hasRegistrySnapshot { Text(presentation.versionText) }
                    Text(dashboard.registryPath.isEmpty ? "No registry identity" : dashboard.registryPath).lineLimit(1)
                }.font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.75))
            }
            if !compact, presentation.hasRegistrySnapshot {
                HStack(alignment: .top, spacing: 10) {
                    if let score = dashboard.tessl.registryScore {
                        Text("\(score)").font(.system(size: 23, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(score >= 80 ? Color.successAccent : .warningAccent)
                            .frame(width: 43, height: 43)
                            .background(.green.opacity(0.06), in: ScoreHexagon())
                            .overlay(ScoreHexagon().stroke(.green.opacity(0.4)))
                            .accessibilityLabel("Registry score \(score)")
                    }
                    metric("Quality", value: dashboard.tessl.registryQualityScore.map { "\($0)%" } ?? "—", progress: dashboard.tessl.registryQualityScore, tone: RegistryMetricPresentation.percentTone(dashboard.tessl.registryQualityScore))
                    metric("Impact", value: dashboard.tessl.registryImpactScore.map { "\($0)%" } ?? "—", progress: dashboard.tessl.registryImpactScore, tone: dashboard.tessl.registryImpactTone)
                    metric("Security", value: dashboard.tessl.registrySecurityDisplay, progress: dashboard.tessl.registrySecurityTone == .positive ? 100 : nil, tone: dashboard.tessl.registrySecurityTone)
                }
            }
            HStack {
                Text(presentation.hasRegistrySnapshot ? dashboard.registryEvidenceCaption : presentation.compactCaption)
                    .lineLimit(compact ? 1 : 2).help(dashboard.registryEvidenceCaption)
                Spacer(minLength: 0)
                if let url = dashboard.registryURL { Link("Tessl.io ↗", destination: url).foregroundStyle(Color.advisoryAccent) }
            }.font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.75))
            DisclosureGroup("Result details", isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(presentation.observedText) · separate from local SDK proof")
                        HStack {
                            if let count = dashboard.tessl.registryEvalCount { Text("\(count) evaluations") }
                            if let visibility = dashboard.tessl.registryVisibility { Text("· \(visibility)") }
                            if let multiplier = dashboard.tessl.registryImprovementMultiplier {
                                Text(String(format: "· %.2f× baseline", multiplier))
                            }
                        }
                        if compact {
                            Text("Quality: \(dashboard.tessl.registryQualityScore.map(String.init) ?? "—") · Impact: \(dashboard.tessl.registryImpactScore.map(String.init) ?? "—") · Security: \(dashboard.tessl.registrySecurityDisplay)")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
            }.font(.system(size: 11)).tint(.advisoryAccent)
        }
        .padding(10).background(Color(red: 0.03, green: 0.04, blue: 0.035), in: RoundedRectangle(cornerRadius: 8))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain).accessibilityLabel("Tessl registry evidence")
    }

    private func metric(_ title: String, value: String, progress: Int?, tone: StatusTone) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text(title).foregroundStyle(.white)
                Spacer(minLength: 0)
                Text(value).foregroundStyle(tone.color)
            }.font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            if title == "Impact", let multiplier = dashboard.tessl.registryImprovementMultiplier {
                Text(String(format: "%.2f×", multiplier)).font(.system(size: 9)).foregroundStyle(tone.color)
            }
            Spacer(minLength: 0)
            GeometryReader { geometry in
                if title == "Security" {
                    HStack(spacing: 2) {
                        ForEach(0..<5) { _ in Capsule().fill(progress == 100 ? tone.color : .white.opacity(0.12)) }
                    }
                } else {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(tone.color).frame(width: geometry.size.width * Double(min(100, max(0, progress ?? 0))) / 100)
                }
            }.frame(height: 4)
            if title == "Impact", let multiplier = dashboard.tessl.registryImprovementMultiplier, multiplier > 0, let progress {
                GeometryReader { geometry in
                    Capsule().fill(.white.opacity(0.8))
                        .frame(width: geometry.size.width * min(1, Double(progress) / 100 / multiplier))
                }.frame(height: 2).accessibilityLabel("Baseline comparison")
            }
        }.frame(maxWidth: .infinity).frame(height: 45).opacity(presentation.isLive ? 1 : 0.7)
    }
}

private struct ScoreHexagon: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let points = [(0.25, 0.0), (0.75, 0.0), (1.0, 0.5), (0.75, 1.0), (0.25, 1.0), (0.0, 0.5)]
            path.addLines(points.map { CGPoint(x: rect.width * $0.0, y: rect.height * $0.1) })
            path.closeSubpath()
        }
    }
}
