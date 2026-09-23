import Foundation
import MicaCore
import Observation
import SwiftUI
import Synchronization
import Testing
@testable import Mica

@MainActor
struct WorkbenchCatalogObserverTests {
    @Test func catalogSubscriptionsBelongToLeafBodiesAndStayDomainScoped() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let sourceModel = WorkbenchSourcesModel()
        let logModel = WorkbenchLogsModel()
        let parentChanges = Mutex(0)
        let sourceChanges = Mutex(0)
        let logChanges = Mutex(0)

        // This is the production boundary used by the page body: it passes
        // references and explicit user input without evaluating live catalogs.
        withObservationTracking {
            _ = fixture.sources(model: sourceModel)
            _ = fixture.logs(model: logModel)
        } onChange: {
            parentChanges.withLock { $0 += 1 }
        }
        withObservationTracking {
            _ = fixture.sources(model: sourceModel).body
        } onChange: {
            sourceChanges.withLock { $0 += 1 }
        }
        withObservationTracking {
            _ = fixture.logs(model: logModel).body
        } onChange: {
            logChanges.withLock { $0 += 1 }
        }

        fixture.appModel.providersCatalog = .init(providers: [provider("updated", count: 2)])
        #expect(parentChanges.withLock { $0 } == 0)
        #expect(sourceChanges.withLock { $0 } == 1)
        #expect(logChanges.withLock { $0 } == 0)

