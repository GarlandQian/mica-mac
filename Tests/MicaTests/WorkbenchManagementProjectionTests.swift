import Foundation
import MicaCore
import Testing
@testable import Mica

struct WorkbenchManagementProjectionTests {
    @Test func managementRowsUseOneRootWidthMode() {
        #expect(
            WorkbenchManagementWidthMode(
                availableWidth: MicaBounds.wideThreshold - 1
            ) == .compact
        )
        #expect(
            WorkbenchManagementWidthMode(
                availableWidth: MicaBounds.wideThreshold
            ) == .regular
        )
        #expect(
            WorkbenchManagementWidthMode(
                availableWidth: MicaBounds.wideThreshold + 400
            ) == .regular
        )
    }

    @Test func retainsCompleteLatestReportForEachProfile() throws {
        let presentationID = UUID()
        let first = profile(name: "Primary", host: "primary.example", port: 12_001)
        let second = profile(name: "Backup", host: "backup.example", port: 12_002)
        let report = connectionReport(headline: "Primary is ready")
        var projection = WorkbenchConnectionTestProjection(
            presentationID: presentationID
        )

        let intent = projection.begin(profile: first, intentID: UUID())
        let accepted = projection.receive(
            report,
            for: intent,
            profiles: [first, second]
        )

        #expect(accepted)
        #expect(projection.report(for: first) == report)
        #expect(projection.report(for: second) == nil)
        #expect(
            try #require(projection.report(for: first)).steps.map(\.id)
                == ["url", "tls", "version"]
        )
    }

    @Test func newerIntentRejectsAnOlderResultForTheSameProfile() {
        let target = profile(name: "Primary", host: "primary.example", port: 12_001)
        var projection = WorkbenchConnectionTestProjection()
        let olderIntent = projection.begin(profile: target, intentID: UUID())
        let newerIntent = projection.begin(profile: target, intentID: UUID())
        let acceptedOlderResult = projection.receive(
            connectionReport(headline: "Older result"),
            for: olderIntent,
            profiles: [target]
        )
        let acceptedNewerResult = projection.receive(
            connectionReport(headline: "Newer result"),
            for: newerIntent,
            profiles: [target]
        )

        #expect(!acceptedOlderResult)
        #expect(acceptedNewerResult)
        #expect(projection.report(for: target)?.headline == "Newer result")
    }

    @Test func replacingThePresentationInvalidatesAnInflightResult() {
        let target = profile(name: "Primary", host: "primary.example", port: 12_001)
        var projection = WorkbenchConnectionTestProjection(
            presentationID: UUID()
        )
        let intent = projection.begin(profile: target, intentID: UUID())

        projection.replacePresentation(with: UUID())
        let accepted = projection.receive(
            connectionReport(headline: "Stale result"),
            for: intent,
            profiles: [target]
        )

        #expect(!accepted)
        #expect(projection.report(for: target) == nil)
    }

    @Test func editingTestRelevantProfileFieldsInvalidatesStoredAndInflightResults() {
        let original = profile(name: "Primary", host: "primary.example", port: 12_001)
        var edited = original
        edited.host = "replacement.example"
        var projection = WorkbenchConnectionTestProjection()
        let completedIntent = projection.begin(profile: original, intentID: UUID())
        let acceptedCompletedResult = projection.receive(
            connectionReport(headline: "Original result"),
            for: completedIntent,
            profiles: [original]
        )
        #expect(acceptedCompletedResult)

        let inflightIntent = projection.begin(profile: original, intentID: UUID())
        projection.reconcile(profiles: [edited])
        let acceptedInflightResult = projection.receive(
            connectionReport(headline: "Late original result"),
            for: inflightIntent,
            profiles: [edited]
        )

        #expect(projection.report(for: edited) == nil)
        #expect(!projection.isTesting(edited))
        #expect(!acceptedInflightResult)
    }

    @Test func lastConnectedAtUpdatesDoNotInvalidateTheMatchingResult() {
        let original = profile(name: "Primary", host: "primary.example", port: 12_001)
        var updated = original
        updated.lastConnectedAt = Date(timeIntervalSince1970: 1)
        var projection = WorkbenchConnectionTestProjection()
        let intent = projection.begin(profile: original, intentID: UUID())

        projection.reconcile(profiles: [updated])
        let accepted = projection.receive(
            connectionReport(headline: "Current result"),
            for: intent,
            profiles: [updated]
        )

        #expect(accepted)
        #expect(projection.report(for: updated)?.headline == "Current result")
    }

    @Test func controllerFilteringPreservesPersistedOrder() {
        let first = profile(name: "Edge Primary", host: "first.example", port: 12_001)
        let second = profile(name: "Backup", host: "edge-backup.example", port: 12_002)
        let third = profile(name: "Edge Lab", host: "third.example", port: 12_003)

        let filtered = WorkbenchControllerListProjection.filtered(
            [first, second, third],
            query: "edge"
        ) { _ in "Mihomo" }

        #expect(filtered.map(\.id) == [first.id, second.id, third.id])
    }

    @Test func controllerSelectionPrefersStoredThenActiveThenFirst() {
        let first = profile(name: "Primary", host: "first.example", port: 12_001)
        let second = profile(name: "Backup", host: "second.example", port: 12_002)

        #expect(
            WorkbenchControllerListProjection.reconciledSelection(
                storedID: second.id,
                activeID: first.id,
                candidates: [first, second]
            ) == second.id
        )
        #expect(
            WorkbenchControllerListProjection.reconciledSelection(
                storedID: UUID(),
                activeID: second.id,
                candidates: [first, second]
            ) == second.id
        )
        #expect(
            WorkbenchControllerListProjection.reconciledSelection(
                storedID: nil,
                activeID: nil,
                candidates: [first, second]
            ) == first.id
        )
    }

    @Test func controllerDeletionConfirmationIsGenerationScoped() {
        let selectedRouterID = UUID()
        let generation = UUID()
        let confirmation = WorkbenchControllerDeleteConfirmation(
            profileID: UUID(),
            selectedRouterID: selectedRouterID,
            generation: generation
        )

        #expect(
            confirmation.isCurrent(
                selectedRouterID: selectedRouterID,
                generation: generation
            )
        )
        #expect(
            !confirmation.isCurrent(
                selectedRouterID: UUID(),
                generation: generation
            )
        )
        #expect(
            !confirmation.isCurrent(
                selectedRouterID: selectedRouterID,
                generation: UUID()
            )
        )
    }

    @Test func runtimeConfirmationRequiresTheSameLiveGeneration() {
        let routerID = UUID()
        let generation = UUID()
        let confirmation = WorkbenchRuntimeConfirmation(
            routerID: routerID,
            generation: generation,
            operationID: "core-restart"
        )

        #expect(
            confirmation.isCurrent(
                routerID: routerID,
                generation: generation,
                permitsLiveOperations: true
            )
        )
        #expect(
            !confirmation.isCurrent(
                routerID: routerID,
                generation: generation,
                permitsLiveOperations: false
            )
        )
        #expect(
            !confirmation.isCurrent(
                routerID: routerID,
                generation: UUID(),
                permitsLiveOperations: true
            )
        )
    }

    @Test func actionsProjectionKeepsOnlySupportedExecutableRowsInNativeOrder() {
        let rows = [
            runtimeOperationRow(id: "core-upgrade", status: .supported),
            runtimeOperationRow(id: "memory", status: .unavailable),
            runtimeOperationRow(id: "dns-flush", status: .supported),
            runtimeOperationRow(id: "configuration-reload", status: .supported, actionKey: nil),
            runtimeOperationRow(id: "core-restart", status: .partial),
        ]

        let projection = WorkbenchActionsProjection(runtimeRows: rows) { action in
            action.rawValue == UnifiedControllerAction.testConnection.rawValue
                || action.rawValue == UnifiedControllerAction.reloadRules.rawValue
        }

        #expect(projection.supports(.testConnection))
        #expect(projection.supports(.reloadRules))
        #expect(!projection.supports(.refreshSnapshot))
        #expect(projection.runtimeRows.map(\.id) == ["dns-flush"])
        #expect(projection.lifecycleRows.map(\.id) == ["core-upgrade"])
        #expect(projection.supportedOperationCount == 4)
    }

    @MainActor
    @Test func controllersSelectionUsesTheWindowWorkspaceStore() {
        let profile = profile(name: "Primary", host: "first.example", port: 12_001)
        let store = WorkbenchWorkspaceStore()

        store.update(controllerID: profile.id, destination: .controllers) { workspace in
            workspace.selectedItemID = profile.id.uuidString
        }

        #expect(
            store.workspace(
                controllerID: profile.id,
                destination: .controllers
            ).selectedItemID == profile.id.uuidString
        )
    }

    @Test func diagnosticsCheckResultProjectionKeepsUserFacingValuesInDisplayOrder() {
        let row = CheckResultRow(
            id: "result",
            title: "Controller request",
            state: .partial,
            currentState: "Ready",
            latestResult: "Controller check completed",
            lastChecked: "2026-07-28 18:42:01 +0800",
            nextAction: "Refresh the complete controller snapshot",
            retryAction: "Retry against https://controller.example:9090/full/path",
            reportPolicy: "Exclude credentials and raw response bodies only"
        )

        let fields = WorkbenchDiagnosticsProjection.fields(for: row)

        #expect(
            fields.map(\.id) == [
                "current-state",
                "latest-result",
                "last-checked",
                "next-action",
            ]
        )
        #expect(
            fields.map(\.value) == [
                row.currentState,
                row.latestResult,
                row.lastChecked,
                row.nextAction,
            ]
        )
        #expect(fields.filter(\.monospaced).map(\.id) == ["last-checked"])
    }

    @Test func diagnosticsProjectionOmitsEmptyAndMachineFacingValues() {
        let row = CheckResultRow(
            id: "technical-result",
            title: "Controller request",
            state: .attention,
            currentState: "ready at https://controller.example:9090/full/path",
            latestResult: "connection-id=0123456789abcdef; provider=full-provider-name",
            lastChecked: "   ",
            nextAction: "GET /rules",
            retryAction: "Retry against https://controller.example:9090/full/path",
            reportPolicy: "Exclude credentials and raw response bodies only"
        )

        #expect(WorkbenchDiagnosticsProjection.fields(for: row).isEmpty)
    }

    @Test func diagnosticsVisibilityRemovesUnsupportedItemsFromBothLevels() {
        let capabilityRows = [
            CapabilityMatrixRow(
                id: "supported",
                title: "Supported",
                status: .supported,
                evidence: "ready",
                operationImpact: "visible"
            ),
            CapabilityMatrixRow(
                id: "unavailable",
                title: "Unavailable",
                status: .unavailable,
                evidence: "missing",
                operationImpact: "hidden"
            ),
            CapabilityMatrixRow(
                id: "adapter-source",
                title: "Adapter Source",
                status: .supported,
                evidence: "internal",
                operationImpact: "hidden"
            ),
            CapabilityMatrixRow(
                id: "empty",
                title: "",
                status: .supported,
                evidence: "ready",
                operationImpact: ""
            ),
        ]
        #expect(
            WorkbenchDiagnosticsVisibility.availableCapabilityRows(capabilityRows)
                .map(\.id) == ["supported"]
        )

        let observabilityRows = [
            ObservabilityReadinessRow(
                id: "ready",
                title: "Ready",
                category: "Local",
                state: .ready,
                detail: "ready",
                boundary: "local"
            ),
            ObservabilityReadinessRow(
                id: "future",
                title: "Future",
                category: "Stream",
                state: .futureOptionalStream,
                detail: "future",
                boundary: "optional"
            ),
            ObservabilityReadinessRow(
                id: "unavailable",
                title: "Unavailable",
                category: "Controller",
                state: .unavailable,
                detail: "missing",
                boundary: "unsupported"
            ),
            ObservabilityReadinessRow(
                id: "empty",
                title: "",
                category: "Local",
                state: .ready,
                detail: "",
                boundary: "local"
            ),
        ]
        #expect(
            WorkbenchDiagnosticsVisibility.availableObservabilityRows(observabilityRows)
                .map(\.id) == ["ready"]
        )

        let support = WorkbenchDiagnosticsSupport(
            enhancedSnapshot: true,
            providerUpdate: false,
            delayTest: true,
            connectionClose: false
        )
        let steps = [
            endpointStep(id: "endpoint-profile"),
            endpointStep(id: "endpoint-enhanced-snapshot"),
            endpointStep(id: "endpoint-provider-update"),
            endpointStep(id: "endpoint-delay-test"),
            endpointStep(id: "endpoint-connection-close"),
            EndpointCheckStep(
                id: "empty",
                title: "",
                state: .ready,
                detail: "",
                nextAction: "",
                primaryAction: nil
            ),
        ]
        #expect(
            WorkbenchDiagnosticsVisibility.availableEndpointSteps(
                steps,
                support: support
            ).map(\.id) == [
                "endpoint-profile",
                "endpoint-enhanced-snapshot",
                "endpoint-delay-test",
            ]
        )

        let results = [
            checkResult(id: "profile"),
            checkResult(id: "enhanced-snapshot"),
            checkResult(id: "provider-update"),
            checkResult(id: "delay-test"),
            checkResult(id: "close-connection"),
            checkResult(id: "close-all-connections"),
            CheckResultRow(
                id: "empty",
                title: "",
                state: .notChecked,
                currentState: "key=value",
                latestResult: "GET /rules",
                lastChecked: "",
                nextAction: "",
                retryAction: "",
                reportPolicy: ""
            ),
        ]
        #expect(
            WorkbenchDiagnosticsVisibility.availableCheckResults(
                results,
                support: support
            ).map(\.id) == [
                "profile",
                "enhanced-snapshot",
                "delay-test",
            ]
        )
    }

    private func endpointStep(id: String) -> EndpointCheckStep {
        EndpointCheckStep(
            id: id,
            title: id,
            state: .ready,
            detail: "detail",
            nextAction: "next",
            primaryAction: nil
        )
    }

    private func checkResult(id: String) -> CheckResultRow {
        CheckResultRow(
            id: id,
            title: id,
            state: .ready,
            currentState: "ready",
            latestResult: "ready",
            lastChecked: "now",
            nextAction: "none",
            retryAction: "none",
            reportPolicy: "full"
        )
    }

    private func runtimeOperationRow(
        id: String,
        status: CapabilityStatus,
        actionKey: String? = "action.run"
    ) -> DiagnosticsRuntimeOperationRow {
        DiagnosticsRuntimeOperationRow(
            id: id,
            titleKey: "action.title",
            detailKey: "action.detail",
            sourceKey: "action.source",
            sourceRowID: id,
            systemImage: "bolt",
            status: status,
            nextStepKey: "action.next",
            actionButtonKey: actionKey,
            requiresConfirmation: false,
            confirmationMessageKey: nil,
            isDestructive: false,
            evidence: "ready"
        )
    }

    private func profile(name: String, host: String, port: Int) -> RouterProfile {
        RouterProfile(
            displayName: name,
            scheme: .https,
            host: host,
            port: port,
            secretReference: "keychain:test",
            tlsPolicy: .system,
            controllerKind: .singBoxCompatible,
            surgePlatform: .remoteMac
        )
    }

    private func connectionReport(headline: String) -> ConnectionTestReport {
        ConnectionTestReport(
            summary: .ready,
            headline: headline,
            targetURL: "HTTPS - https://primary.example:12001",
            steps: [
                ConnectionCheckStep(
                    id: "url",
                    title: "URL",
                    value: "https://primary.example:12001",
                    state: .ready
                ),
                ConnectionCheckStep(
                    id: "tls",
                    title: "TLS",
                    value: "System trust",
                    state: .ready
                ),
                ConnectionCheckStep(
                    id: "version",
                    title: "Version",
                    value: "1.12.0",
                    state: .ready
                ),
            ],
            nextStep: "Refresh"
        )
    }
}
