import Foundation
import MicaCore
import Testing
@testable import Mica

struct AppModelEndpointChecksTests {
    @MainActor
    @Test func publishedDomainCatalogsOwnBaseSnapshotReadiness() throws {
        let (model, _) = makeEndpointChecksModel()
        model.dashboard = DashboardSnapshot(
            versionLabel: "internal-only",
            mode: "Rule",
            traffic: TrafficSnapshot(upload: 1, download: 1),
            groups: [proxyGroup()],
            connections: [ConnectionSnapshot(id: "internal-only")]
        )

        #expect(!model.hasPublishedBaseSnapshot)

        model.controllerMetadata.versionLabel = "1.0"
        #expect(model.hasPublishedBaseSnapshot)
        model.controllerMetadata = .empty

        model.policyGroupCatalog.groups = [proxyGroup()]
        #expect(model.hasPublishedBaseSnapshot)
        model.policyGroupCatalog = .empty

        model.connectionsCatalog.connections = [ConnectionSnapshot(id: "published")]
        #expect(model.hasPublishedBaseSnapshot)
        model.connectionsCatalog = .empty

        model.connectionsCatalog.traffic = TrafficSnapshot(upload: 0, download: 1)
        #expect(model.hasPublishedBaseSnapshot)

        let endpointStep = try #require(
            model.endpointCheckSteps.first { $0.id == "endpoint-base-snapshot" }
        )
        let resultRow = try #require(
            model.checkResultRows.first { $0.id == "base-snapshot" }
        )
        #expect(endpointStep.state == .passed)
        #expect(resultRow.state == .ready)
    }

    @MainActor
    @Test func coreCompatibilityFallbackUsesPublishedControllerMetadata() {
        let (model, profile) = makeEndpointChecksModel()
        model.dashboard.versionLabel = "legacy-core"
        model.controllerMetadata.versionLabel = "smart-core"

        var health = ControllerHealthSnapshot.checking(router: profile)
        health.set(.version, status: .idle)
        health.set(.configs, status: .ready("ready"))
        health.set(.proxies, status: .ready("ready"))
        health.set(.connections, status: .ready("ready"))
        health.set(.rules, status: .idle)
        health.set(.providers, status: .idle)
        health.finalize()
        model.controllerHealth = health

        #expect(model.coreCompatibilitySummary == .partialCompatible)
    }

    @MainActor
    @Test func surgeBaseSnapshotReadinessRemainsSurgeOwned() throws {
        let (model, _) = makeEndpointChecksModel(kind: .surgeCompatible)
        model.controllerMetadata.versionLabel = "mihomo-domain-value"

        #expect(model.hasPublishedBaseSnapshot)
        #expect(model.surgeSnapshot.isEmpty)

        let endpointStep = try #require(
            model.endpointCheckSteps.first { $0.id == "endpoint-base-snapshot" }
        )
        let resultRow = try #require(
            model.checkResultRows.first { $0.id == "base-snapshot" }
        )
        #expect(endpointStep.detail == model.localized("trial.base_not_loaded"))
        #expect(resultRow.latestResult == model.localized("matrix.no_current_base_snapshot"))
    }

    @MainActor
    @Test func diagnosticsUsePublishedDomainCatalogs() throws {
        let (model, _) = makeEndpointChecksModel()
        model.dashboard = DashboardSnapshot(
            versionLabel: "internal-version",
            mode: "Direct",
            traffic: TrafficSnapshot(upload: 0, download: 0),
            groups: [],
            connections: []
        )

        var config = DashboardConfigSnapshot.empty
        config.allowLan = true
        config.port = 7_890
        model.controllerMetadata = ControllerMetadataSnapshot(
            versionLabel: "published-version",
            mode: "Rule",
            config: config
        )
        model.policyGroupCatalog = PolicyGroupCatalogSnapshot(
            mode: "Rule",
            groups: [proxyGroup()]
        )
        model.connectionsCatalog = ConnectionsCatalogSnapshot(
            connections: [ConnectionSnapshot(id: "published-connection")],
            traffic: TrafficSnapshot(upload: 10, download: 20)
        )
        model.rulesCatalog = RulesCatalogSnapshot(
            rules: [RuleViewState(id: "published-rule", type: "MATCH", payload: "", proxy: "DIRECT")]
        )
        model.providersCatalog = ProvidersCatalogSnapshot(
            providers: [ProxyProviderViewState(name: "published-provider", type: "HTTP", itemCount: 1)]
        )
        model.insightCatalog = InsightSummarySnapshot(
            connectionCount: 3,
            ruleCount: 4,
            providerCount: 5,
            latencySampleCount: 6
        )

        let report = model.controllerDiagnosticsReport()
        #expect(report.contains(model.localized("diagnostics.version published-version")))
        #expect(report.contains(model.localized("diagnostics.mode \(MicaStrings.displayMode("Rule", language: model.presentationLanguage))")))
        #expect(report.contains(model.localized("diagnostics.policy_groups 1")))
        #expect(report.contains(model.localized("diagnostics.connections 1")))
        #expect(report.contains(model.localized("diagnostics.rules 1")))
        #expect(report.contains(model.localized("diagnostics.proxy_providers 1")))
        #expect(report.contains(model.localized("diagnostics.insight \(model.insightCatalog.diagnosticsStats)")))
        #expect(!report.contains("internal-version"))

        let displayPreview = model.diagnosticsReportDisplayPreview()
        #expect(displayPreview.contains(model.localized("diagnostics.policy_groups 1")))
        #expect(displayPreview.contains(model.localized("diagnostics.insight \(model.insightCatalog.diagnosticsStatsSummary(language: model.presentationLanguage))")))

        #expect(model.snapshotStatsDiagnostics.contains("groups=1; connections=1; rules=1; providers=1"))
        #expect(model.snapshotStatsDiagnostics.contains("config=[fields=2; mode-options=0; ports=1; boolean-flags=1]"))
        #expect(model.snapshotStatsDiagnostics.contains("insight=[\(model.insightCatalog.diagnosticsStats)]"))
        let exportedStats = try #require(
            model.diagnosticsExportPlanRows.first { $0.id == "snapshot-stats" }
        )
        #expect(exportedStats.value == model.snapshotStatsDiagnostics)
    }

    @MainActor
    @Test func newerProviderUpdateAllRecordDrivesEndpointAndCheckResults() throws {
        let (model, profile) = makeEndpointChecksModel()
        let olderSingleTimestamp = Date(timeIntervalSince1970: 100)
        let newerBatchTimestamp = Date(timeIntervalSince1970: 200)

        model.trialSessions[profile.id] = trialSession(
            for: profile,
            commandLog: [
                commandEntry(
                    action: .providerUpdate,
                    status: .failed,
                    timestamp: olderSingleTimestamp
                ),
                commandEntry(
                    action: .providerUpdateAll,
                    status: .success,
                    timestamp: newerBatchTimestamp
                ),
            ]
        )

        let endpointStep = try #require(
            model.endpointCheckSteps.first { $0.id == "endpoint-provider-update" }
        )
        let resultRow = try #require(
            model.checkResultRows.first { $0.id == "provider-update" }
        )
        let expectedResult = commandResultLabel(
            action: .providerUpdateAll,
            status: .success,
            language: model.presentationLanguage
        )

        #expect(endpointStep.state == .passed)
        #expect(endpointStep.detail == expectedResult)
        #expect(resultRow.state == .ready)
        #expect(resultRow.currentState == CommandLifecycle.success.label(language: model.presentationLanguage))
        #expect(resultRow.latestResult == expectedResult)
        #expect(resultRow.lastChecked == ISO8601DateFormatter().string(from: newerBatchTimestamp))
    }

    @MainActor
    @Test func newerIndividualProviderUpdateRecordWinsOlderBatchRecord() throws {
        let (model, profile) = makeEndpointChecksModel()
        let olderBatchTimestamp = Date(timeIntervalSince1970: 300)
        let newerSingleTimestamp = Date(timeIntervalSince1970: 400)

        model.trialSessions[profile.id] = trialSession(
            for: profile,
            commandLog: [
                commandEntry(
                    action: .providerUpdateAll,
                    status: .success,
                    timestamp: olderBatchTimestamp
                ),
                commandEntry(
                    action: .providerUpdate,
                    status: .partial,
                    timestamp: newerSingleTimestamp
                ),
            ]
        )

        let endpointStep = try #require(
            model.endpointCheckSteps.first { $0.id == "endpoint-provider-update" }
        )
        let resultRow = try #require(
            model.checkResultRows.first { $0.id == "provider-update" }
        )
        let expectedResult = commandResultLabel(
            action: .providerUpdate,
            status: .partial,
            language: model.presentationLanguage
        )

        #expect(endpointStep.state == .partial)
        #expect(endpointStep.detail == expectedResult)
        #expect(resultRow.state == .partial)
        #expect(resultRow.currentState == CommandLifecycle.partial.label(language: model.presentationLanguage))
        #expect(resultRow.latestResult == expectedResult)
        #expect(resultRow.lastChecked == ISO8601DateFormatter().string(from: newerSingleTimestamp))
    }

    @MainActor
    @Test func missingProviderCommandRecordRemainsNotChecked() throws {
        let (model, profile) = makeEndpointChecksModel()
        model.trialSessions[profile.id] = trialSession(
            for: profile,
            commandLog: [
                commandEntry(
                    action: .refresh,
                    status: .success,
                    timestamp: Date(timeIntervalSince1970: 500)
                ),
            ]
        )

        let endpointStep = try #require(
            model.endpointCheckSteps.first { $0.id == "endpoint-provider-update" }
        )
        let resultRow = try #require(
            model.checkResultRows.first { $0.id == "provider-update" }
        )

        #expect(endpointStep.state == .ready)
        #expect(endpointStep.detail == model.localized("check.no_result"))
        #expect(resultRow.state == .notChecked)
        #expect(resultRow.currentState == model.localized("matrix.not_checked"))
        #expect(resultRow.latestResult == model.localized("check.no_result"))
        #expect(resultRow.lastChecked == model.localized("matrix.not_recorded"))
    }
}

