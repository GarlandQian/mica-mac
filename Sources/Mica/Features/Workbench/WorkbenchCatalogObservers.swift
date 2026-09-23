import MicaCore
import SwiftUI

/// Catalog observation belongs to a nonvisual leaf. Constructing this view
/// does not read the catalog, so accepting a deferred snapshot cannot rebuild
/// the parent command bar, accessibility payload, or native Table.
struct WorkbenchSourcesCatalogObserver: View {
    let appModel: AppModel
    let workspaceStore: WorkbenchWorkspaceStore
    let model: WorkbenchSourcesModel
    let query: String
    let language: AppLanguage

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear(perform: activate)
            .onDisappear(perform: deactivate)
            .onChange(of: presentationInput) { _, input in
                synchronize(input)
            }
    }

    var presentationInput: WorkbenchSourcesPresentationInput {
        WorkbenchSourcesPresentationInput(
            scope: WorkbenchSessionIdentity(
                controllerID: appModel.selectedRouterID,
                generation: appModel.controllerSessionPresentation.generation
            ),
            sources: appModel.providersCatalog.providers,
            query: query,
            language: language
        )
    }

    func activate() {
        workspaceStore.sourceRowResolver = { [weak model] id in model?.row(id: id) }
        let input = presentationInput
        restoreWorkspace(scope: input.scope)
        model.update(input)
        if let selectedRowID = model.selectedRowID {
            workspaceStore.selectInspector(.source(id: selectedRowID))
        }
    }

    func deactivate() {
        workspaceStore.sourceRowResolver = nil
        model.deactivate()
    }

    func synchronize(_ input: WorkbenchSourcesPresentationInput) {
        guard model.isActive, input.scope == presentationScope else { return }
        if model.scope != input.scope {
            restoreWorkspace(scope: input.scope)
        }
        model.update(input)
    }

    private var presentationScope: WorkbenchSessionIdentity {
        WorkbenchSessionIdentity(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
    }

    private func restoreWorkspace(scope: WorkbenchSessionIdentity) {
        if let controllerID = scope.controllerID {
            workspaceStore.activateSession(controllerID: controllerID, generation: scope.generation)
        }
        model.activate(
            scope: scope,
            workspace: workspaceStore.workspace(controllerID: scope.controllerID, destination: .sources),
            scrollAnchorID: scope.controllerID.flatMap {
                workspaceStore.scrollAnchorID(controllerID: $0, generation: scope.generation, destination: .sources)
            }
        )
    }
}

struct WorkbenchLogsCatalogObserver: View {
    let appModel: AppModel
    let workspaceStore: WorkbenchWorkspaceStore
    let model: WorkbenchLogsModel
    let query: String
    let language: AppLanguage

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear(perform: activate)
            .onDisappear(perform: deactivate)
            .onChange(of: presentationRequest) { _, request in
                synchronize(request)
            }
    }

    var presentationRequest: WorkbenchLogsPresentationRequest {
        WorkbenchLogsPresentationRequest(
            scope: WorkbenchSessionIdentity(
                controllerID: appModel.selectedRouterID,
                generation: appModel.controllerSessionPresentation.generation
            ),
            revision: appModel.logsCatalog.entriesRevision,
            query: query,
            language: language
        )
    }

    func activate() {
        workspaceStore.logEntryResolver = { [weak model] id in model?.row(id: id) }
        let request = presentationRequest
        restoreWorkspace(scope: request.scope)
        model.update(catalog: appModel.logsCatalog, request: request)
        if let selectedRowID = model.selectedRowID {
            workspaceStore.selectInspector(.log(id: selectedRowID))
        }
    }

    func deactivate() {
        workspaceStore.logEntryResolver = nil
        model.deactivate()
    }

    func synchronize(_ request: WorkbenchLogsPresentationRequest) {
        guard model.isActive, request.scope == presentationScope else { return }
        if model.scope != request.scope {
            restoreWorkspace(scope: request.scope)
        }
        model.update(catalog: appModel.logsCatalog, request: request)
    }

    private var presentationScope: WorkbenchSessionIdentity {
        WorkbenchSessionIdentity(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation
        )
    }

    private func restoreWorkspace(scope: WorkbenchSessionIdentity) {
        if let controllerID = scope.controllerID {
            workspaceStore.activateSession(controllerID: controllerID, generation: scope.generation)
        }
        model.activate(
            scope: scope,
            workspace: workspaceStore.workspace(controllerID: scope.controllerID, destination: .logs),
            scrollAnchorID: scope.controllerID.flatMap {
                workspaceStore.scrollAnchorID(controllerID: $0, generation: scope.generation, destination: .logs)
            },
            defaultLevel: appModel.controllerLogLevel,
            availableLevels: LogSessionLevel.availableLevels(for: appModel.selectedUnifiedControllerType)
        )
    }
}
