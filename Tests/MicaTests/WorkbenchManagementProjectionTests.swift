import Foundation
import MicaCore
import Testing
@testable import Mica

struct WorkbenchManagementProjectionTests {
    @Test func managementRowsUseOneRootWidthMode() {
        #expect(
            WorkbenchManagementWidthMode(
                availableWidth: MicaTheme.Metrics.wideThreshold - 1
            ) == .compact
        )
        #expect(
            WorkbenchManagementWidthMode(
                availableWidth: MicaTheme.Metrics.wideThreshold
            ) == .regular
        )
        #expect(
            WorkbenchManagementWidthMode(
                availableWidth: MicaTheme.Metrics.wideThreshold + 400
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
                profiles: [first, second],
                query: "",
                controllerTypeLabel: { _ in "Mihomo" }
            ) == second.id
        )
        #expect(
            WorkbenchControllerListProjection.reconciledSelection(
                storedID: UUID(),
                activeID: second.id,
                profiles: [first, second],
                query: "",
                controllerTypeLabel: { _ in "Mihomo" }
            ) == second.id
        )
        #expect(
            WorkbenchControllerListProjection.reconciledSelection(
                storedID: nil,
                activeID: nil,
                profiles: [first, second],
                query: "",
                controllerTypeLabel: { _ in "Mihomo" }
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

    @Test func actionsRecoveryDoesNotCountDisabledRefresh() {
        let router = controllerProfile(
            kind: .autoDetect,
            host: "127.0.0.1"
        )
        let snapshot = WorkbenchActionsProjection.snapshot(
            actionsInput(
                router: router,
                controllerType: .smartProbe,
                state: .failedBeforeFirstSnapshot("Connection refused"),
                capabilities: .probeReadiness,
                canTest: true,
                canRefresh: false
            )
        )

        #expect(snapshot.availability == .recovery)
        #expect(snapshot.executableCount == 0)
        #expect(snapshot.groups.isEmpty)
        #expect(snapshot.recovery?.primaryIntent == .testConnection)
        #expect(snapshot.targetScope == .thisMac)
        #expect(snapshot.showsTargetCorrection)
    }

    @Test func actionsProjectionUsesVerifiedControllerDispatchers() {
        let rows = runtimeRowsForActions()
        let mihomo = WorkbenchActionsProjection.snapshot(
            actionsInput(
                router: controllerProfile(kind: .nikkiMihomoCompatible),
                controllerType: .nikkiMihomoCompatible,
                capabilities: .mihomoCompatible,
                runtimeRows: rows
            )
        )
        #expect(
            mihomo.visibleOperationIDs == [
                "refresh", "reload-rules", "reload-providers",
                "configuration-reload", "geo-resources", "memory",
                "dns-flush", "cache-flush", "core-restart", "core-upgrade",
            ]
        )
        #expect(mihomo.relatedDestinations.isEmpty)

        for (kind, type) in [
            (ControllerKind.mihomoCompatible, UnifiedControllerType.mihomoCompatible),
            (.openClashMihomoCompatible, .openClashMihomoCompatible),
        ] {
            let familySnapshot = WorkbenchActionsProjection.snapshot(
                actionsInput(
                    router: controllerProfile(kind: kind),
                    controllerType: type,
                    capabilities: .mihomoCompatible,
                    runtimeRows: rows
                )
            )
            #expect(familySnapshot.visibleOperationIDs == mihomo.visibleOperationIDs)
        }

        let cmfa = WorkbenchActionsProjection.snapshot(
            actionsInput(
                router: controllerProfile(kind: .cmfaCompatible),
                controllerType: .cmfaCompatible,
                capabilities: .cmfaCompatible,
                runtimeRows: rows
            )
        )
        #expect(
            cmfa.visibleOperationIDs == [
                "refresh", "reload-rules", "reload-providers", "memory",
                "dns-flush", "cache-flush",
            ]
        )

        let singBox = WorkbenchActionsProjection.snapshot(
            actionsInput(
                router: controllerProfile(kind: .singBoxCompatible),
                controllerType: .singBoxCompatible,
                capabilities: .singBoxCompatible,
                runtimeRows: rows
            )
        )
        #expect(singBox.visibleOperationIDs == ["refresh"])
        #expect(!singBox.visibleOperationIDs.contains("memory"))
        #expect(!singBox.relatedDestinations.isEmpty)

        let surge = WorkbenchActionsProjection.snapshot(
            actionsInput(
                router: controllerProfile(kind: .surgeCompatible),
                controllerType: .surgeHTTPAPI,
                capabilities: .surgeHTTPAPI,
                runtimeRows: rows
            )
        )
        #expect(
            surge.visibleOperationIDs == [
                "refresh", "reload-rules", "reload-profile", "dns-flush",
            ]
        )

        let stash = WorkbenchActionsProjection.snapshot(
            actionsInput(
                router: controllerProfile(kind: .stashCompatible),
                controllerType: .stashCompatible,
                capabilities: .stashCompatible,
                runtimeRows: rows
            )
        )
        #expect(stash.visibleOperationIDs == ["refresh", "reload-rules", "reload-providers"])

        let unsupported = WorkbenchActionsProjection.snapshot(
            actionsInput(
                router: controllerProfile(kind: .unsupported),
                controllerType: .unsupported,
                state: .live,
                capabilities: .none,
                runtimeRows: rows,
                canRefresh: false
            )
        )
        #expect(unsupported.availability == .unsupported)
        #expect(unsupported.visibleOperationIDs.isEmpty)
    }

    @Test func actionsExecutableCountTracksTransientReadinessWithoutLosingInventory() {
        let snapshot = WorkbenchActionsProjection.snapshot(
            actionsInput(
                router: controllerProfile(kind: .mihomoCompatible),
                controllerType: .mihomoCompatible,
                capabilities: .mihomoCompatible,
                runtimeRows: runtimeRowsForActions(),
                isBusy: true
            )
        )

        #expect(snapshot.availability == .ready)
        #expect(!snapshot.groups.isEmpty)
        #expect(snapshot.commandCount == snapshot.visibleOperationIDs.count)
        #expect(snapshot.executableCount == 0)
        #expect(snapshot.groups.flatMap(\.commands).allSatisfy { !$0.isEnabled })
    }

    @Test func actionsLayoutUsesCompactSingleColumnOnlyForSparseCommands() {
        for commandCount in 0...4 {
            let narrow = WorkbenchActionsLayoutDecision.resolve(
                commandCount: commandCount,
                availableWidth: 1_200
            )
            #expect(
                narrow.maximumContentWidth
                    == WorkbenchActionsLayoutDecision.compactMaximumWidth
            )
            #expect(!narrow.usesTwoColumns)
        }

        let constrainedDense = WorkbenchActionsLayoutDecision.resolve(
            commandCount: 5,
            availableWidth: 899
        )
        #expect(
            constrainedDense.maximumContentWidth
                == WorkbenchActionsLayoutDecision.denseMaximumWidth
        )
        #expect(!constrainedDense.usesTwoColumns)

        let wideDense = WorkbenchActionsLayoutDecision.resolve(
            commandCount: 5,
            availableWidth: 900
        )
        #expect(
            wideDense.maximumContentWidth
                == WorkbenchActionsLayoutDecision.denseMaximumWidth
        )
        #expect(wideDense.usesTwoColumns)
    }

    @Test func actionsRuntimeObservationMatchesDispatcherFamilies() {
        for controllerType in [
            UnifiedControllerType.mihomoCompatible,
            .nikkiMihomoCompatible,
            .openClashMihomoCompatible,
            .cmfaCompatible,
        ] {
            #expect(controllerType.hasWorkbenchRuntimeOperations)
        }

        for controllerType in [
            UnifiedControllerType.surgeHTTPAPI,
            .singBoxCompatible,
            .stashCompatible,
            .stashCmfaCompatible,
            .smartProbe,
            .unknown,
            .unsupported,
        ] {
            #expect(!controllerType.hasWorkbenchRuntimeOperations)
        }
    }

    @Test func actionsAvailabilitySeparatesCheckingPartialAndUnsupportedStates() {
        let checking = WorkbenchActionsProjection.snapshot(
            actionsInput(
                router: controllerProfile(kind: .autoDetect),
                controllerType: .smartProbe,
                state: .connecting,
                capabilities: .probeReadiness,
                canRefresh: false
            )
        )
        #expect(checking.availability == .checking)
        #expect(checking.groups.isEmpty)
        #expect(checking.recovery?.primaryIntent == nil)

        let partial = WorkbenchActionsProjection.snapshot(
            actionsInput(
                router: controllerProfile(kind: .mihomoCompatible),
                controllerType: .mihomoCompatible,
                state: .partial("Some data is retained"),
                capabilities: .mihomoCompatible,
                runtimeRows: runtimeRowsForActions()
            )
        )
        #expect(partial.availability == .partial)
        #expect(!partial.groups.isEmpty)

        let unresolved = WorkbenchActionsProjection.snapshot(
            actionsInput(
                router: controllerProfile(kind: .unknown),
                controllerType: .unknown,
                capabilities: .none,
                canRefresh: false
            )
        )
        #expect(unresolved.availability == .unsupported)
        #expect(unresolved.groups.isEmpty)
    }

    @Test func actionsEffectiveUnsupportedStateCarriesUnsupportedRecovery() {
        let snapshot = WorkbenchActionsProjection.snapshot(
            actionsInput(
                router: controllerProfile(kind: .mihomoCompatible),
                controllerType: .mihomoCompatible,
                capabilities: .none,
                canRefresh: false
            )
        )

        #expect(snapshot.availability == .unsupported)
        #expect(snapshot.groups.isEmpty)
        #expect(snapshot.recovery?.titleKey == "actions.unsupported_title")
    }

    @Test func targetScopeDistinguishesThisMacNetworkAndExplicitMacLocal() {
        #expect(WorkbenchControllerTargetScope(host: "localhost") == .thisMac)
        #expect(WorkbenchControllerTargetScope(host: "127.8.4.2") == .thisMac)
        #expect(WorkbenchControllerTargetScope(host: "[::1]") == .thisMac)
        #expect(WorkbenchControllerTargetScope(host: "192.168.1.1") == .networkHost)
        #expect(WorkbenchControllerTargetScope(host: "router.lan") == .networkHost)
        #expect(WorkbenchControllerTargetScope(host: "  ") == .unconfigured)

        let macLocal = RouterProfile(
            displayName: "Surge",
            host: "127.0.0.1",
            controllerKind: .surgeCompatible,
            surgePlatform: .macLocal
        )
        #expect(macLocal.permitsThisMacTarget)
        #expect(!macLocal.expectsNetworkControllerTarget)
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

    @Test func diagnosticsControllerFailureSuppressesDuplicateEndpointFailures() {
        let health = controllerHealth(
            summary: .offline,
            statuses: ControllerEndpointKind.allCases.map {
                ($0, ControllerEndpointStatus.failed("Connection refused"))
            }
        )
        let snapshot = WorkbenchDiagnosticsProjection.snapshot(
            diagnosticsInput(
                router: controllerProfile(kind: .autoDetect, host: "127.0.0.1"),
                controllerType: .smartProbe,
                state: .failedBeforeFirstSnapshot("Connection refused"),
                health: health,
                capabilities: .probeReadiness
            )
        )

        #expect(snapshot.overallState == .blocked)
        #expect(snapshot.issues.map(\.id) == ["controller-access"])
        #expect(snapshot.availableAreas.isEmpty)
        #expect(snapshot.targetScope == .thisMac)
        #expect(snapshot.issues.first?.primaryAction == .refresh)
    }

    @Test func diagnosticsProjectionOmitsMachineFacingEvidence() {
        #expect(
            WorkbenchDiagnosticsProjection.displayableText(
                "connection-id=0123456789abcdef; provider=full-provider-name"
            ) == nil
        )
        #expect(WorkbenchDiagnosticsProjection.displayableText("GET /rules") == nil)
        #expect(
            WorkbenchDiagnosticsProjection.displayableText(
                "https://controller.example:9090/full/path"
            ) == nil
        )
        #expect(
            WorkbenchDiagnosticsProjection.displayableText("Connection refused")
                == "Connection refused"
        )
    }

    @Test func diagnosticsUsesCapabilitiesToSuppressUnsupportedFailures() {
        let snapshot = WorkbenchDiagnosticsProjection.snapshot(
            diagnosticsInput(
                router: controllerProfile(kind: .singBoxCompatible),
                controllerType: .singBoxCompatible,
                state: .live,
                lastSuccessAt: Date(timeIntervalSince1970: 2_000_000_000),
                isPaused: true,
                health: controllerHealth(summary: .ready),
                capabilities: .singBoxCompatible,
                rulesState: .unavailable("Rules are unavailable"),
                providersState: .unavailable("Providers are unavailable")
            )
        )

        #expect(snapshot.overallState == .needsAttention)
        #expect(snapshot.issues.map(\.id) == ["presentation-paused"])
        #expect(snapshot.freshness == .paused(Date(timeIntervalSince1970: 2_000_000_001)))
        #expect(snapshot.issues.first?.primaryAction == .resumePresentation)
        #expect(!snapshot.issues.contains { $0.id == "rules-data" || $0.id == "sources-data" })
        #expect(snapshot.availableAreas.map(\.destination).contains(.proxies))
        #expect(!snapshot.availableAreas.map(\.destination).contains(.rules))
        #expect(!snapshot.availableAreas.map(\.destination).contains(.sources))
    }

    @Test func diagnosticsTracksCheckingRetainedPartialAndHealthyStates() {
        let router = controllerProfile(kind: .mihomoCompatible)
        let lastSuccess = Date(timeIntervalSince1970: 2_000_000_000)

        let checking = WorkbenchDiagnosticsProjection.snapshot(
            diagnosticsInput(
                router: router,
                controllerType: .mihomoCompatible,
                state: .connecting,
                health: controllerHealth(summary: .checking),
                capabilities: .mihomoCompatible
            )
        )
        #expect(checking.overallState == .checking)
        #expect(checking.freshness == .checking)
        #expect(checking.issues.isEmpty)
        #expect(checking.availableAreas.isEmpty)

        let retained = WorkbenchDiagnosticsProjection.snapshot(
            diagnosticsInput(
                router: router,
                controllerType: .mihomoCompatible,
                state: .staleReconnecting("Connection timed out"),
                lastSuccessAt: lastSuccess,
                health: controllerHealth(summary: .ready),
                capabilities: .mihomoCompatible
            )
        )
        #expect(retained.overallState == .needsAttention)
        #expect(retained.freshness == .retained(lastSuccess))
        #expect(retained.issues.map(\.id) == ["session-stale"])
        #expect(retained.issues.first?.primaryAction == .refresh)

        let partial = WorkbenchDiagnosticsProjection.snapshot(
            diagnosticsInput(
                router: router,
                controllerType: .mihomoCompatible,
                state: .partial("Only part of the snapshot is available"),
                lastSuccessAt: lastSuccess,
                health: controllerHealth(summary: .partial),
                capabilities: .mihomoCompatible
            )
        )
        #expect(partial.overallState == .needsAttention)
        #expect(partial.freshness == .live(lastSuccess))
        #expect(partial.issues.map(\.id) == ["session-partial"])

        let healthy = WorkbenchDiagnosticsProjection.snapshot(
            diagnosticsInput(
                router: router,
                controllerType: .mihomoCompatible,
                state: .live,
                lastSuccessAt: lastSuccess,
                health: controllerHealth(summary: .ready),
                capabilities: .mihomoCompatible
            )
        )
        #expect(healthy.overallState == .ready)
        #expect(healthy.issues.isEmpty)
        #expect(
            healthy.availableAreas.map(\.destination) == [
                .proxies, .connections, .rules, .sources, .overview, .configuration,
            ]
        )
    }

    @Test func diagnosticsCheckingSuppressesProvisionalFailuresAndAreas() {
        let health = controllerHealth(
            summary: .checking,
            statuses: ControllerEndpointKind.allCases.map {
                ($0, ControllerEndpointStatus.failed("Connection refused"))
            }
        )
        let snapshot = WorkbenchDiagnosticsProjection.snapshot(
            diagnosticsInput(
                router: controllerProfile(kind: .autoDetect),
                controllerType: .smartProbe,
                state: .connecting,
                health: health,
                capabilities: .mihomoCompatible
            )
        )

        #expect(snapshot.overallState == .checking)
        #expect(snapshot.issues.isEmpty)
        #expect(snapshot.availableAreas.isEmpty)
    }

    @Test func diagnosticsProjectedEvidenceUsesSafeFallback() throws {
        let snapshot = WorkbenchDiagnosticsProjection.snapshot(
            diagnosticsInput(
                router: controllerProfile(kind: .mihomoCompatible),
                controllerType: .mihomoCompatible,
                state: .staleReconnecting("GET /rules"),
                lastSuccessAt: Date(timeIntervalSince1970: 2_000_000_000),
                health: controllerHealth(summary: .ready),
                capabilities: .mihomoCompatible
            )
        )

        let issue = try #require(snapshot.issues.first { $0.id == "session-stale" })
        #expect(
            issue.evidence.first?.value
                == MicaStrings.localizedKey(
                    "diagnostics.evidence_unavailable",
                    language: .english
                )
        )
    }

    @Test func diagnosticsRetainedControllerFailureSuppressesEndpointFailures() {
        let lastSuccess = Date(timeIntervalSince1970: 2_000_000_000)
        let health = controllerHealth(
            summary: .offline,
            statuses: ControllerEndpointKind.allCases.map {
                ($0, ControllerEndpointStatus.failed("Connection refused"))
            }
        )
        let snapshot = WorkbenchDiagnosticsProjection.snapshot(
            diagnosticsInput(
                router: controllerProfile(kind: .mihomoCompatible),
                controllerType: .mihomoCompatible,
                state: .failed("Connection refused"),
                lastSuccessAt: lastSuccess,
                health: health,
                capabilities: .mihomoCompatible
            )
        )

        #expect(snapshot.overallState == .needsAttention)
        #expect(snapshot.freshness == .retained(lastSuccess))
        #expect(snapshot.issues.map(\.id) == ["controller-access"])
    }

    @Test func diagnosticsMapsExpectedEndpointFailuresToProductAreas() {
        let health = controllerHealth(
            summary: .partial,
            statuses: [
                (.version, .ready("1.0")),
                (.configs, .ready("Ready")),
                (.proxies, .failed("Policy read failed")),
                (.connections, .ready("Ready")),
                (.rules, .failed("Rule read failed")),
                (.providers, .ready("Ready")),
            ]
        )
        let snapshot = WorkbenchDiagnosticsProjection.snapshot(
            diagnosticsInput(
                router: controllerProfile(kind: .mihomoCompatible),
                controllerType: .mihomoCompatible,
                state: .live,
                lastSuccessAt: Date(timeIntervalSince1970: 2_000_000_000),
                health: health,
                capabilities: .mihomoCompatible
            )
        )

        #expect(snapshot.issues.map(\.id) == ["endpoint-proxies", "endpoint-rules"])
        #expect(!snapshot.availableAreas.map(\.destination).contains(.proxies))
        #expect(!snapshot.availableAreas.map(\.destination).contains(.rules))
        #expect(snapshot.availableAreas.map(\.destination).contains(.connections))
        #expect(snapshot.availableAreas.map(\.destination).contains(.sources))
    }

    @Test func diagnosticsSelectionReconcilesByStableIssueID() {
        let issues = [
            diagnosticIssue(id: "first"),
            diagnosticIssue(id: "second"),
        ]

        #expect(
            WorkbenchDiagnosticsProjection.reconciledSelection(
                currentID: "second",
                issues: issues
            ) == "second"
        )
        #expect(
            WorkbenchDiagnosticsProjection.reconciledSelection(
                currentID: "resolved",
                issues: issues
            ) == "first"
        )
        #expect(
            WorkbenchDiagnosticsProjection.reconciledSelection(
                currentID: "first",
                issues: []
            ) == nil
        )
    }

    @Test func diagnosticsActionsUseSharedLiveCommandAvailability() {
        let blocked = WorkbenchDiagnosticsActionAvailability(
            canRefresh: false,
            canTest: false,
            canTogglePresentationPause: false,
            isPresentationPaused: true,
            hasSelectedController: true,
            isBusy: true
        )

        #expect(!blocked.isEnabled(.refresh))
        #expect(!blocked.isEnabled(.resumePresentation))
        #expect(!blocked.isEnabled(.editController))
        #expect(blocked.isEnabled(.navigate(.connections)))

        let available = WorkbenchDiagnosticsActionAvailability(
            canRefresh: false,
            canTest: true,
            canTogglePresentationPause: true,
            isPresentationPaused: true,
            hasSelectedController: true,
            isBusy: false
        )

        #expect(available.isEnabled(.refresh))
        #expect(available.isEnabled(.resumePresentation))
        #expect(available.isEnabled(.editController))
    }

    @Test func diagnosticsResumeRequiresAnActuallyPausedPresentation() {
        let availability = WorkbenchDiagnosticsActionAvailability(
            canRefresh: true,
            canTest: true,
            canTogglePresentationPause: true,
            isPresentationPaused: false,
            hasSelectedController: true,
            isBusy: false
        )

        #expect(!availability.isEnabled(.resumePresentation))
    }

    private func runtimeOperationRow(
        id: String,
        status: CapabilityStatus,
        actionKey: String? = "action.run",
        isDestructive: Bool = false
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
            requiresConfirmation: isDestructive,
            confirmationMessageKey: isDestructive ? "action.confirm" : nil,
            isDestructive: isDestructive,
            evidence: "ready"
        )
    }

    private func runtimeRowsForActions() -> [DiagnosticsRuntimeOperationRow] {
        [
            runtimeOperationRow(id: "configuration-reload", status: .supported),
            runtimeOperationRow(id: "geo-resources", status: .supported),
            runtimeOperationRow(id: "memory", status: .supported),
            runtimeOperationRow(id: "dns-flush", status: .supported),
            runtimeOperationRow(id: "cache-flush", status: .supported),
            runtimeOperationRow(id: "core-restart", status: .supported, isDestructive: true),
            runtimeOperationRow(id: "core-upgrade", status: .supported, isDestructive: true),
        ]
    }

    private func actionsInput(
        router: RouterProfile,
        controllerType: UnifiedControllerType,
        state: LiveSessionState = .live,
        capabilities: ControllerCapabilities,
        runtimeRows: [DiagnosticsRuntimeOperationRow] = [],
        canTest: Bool = true,
        canRefresh: Bool = true,
        isBusy: Bool = false
    ) -> WorkbenchActionsInput {
        WorkbenchActionsInput(
            router: router,
            generation: UUID(),
            controllerType: controllerType,
            sessionState: state,
            capabilities: capabilities,
            runtimeRows: runtimeRows,
            canTest: canTest,
            canRefresh: canRefresh,
            isBusy: isBusy
        )
    }

    private func diagnosticsInput(
        router: RouterProfile,
        controllerType: UnifiedControllerType,
        state: LiveSessionState,
        lastSuccessAt: Date? = nil,
        isPaused: Bool = false,
        health: ControllerHealthSnapshot,
        capabilities: ControllerCapabilities,
        rulesState: EnhancedSnapshotState = .available,
        providersState: EnhancedSnapshotState = .available,
        liveStreamState: LiveStreamState = .live
    ) -> WorkbenchDiagnosticsInput {
        WorkbenchDiagnosticsInput(
            router: router,
            generation: UUID(),
            detectedKind: router.controllerKind,
            controllerType: controllerType,
            sessionState: state,
            lastSuccessAt: lastSuccessAt,
            isPresentationPaused: isPaused,
            presentationPausedAt: isPaused ? Date(timeIntervalSince1970: 2_000_000_001) : nil,
            health: health,
            capabilities: capabilities,
            rulesState: rulesState,
            providersState: providersState,
            liveStreamState: liveStreamState,
            metadata: .empty,
            language: .english
        )
    }

    private func controllerHealth(
        summary: ControllerHealthSummary,
        statuses: [(ControllerEndpointKind, ControllerEndpointStatus)] = []
    ) -> ControllerHealthSnapshot {
        ControllerHealthSnapshot(
            summary: summary,
            routerName: "Controller",
            checkedAt: Date(timeIntervalSince1970: 2_000_000_002),
            endpoints: ControllerEndpointKind.allCases.map { endpoint in
                ControllerEndpointHealth(
                    endpoint: endpoint,
                    status: statuses.first { $0.0 == endpoint }?.1 ?? .ready("Ready")
                )
            }
        )
    }

    private func diagnosticIssue(id: String) -> WorkbenchDiagnosticsIssue {
        WorkbenchDiagnosticsIssue(
            id: id,
            severity: .warning,
            title: id,
            detail: id,
            affectedDestinations: [.overview],
            evidence: [],
            primaryAction: nil
        )
    }

    private func controllerProfile(
        kind: ControllerKind,
        host: String = "router.example"
    ) -> RouterProfile {
        RouterProfile(
            displayName: kind.label,
            scheme: .http,
            host: host,
            port: 9090,
            controllerKind: kind,
            surgePlatform: .remoteMac
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
