import Foundation

enum SkillsBarDemoMode {
    #if DEBUG
    static let environmentKey = "SKILLSBAR_DEMO_MODE"
    #else
    static let environmentKey = ""
    #endif

    static func isEnabled(in environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        #if DEBUG
        guard let value = environment[environmentKey]?.lowercased() else { return false }
        return ["1", "true", "yes", "on"].contains(value)
        #else
        return false
        #endif
    }
}

struct DashboardDataSource {
    typealias LocalEvidenceUpdate = @MainActor (SkillDashboard) -> Void

    private let environment: [String: String]
    private let liveLoad: () throws -> SkillDashboard
    private let progressiveLoadAsync: (@escaping LocalEvidenceUpdate) async throws -> SkillDashboard

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        liveLoad: @escaping () throws -> SkillDashboard = { try DashboardLoader().loadSync() },
        liveLoadAsync: (() async throws -> SkillDashboard)? = nil,
        progressiveLoadAsync: ((@escaping LocalEvidenceUpdate) async throws -> SkillDashboard)? = nil
    ) {
        self.environment = environment
        self.liveLoad = liveLoad
        let resolvedLiveLoadAsync = liveLoadAsync ?? { try await DashboardLoader().load() }
        if let progressiveLoadAsync {
            self.progressiveLoadAsync = progressiveLoadAsync
        } else if liveLoadAsync != nil {
            self.progressiveLoadAsync = { update in
                let dashboard = try await resolvedLiveLoadAsync()
                await update(dashboard)
                return dashboard
            }
        } else {
            self.progressiveLoadAsync = { update in
                try await DashboardLoader().load(onLocalEvidence: update)
            }
        }
    }

    var usesReviewFixture: Bool {
        fixtureValue != nil
    }

    private var fixtureValue: String? {
        #if DEBUG
        if SkillsBarDemoMode.isEnabled(in: environment) {
            return "live"
        }
        guard let value = environment["SKILLSBAR_REVIEW_FIXTURE"]?.lowercased(),
              ["1", "live", "no-cli", "offline", "reference"].contains(value) else { return nil }
        return value
        #else
        return nil
        #endif
    }

    private var fixtureDashboard: SkillDashboard {
        switch fixtureValue {
        case "no-cli", "offline":
            return .reviewNoCLIFixture
        case "reference":
            return .visualReferenceFixture
        default:
            return .reviewFixture
        }
    }

    var initialDashboard: SkillDashboard {
        usesReviewFixture ? fixtureDashboard : .placeholder
    }

    func loadSync() throws -> SkillDashboard {
        if usesReviewFixture {
            return fixtureDashboard
        }
        return try liveLoad()
    }

    @MainActor
    func load() async throws -> SkillDashboard {
        try await load { _ in }
    }

    @MainActor
    func load(onLocalEvidence: @escaping LocalEvidenceUpdate) async throws -> SkillDashboard {
        if usesReviewFixture {
            onLocalEvidence(fixtureDashboard)
            return fixtureDashboard
        }
        return try await progressiveLoadAsync(onLocalEvidence)
    }
}