private func proxyGroup() -> ProxyGroupViewState {
    ProxyGroupViewState(
        id: "published-group",
        type: "Selector",
        selected: "node-a",
        options: ["node-a"]
    )
}

@MainActor
private func makeEndpointChecksModel(
    kind: ControllerKind = .mihomoCompatible
) -> (AppModel, RouterProfile) {
    let profile = RouterProfile(
        displayName: "Offline Controller",
        host: "offline.invalid",
        port: 12_345,
        controllerKind: kind
    )
    let model = AppModel(
        routers: [profile],
        selectedRouterID: profile.id,
        connectionState: .connected(version: "offline-test"),
        profileStore: InMemoryRouterProfileStore(),
        secretStore: InMemorySecretStore()
    )
    model.controllerSession.begin(controllerID: profile.id)
    model.activeSessionControllerKind = kind

    var health = ControllerHealthSnapshot.checking(router: profile)
    health.set(.providers, status: .ready("ready"))
    health.finalize()
    model.controllerHealth = health

    return (model, profile)
}

private func trialSession(
    for profile: RouterProfile,
    commandLog: [CommandLogEntry]
) -> TrialSessionSnapshot {
    let latestCommand = commandLog.max { $0.timestamp < $1.timestamp }

    return TrialSessionSnapshot(
        routerName: profile.displayName,
        lastTestedAt: nil,
        lastRefreshedAt: nil,
        lastSuccessfulBaseSnapshotAt: nil,
        lastPartialSnapshotAt: nil,
        lastCommandAction: latestCommand?.action,
        lastCommandStatus: latestCommand?.status,
        lastCommandSummary: latestCommand?.safeSummary,
        commandLog: commandLog
    )
}

private func commandEntry(
    action: TrialCommandAction,
    status: CommandLifecycle,
    timestamp: Date
) -> CommandLogEntry {
    CommandLogEntry(
        action: action,
        status: status,
        timestamp: timestamp,
        safeTarget: "Offline Controller",
        safeSummary: "offline command record"
    )
}

private func commandResultLabel(
    action: TrialCommandAction,
    status: CommandLifecycle,
    language: AppLanguage
) -> String {
    "\(action.title(language: language)) \(status.label(language: language))"
}
