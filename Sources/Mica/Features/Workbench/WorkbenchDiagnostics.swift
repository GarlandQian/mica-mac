import Foundation
import MicaCore
import SwiftUI

// MARK: - Diagnostics

struct WorkbenchDiagnosticsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    @Binding var destination: WorkbenchDestination

    let onEditController: (RouterProfile) -> Void

    @State private var selectedIssueID: String?
    @State private var technicalDetailsExpanded = false

    var body: some View {
        let snapshot = diagnosticsSnapshot

        WorkbenchPageScaffold {
            commandBar(snapshot)
        } content: {
            diagnosticsContent(snapshot)
        }
        .onAppear {
            reconcileSelection(with: snapshot, reset: true)
        }
        .onChange(of: snapshot?.controllerID) { _, _ in
            technicalDetailsExpanded = false
            reconcileSelection(with: snapshot, reset: true)
        }
        .onChange(of: snapshot?.generation) { _, _ in
            technicalDetailsExpanded = false
            reconcileSelection(with: snapshot, reset: true)
        }
        .onChange(of: snapshot?.issues.map(\.id)) { _, _ in
            reconcileSelection(with: snapshot, reset: false)
        }
    }

    private var diagnosticsSnapshot: WorkbenchDiagnosticsSnapshot? {
        guard let router = appModel.selectedRouter else { return nil }
        return WorkbenchDiagnosticsProjection.snapshot(
            WorkbenchDiagnosticsInput(
                router: router,
                generation: appModel.controllerSessionPresentation.generation,
                detectedKind: appModel.runtimeControllerKind(for: router),
                controllerType: appModel.selectedUnifiedControllerType,
                sessionState: appModel.controllerSessionPresentation.state,
                lastSuccessAt: appModel.controllerSessionPresentation.lastSuccessAt,
                isPresentationPaused: appModel.controllerSessionPresentation.controls.dashboardUpdatesPaused,
                presentationPausedAt: appModel.controllerSessionPresentation.controls.presentationPausedAt,
                health: appModel.controllerHealth,
                capabilities: appModel.selectedUnifiedCapabilities,
                rulesState: appModel.rulesSnapshotState,
                providersState: appModel.providersSnapshotState,
                liveStreamState: appModel.liveStreamState,
                metadata: appModel.controllerMetadata,
                language: language
            )
        )
    }

    @ViewBuilder
    private func diagnosticsContent(
        _ snapshot: WorkbenchDiagnosticsSnapshot?
    ) -> some View {
        if let snapshot {
            WorkbenchDiagnosticsCanvas { contentWidth in
                if let retainedFailureMessage {
                    WorkbenchStaleNotice(message: retainedFailureMessage)
                }

                WorkbenchDiagnosticsVerdictHeader(snapshot: snapshot)

                if !snapshot.issues.isEmpty {
                    WorkbenchDiagnosticsIssueWorkspace(
                        issues: snapshot.issues,
                        usesSplitLayout: contentWidth >= 900,
                        selectedIssueID: $selectedIssueID,
                        isActionEnabled: diagnosticsActionAvailability.isEnabled,
                        onAction: perform
                    )
                }

                if !snapshot.availableAreas.isEmpty {
                    Divider()
                    WorkbenchDiagnosticsAvailableAreas(
                        areas: snapshot.availableAreas
                    ) { destination in
                        self.destination = destination
                    }
                }

                if !snapshot.technicalGroups.isEmpty {
                    Divider()
                    WorkbenchDiagnosticsTechnicalDetails(
                        groups: snapshot.technicalGroups,
                        isExpanded: $technicalDetailsExpanded
                    )
                }
            }
        } else {
            WorkbenchStateView(
                kind: .noController,
                titleKey: "dashboard.connect_router",
                detailKey: "configuration.no_controller_detail"
            )
        }
    }

    private func commandBar(
        _ snapshot: WorkbenchDiagnosticsSnapshot?
    ) -> some View {
        WorkbenchCommandBar {
            WorkbenchManagementHeader(
                systemImage: "stethoscope",
                titleKey: "diagnostics.title",
                detail: snapshot?.controllerName,
                value: snapshot?.visibleTarget
            )
        } controls: {
            if let snapshot {
                WorkbenchStatusBadge(
                    text: MicaStrings.localizedKey(
                        snapshot.overallState.labelKey,
                        language: language
                    ),
                    tint: snapshot.overallState.tint
                )
            }
        } commands: {
            WorkbenchIconCommand(
                titleKey: "diagnostics.copy_report",
                systemImage: "doc.on.doc",
                isEnabled: snapshot != nil && !appModel.diagnosticsReportSections.isEmpty
            ) {
                appModel.copyDiagnosticsReport()
            }
        }
    }

    private func perform(_ action: WorkbenchDiagnosticsAction) {
        guard diagnosticsActionAvailability.isEnabled(action) else { return }
        switch action {
        case .refresh:
            if appModel.canRefreshSelectedRouter {
                appModel.refreshSelectedRouter()
            } else if appModel.canTestSelectedRouter {
                appModel.testSelectedRouter()
            }
        case .resumePresentation:
            appModel.setPresentationPaused(false)
        case .editController:
            if let router = appModel.selectedRouter {
                onEditController(router)
            }
        case .navigate(let destination):
            self.destination = destination
        }
    }

    private var diagnosticsActionAvailability: WorkbenchDiagnosticsActionAvailability {
        WorkbenchDiagnosticsActionAvailability(
            canRefresh: appModel.canRefreshSelectedRouter,
            canTest: appModel.canTestSelectedRouter,
            canTogglePresentationPause: appModel.canTogglePresentationPause,
            isPresentationPaused: appModel.controllerSessionPresentation.controls.dashboardUpdatesPaused,
            hasSelectedController: appModel.selectedRouter != nil,
            isBusy: appModel.isBusy
        )
    }

    private func reconcileSelection(
        with snapshot: WorkbenchDiagnosticsSnapshot?,
        reset: Bool
    ) {
        guard let snapshot else {
            selectedIssueID = nil
            return
        }
        let currentID = reset ? nil : selectedIssueID
        let nextID = WorkbenchDiagnosticsProjection.reconciledSelection(
            currentID: currentID,
            issues: snapshot.issues
        )
        if selectedIssueID != nextID {
            selectedIssueID = nextID
        }
    }

    private var retainedFailureMessage: String? {
        switch appModel.controllerSessionPresentation.state {
        case .staleReconnecting(let message), .partial(let message), .failed(let message):
            message.managementNonEmpty
        default:
            nil
        }
    }
}
