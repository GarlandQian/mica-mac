import Foundation
import MicaCore
import Testing
@testable import Mica

@MainActor
struct ProviderCommandScopeTests {
    enum Replacement: String, CaseIterable {
        case generation
        case controller
    }

    @Test(arguments: Replacement.allCases)
    func retainedScopeCannotUpdateAnIdenticalProviderInTheReplacementSession(
        replacement: Replacement
    ) async {
        let attempts = UpdateAttempts()
        let fixture = makeFixture(replacement: replacement, attempts: attempts)
        let model = fixture.model
        let initialState = model.operationState
        #expect(model.providersCatalog.providers.contains(fixture.provider))
        #expect(!model.matchesCurrentCommandScope(fixture.retainedScope))

        model.updateProxyProvider(fixture.provider, scope: fixture.retainedScope)
        await model.providerTask?.value

        #expect(await attempts.count == 0)
        #expect(model.providerTask == nil)
        #expect(model.updatingProviderName == nil)
        #expect(model.operationState == initialState)
    }

    @Test(arguments: Replacement.allCases)
    func staleProviderActionsCannotReplaceTheNewSessionsOperationStatus(
        replacement: Replacement
    ) async {
        let attempts = UpdateAttempts()
        let fixture = makeFixture(replacement: replacement, attempts: attempts)
        let model = fixture.model
        let owner = Task<Void, Never> {}
        let ownerState = OperationState.working("Current session provider operation")
        model.providerTask = owner
        model.reloadingProviders = true
        model.operationState = ownerState

        model.updateProxyProvider(fixture.provider, scope: fixture.retainedScope)
        #expect(model.operationState == ownerState)
        model.healthCheckProxyProvider(fixture.provider, scope: fixture.retainedScope)

        #expect(model.operationState == ownerState)
        #expect(model.reloadingProviders)
        #expect(model.providerTask != nil)
        #expect(!owner.isCancelled)
        #expect(model.updatingProviderName == nil)
        #expect(model.checkingProviderName == nil)
        #expect(await attempts.count == 0)
        await owner.value
        model.providerTask = nil
    }

    private struct Fixture {
        let model: AppModel
        let provider: ProxyProviderViewState
        let retainedScope: LiveCommandScope
    }

    private enum UnexpectedProviderDispatch: Error {
        case rejected
    }

    private actor UpdateAttempts {
        private(set) var count = 0

        func record() {
            count += 1
        }
    }

    private func makeFixture(
        replacement: Replacement,
        attempts: UpdateAttempts
    ) -> Fixture {
        let first = RouterProfile(
            displayName: "First offline controller",
            host: "first.invalid",
            controllerKind: .mihomoCompatible
        )
        let second = RouterProfile(
            displayName: "Second offline controller",
            host: "second.invalid",
            controllerKind: .mihomoCompatible
        )
        let provider = ProxyProviderViewState(
            kind: .proxy,
            name: "Shared provider",
            type: "HTTP",
            updatable: true,
            healthCheck: .object(["enable": .bool(true)]),
            itemCount: 4
        )
        var dashboard = DashboardSnapshot.empty
        dashboard.providers = [provider]
        let model = AppModel(
            routers: [first, second],
            selectedRouterID: first.id,
            connectionState: .connected(version: "offline-test"),
            dashboard: dashboard,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore(),
            providerUpdateOperation: { _, _, _ in
                await attempts.record()
                throw UnexpectedProviderDispatch.rejected
            }
        )
        model.controllerSession.begin(controllerID: first.id)
        model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 1))
        model.controllerSession.state = .live
        model.activeSessionControllerKind = .mihomoCompatible
        let retainedScope = commandScope(for: model)
        let current = replacement == .controller ? second : first
        model.selectedRouterID = current.id
        model.controllerSession.begin(controllerID: current.id)
        model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 2))
        model.controllerSession.state = .live
        return Fixture(model: model, provider: provider, retainedScope: retainedScope)
    }
}