        fixture.appModel.logsCatalog = .init(entries: [entry("new")], entriesRevision: 2)
        #expect(parentChanges.withLock { $0 } == 0)
        #expect(logChanges.withLock { $0 } == 1)
    }

    @Test func sourcesRestoreSelectionAndFilterLatestDeferredSnapshotImmediately() throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let original = provider("kept", count: 1)
        fixture.appModel.providersCatalog = .init(providers: [original])
        fixture.workspace.update(controllerID: fixture.controllerID, destination: .sources) {
            $0.selectedItemID = original.id
            $0.activeTab = ProviderSessionKind.proxy.rawValue
        }
        let model = WorkbenchSourcesModel()
        let observer = fixture.sources(model: model)
        observer.activate()
        defer { observer.deactivate() }
        let scope = try #require(model.scope)
        #expect(model.selectedRow?.source == original)
        #expect(fixture.workspace.inspectorSelection == .source(id: original.id))
        #expect(fixture.workspace.sourceRowResolver?(original.id)?.itemCount == 1)
        model.interaction.apply(.began)

        fixture.appModel.providersCatalog = .init(providers: [provider("kept", count: 20), provider("added", count: 30)])
        observer.synchronize(observer.presentationInput)
        #expect(model.rows.map(\.itemCount) == [1])
        #expect(fixture.workspace.sourceRowResolver?(original.id)?.itemCount == 1)

        let filtered = fixture.sources(model: model, query: "added", language: .simplifiedChinese)
        filtered.synchronize(filtered.presentationInput)
        #expect(model.rows.map(\.name) == ["added"])
        #expect(model.rows.first?.itemCount == 30)
        #expect(model.rows.first?.kindText == MicaStrings.localizedKey("traffic.provider_kind_proxy", language: .simplifiedChinese))
        #expect(model.selectedRowID == nil)
        model.interaction.apply(.ended)
        model.finishDeferredPresentation(scope: scope)
        #expect(model.rows.map(\.name) == ["added"])
    }

    @Test func logsRestoreFollowAndInspectionAndQueryCurrentDeferredEntries() throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.appModel.logsCatalog = .init(entries: [entry("kept")], entriesRevision: 1)
        fixture.workspace.update(controllerID: fixture.controllerID, destination: .logs) {
            $0.selectedItemID = "kept"
            $0.filters["followNewest"] = "false"
        }
        let model = WorkbenchLogsModel()
        let observer = fixture.logs(model: model)
        observer.activate()
        defer { observer.deactivate() }
        #expect(!model.followsNewest)
        #expect(model.selectedRowID == "kept")
        #expect(fixture.workspace.inspectorSelection == .log(id: "kept"))
        #expect(fixture.workspace.logEntryResolver?("kept")?.payloadText == "kept")
        model.interaction.apply(.began)

        let added = entry("added")
        fixture.appModel.logsCatalog = .init(
            entries: [entry("kept"), added], entriesRevision: 2,
            lastChange: .delta(droppedEntryIDs: [], appendedEntries: [added])
        )
        observer.synchronize(observer.presentationRequest)
        #expect(model.rows.map(\.id) == ["kept"])

        let filtered = fixture.logs(model: model, query: "added", language: .simplifiedChinese)
        filtered.synchronize(filtered.presentationRequest)
        #expect(model.rows.map(\.id) == ["added"])
        #expect(model.rows.first?.receivedDateTimeText == WorkbenchDataFormat.receivedDateTime(added.receivedAt, language: .simplifiedChinese))
        #expect(fixture.workspace.logEntryResolver?("added")?.payloadText == "added")
        #expect(!model.followsNewest)
        #expect(model.selectedRowID == nil)
    }

    @Test func delayedLeafCallbacksCannotRestoreAnOldControllerGeneration() throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.appModel.providersCatalog = .init(providers: [provider("old", count: 1)])
        fixture.appModel.logsCatalog = .init(entries: [entry("old")], entriesRevision: 1)
        let sourceModel = WorkbenchSourcesModel()
        let logModel = WorkbenchLogsModel()
        let sources = fixture.sources(model: sourceModel)
        let logs = fixture.logs(model: logModel)
        sources.activate()
        logs.activate()
        let oldSources = sources.presentationInput
        let oldLogs = logs.presentationRequest
        sourceModel.interaction.apply(.began)
        logModel.interaction.apply(.began)

        fixture.appModel.controllerSession.begin(controllerID: fixture.controllerID)
        fixture.appModel.controllerSessionPresentation.synchronize(with: fixture.appModel.controllerSession)
        fixture.appModel.providersCatalog = .init(providers: [provider("replacement", count: 3)])
        fixture.appModel.logsCatalog = .init(entries: [entry("replacement")], entriesRevision: 1)
        sources.synchronize(sources.presentationInput)
        logs.synchronize(logs.presentationRequest)
        let current = try #require(sourceModel.scope)
        #expect(current != oldSources.scope)
        #expect(!sourceModel.interaction.isUserScrolling)
        #expect(!logModel.interaction.isUserScrolling)
        sources.synchronize(oldSources)
        logs.synchronize(oldLogs)
        #expect(sourceModel.scope == current)
        #expect(logModel.scope == current)
        #expect(sourceModel.rows.map(\.name) == ["replacement"])
        #expect(logModel.rows.map(\.id) == ["replacement"])

        sources.deactivate()
        logs.deactivate()
        #expect(fixture.workspace.sourceRowResolver == nil)
        #expect(fixture.workspace.logEntryResolver == nil)
        fixture.appModel.providersCatalog = .init(providers: [])
        fixture.appModel.logsCatalog = .init(entries: [], entriesRevision: 2)
        sources.synchronize(sources.presentationInput)
        logs.synchronize(logs.presentationRequest)
        #expect(sourceModel.rows.map(\.name) == ["replacement"])
        #expect(logModel.rows.map(\.id) == ["replacement"])

        // A callback for the newest controller generation must not restore a
        // page that already disappeared. Only its next appearance may do so.
        fixture.workspace.selectInspector(.rule(type: "DOMAIN", payload: "active.test"))
        fixture.appModel.controllerSession.begin(controllerID: fixture.controllerID)
        fixture.appModel.controllerSessionPresentation.synchronize(with: fixture.appModel.controllerSession)
        fixture.appModel.providersCatalog = .init(providers: [provider("offscreen", count: 8)])
        fixture.appModel.logsCatalog = .init(entries: [entry("offscreen")], entriesRevision: 1)
        let offscreenSources = sources.presentationInput
        let offscreenLogs = logs.presentationRequest
        #expect(offscreenSources.scope != current)
        sources.synchronize(offscreenSources)
        logs.synchronize(offscreenLogs)
        #expect(!sourceModel.isActive)
        #expect(!logModel.isActive)
        #expect(sourceModel.scope == current)
        #expect(logModel.scope == current)
        #expect(sourceModel.rows.map(\.name) == ["replacement"])
        #expect(logModel.rows.map(\.id) == ["replacement"])
        #expect(fixture.workspace.sourceRowResolver == nil)
        #expect(fixture.workspace.logEntryResolver == nil)
        #expect(fixture.workspace.inspectorSelection == .rule(type: "DOMAIN", payload: "active.test"))

        sources.activate()
        logs.activate()
        #expect(sourceModel.isActive)
        #expect(logModel.isActive)
        #expect(sourceModel.scope == offscreenSources.scope)
        #expect(logModel.scope == offscreenLogs.scope)
        #expect(sourceModel.rows.map(\.name) == ["offscreen"])
        #expect(logModel.rows.map(\.id) == ["offscreen"])
        #expect(fixture.workspace.sourceRowResolver?(provider("offscreen", count: 8).id)?.itemCount == 8)
        #expect(fixture.workspace.logEntryResolver?("offscreen")?.payloadText == "offscreen")
        sources.deactivate()
        logs.deactivate()
    }

    private func provider(_ name: String, count: Int) -> ProxyProviderViewState {
        .init(kind: .proxy, name: name, type: "HTTP", updatable: true, itemCount: count)
    }

    private func entry(_ id: String) -> ControllerLogEntry {
        .init(id: id, receivedAt: Date(timeIntervalSince1970: 1_000), message: .init(type: "info", payload: id))
    }

    @MainActor
    private final class Fixture {
        let appModel: AppModel
        let workspace: WorkbenchWorkspaceStore
        let controllerID: UUID
        private let defaults: UserDefaults
        private let suiteName = "mica-catalog-observer-\(UUID().uuidString)"

        init() {
            defaults = UserDefaults(suiteName: suiteName)!
            let profile = RouterProfile(displayName: "Offline", host: "observer.invalid", controllerKind: .mihomoCompatible)
            controllerID = profile.id
            appModel = AppModel(
                routers: [profile], selectedRouterID: profile.id,
                profileStore: InMemoryRouterProfileStore(), secretStore: InMemorySecretStore(), userDefaults: defaults
            )
            workspace = WorkbenchWorkspaceStore(defaults: defaults)
            appModel.controllerSession.begin(controllerID: profile.id)
            appModel.controllerSessionPresentation.synchronize(with: appModel.controllerSession)
        }

        func cleanUp() { defaults.removePersistentDomain(forName: suiteName) }

        func sources(
            model: WorkbenchSourcesModel,
            query: String = "",
            language: AppLanguage = .english
        ) -> WorkbenchSourcesCatalogObserver {
            .init(appModel: appModel, workspaceStore: workspace, model: model, query: query, language: language)
        }

        func logs(
            model: WorkbenchLogsModel,
            query: String = "",
            language: AppLanguage = .english
        ) -> WorkbenchLogsCatalogObserver {
            .init(appModel: appModel, workspaceStore: workspace, model: model, query: query, language: language)
        }
    }
}
