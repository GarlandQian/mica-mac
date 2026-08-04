import Foundation
import MicaCore
import Testing
@testable import Mica

struct AppModelEndpointChecksTests {
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

@MainActor
private func makeEndpointChecksModel() -> (AppModel, RouterProfile) {
    let profile = RouterProfile(
        displayName: "Offline Controller",
        host: "offline.invalid",
        port: 12_345,
        controllerKind: .mihomoCompatible
    )
    let model = AppModel(
        routers: [profile],
        selectedRouterID: profile.id,
        connectionState: .connected(version: "offline-test"),
        profileStore: InMemoryRouterProfileStore(),
        secretStore: InMemorySecretStore()
    )
    model.controllerSession.begin(controllerID: profile.id)
    model.activeSessionControllerKind = .mihomoCompatible

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
