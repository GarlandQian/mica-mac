import Foundation
import MicaCore
import Observation
import SwiftUI

struct OverviewTopologySection: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language
    @State private var structureInput: OverviewTopologyCatalogInput?

    let runtime: OverviewTopologyRuntime
    let minimumFlowHeight: CGFloat
    @Binding var destination: WorkbenchDestination

    var body: some View {
        let request = OverviewTopologyCatalogRequest.observing(appModel)
        let visibleInput = structureInput?.visible(for: request)
        OverviewFlatSection(
            "overview.topology_title",
            systemImage: "point.3.connected.trianglepath.dotted",
            accessory: {
                if let visibleInput {
                    OverviewTopologyHeaderAvailability(
                        generation: request.generation,
                        liveConnectionCount: visibleInput.connections.count,
                        runtime: runtime
                    )
                }
            }
        ) {
            if let visibleInput {
                OverviewTopologyWorkspace(
                    connections: visibleInput.connections,
                    controllerID: visibleInput.request.controllerID,
                    generation: visibleInput.request.generation,
                    revision: visibleInput.catalogRevision,
                    language: language,
                    runtime: runtime,
                    minimumFlowHeight: minimumFlowHeight,
                    destination: $destination
                )
            } else {
                OverviewTopologyLoadingState(language: language)
            }
        }
        .task(id: request) {
            await loadStructureInput(for: request)
        }
    }

    @MainActor
    private func loadStructureInput(
        for request: OverviewTopologyCatalogRequest
    ) async {
        await Task.yield()
        guard !Task.isCancelled,
              OverviewTopologyCatalogRequest.observing(appModel) == request else {
            return
        }
        let catalog = appModel.connectionsCatalog
        guard !Task.isCancelled,
              OverviewTopologyCatalogRequest.observing(appModel) == request else {
            return
        }
        structureInput = OverviewTopologyCatalogInput(
            request: request,
            catalogRevision: catalog.structureRevision,
            connections: catalog.connections
        )
    }
}

struct OverviewTopologyCatalogRequest: Equatable, Sendable {
    let controllerID: RouterProfile.ID?
    let generation: UUID
    let structureRevision: UInt64

    @MainActor
    static func observing(_ appModel: AppModel) -> Self {
        Self(
            controllerID: appModel.selectedRouterID,
            generation: appModel.controllerSessionPresentation.generation,
            structureRevision: appModel.connectionsStructureRevision
        )
    }
}

struct OverviewTopologyCatalogInput: Equatable, Sendable {
    let request: OverviewTopologyCatalogRequest
    let catalogRevision: UInt64
    let connections: [ConnectionSnapshot]

    func visible(
        for currentRequest: OverviewTopologyCatalogRequest
    ) -> Self? {
        guard request.controllerID == currentRequest.controllerID,
              request.generation == currentRequest.generation else {
            return nil
        }
        return self
    }
}

private struct OverviewTopologyLoadingState: View {
    let language: AppLanguage

    var body: some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            ProgressView().controlSize(.small)
            Text(MicaStrings.localizedKey("overview.current_data", language: language))
                .micaThemeFont(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
    }
}

/// Second-bucketed live-signal value retained for the pause/motion projection
/// contract (`motionProjectionIsStaticForPauseInactiveAndReduceMotion`). The flat
/// Mica Ops renderer never threads it into band rendering; band redraws gate on
/// the topology/policy revisions instead (task 08-20).
struct OverviewTopologyLiveSignal: Equatable, Sendable {
    let trafficSecond: Int64?
    let connectionMetricsRevision: UInt64
    let connectionTrafficRevision: UInt64

    init(
        latestTrafficReceivedAt: Date?,
        connectionMetricsRevision: UInt64,
        connectionTrafficRevision: UInt64
    ) {
        trafficSecond = latestTrafficReceivedAt.map {
            Int64($0.timeIntervalSinceReferenceDate.rounded(.down))
        }
        self.connectionMetricsRevision = connectionMetricsRevision
        self.connectionTrafficRevision = connectionTrafficRevision
    }
}

/// Keep freeze/hover dependencies out of the section that owns catalog intake.
/// A populated live graph always has controls, regardless of captured geometry.
struct OverviewTopologyHeaderAvailability: View {
    let generation: UUID
    let liveConnectionCount: Int
    let runtime: OverviewTopologyRuntime

    var body: some View {
        if Self.showsControls(
            generation: generation,
            liveConnectionCount: liveConnectionCount,
            runtime: runtime
        ) {
            OverviewTopologyHeaderControls(runtime: runtime)
        }
    }

    static func showsControls(
        generation: UUID,
        liveConnectionCount: Int,
        runtime: OverviewTopologyRuntime
    ) -> Bool {
        liveConnectionCount > 0 || runtime.presentationState(
            generation: generation,
            liveConnectionCount: liveConnectionCount,
            liveRevision: 0
        ).showsControls
    }
}

private struct OverviewTopologyHeaderControls: View {
    @Environment(\.micaAppLanguage) private var language

    let runtime: OverviewTopologyRuntime

    var body: some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            if runtime.focusedPaths != nil || runtime.displayMode == .complete {
                Button {
                    runtime.returnToOverview()
                } label: {
                    Label(MicaStrings.localizedKey("overview.topology_back_overview", language: language), systemImage: "arrow.left")
                }
                .buttonStyle(.borderless)
            } else {
                Button {
                    runtime.showCompleteGraph()
                } label: {
                    Label(MicaStrings.localizedKey("overview.topology_view_all", language: language), systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
            }
            if runtime.isPaused {
                Text(
                    MicaStrings.localizedKey(
                        "overview.chart_paused",
                        language: language
                    )
                )
                .micaThemeFont(.caption, weight: .semibold)
                .foregroundStyle(MicaTheme.statusWarning)
            }
            WorkbenchIconCommand(
                titleKey: runtime.isPaused
                    ? "live.resume_updates"
                    : "live.pause_updates",
                systemImage: runtime.isPaused ? "play" : "pause"
            ) {
                runtime.togglePause()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct OverviewTopologyWorkspace: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore

    let connections: [ConnectionSnapshot]
    let controllerID: RouterProfile.ID?
    let generation: UUID
    let revision: UInt64
    let language: AppLanguage
    let runtime: OverviewTopologyRuntime
    let minimumFlowHeight: CGFloat
    @Binding var destination: WorkbenchDestination

    var body: some View {
        let presentationState = runtime.presentationState(
            generation: generation,
            liveConnectionCount: connections.count,
            liveRevision: revision
        )
        if presentationState.showsEmptyState {
            OverviewInlineState(
                titleKey: "overview.topology_empty",
                detailKey: "overview.topology_empty_detail"
            )
        } else {
            let resolvedMinimumFlowHeight = Int(minimumFlowHeight.rounded())
            let request = OverviewTopologyRequest(
                generation: generation,
                revision: presentationState.revision,
                availableWidth: runtime.availableWidth,
                minimumFlowHeight: resolvedMinimumFlowHeight,
                displayMode: runtime.displayMode,
                languageID: language.rawValue
            )
            let visibleTopologyIsEmpty = runtime.presentation.flatMap { presentation in
                presentation.canRemainVisible(whileResolving: request)
                    ? presentation.topology.isEmpty
                    : nil
            }
            // A resolved overview already has a content-sized canvas. Reserving
            // the whole window budget here would leave the same empty space
            // below a sparse graph and push the trends out of a short window.
            let reservedMinimumHeight = request.displayMode == .overview ? nil : OverviewTopologyHeightReservation.minimumHeight(
                visibleTopologyIsEmpty: visibleTopologyIsEmpty,
                requestedMinimum: resolvedMinimumFlowHeight
            )

            topologyBody(for: request)
                .frame(
                    minHeight: reservedMinimumHeight.map(CGFloat.init),
                    alignment: .top
                )
                .task(id: request) {
                    await rebuildPresentation(for: request)
                }
                .onChange(of: request.generation) { _, _ in
                    runtime.returnToOverview()
                    runtime.interaction.reset()
                }
                .onChange(of: runtime.interaction.snapshot) { _, snapshot in
                    syncInspectorSelection(with: snapshot)
                }
                .onGeometryChange(for: Int.self) { geometry in
                    let boundedWidth = max(geometry.size.width, 1)
                    return max(Int((boundedWidth / 8).rounded(.down)) * 8, 1)
                } action: { nextAvailableWidth in
                    guard runtime.availableWidth != nextAvailableWidth else { return }
                    runtime.availableWidth = nextAvailableWidth
                }
        }
    }

    @ViewBuilder
    private func topologyBody(for request: OverviewTopologyRequest) -> some View {
        if let presentation = runtime.presentation,
           presentation.canRemainVisible(whileResolving: request) {
            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space3) {
                if let focus = runtime.focusedPaths,
                   focus.structure.generation == generation {
                    OverviewTopologyFocusedPathsView(
                        focus: focus,
                        language: language,
                        canNavigate: focus.canNavigate(generation: generation, revision: revision),
                        onOpenPath: openPathInConnections,
                        onReturn: runtime.returnToOverview
                    )
                    .frame(height: canvasHeight)
                } else if presentation.diagram.isEmpty {
                    VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                        OverviewTopologyIdleSummary(
                            connectionCount: presentation.topology.connectionCount,
                            unavailablePathCount: presentation.topology.routeUnavailableCount,
                            language: language
                        )
                        OverviewInlineState(
                            titleKey: "overview.topology_empty",
                            detailKey: "overview.topology_empty_detail"
                        )

                        ScrollView {
                            OverviewTopologyPathRows(
                                paths: presentation.topology.paths,
                                language: language,
                                interaction: runtime.interaction,
                                onOpenPath: openPathInConnections
                            )
                        }
                        .frame(maxHeight: canvasHeight - 100)
                    }
                    .accessibilityRepresentation {
                        OverviewTopologyAccessibilityRepresentation(
                            paths: presentation.topology.paths,
                            structure: presentation.request.diagramStructure,
                            topologyIndex: presentation.index,
                            policyCache: runtime.policyInspectionCache,
                            language: language,
                            interaction: runtime.interaction,
                            onOpenPath: openPathInConnections,
                            onOpenProxies: openProxies(for:)
                        )
                    }
                } else {
                    if presentation.request.displayMode == .overview {
                        overviewSummary(presentation)
                    }
                    OverviewTopologyViewport(
                        topology: presentation.diagram,
                        request: presentation.request,
                        index: presentation.diagramIndex,
                        layout: presentation.layout,
                        language: language,
                        runtime: runtime,
                        interaction: runtime.interaction,
                        viewportHeight: OverviewTopologyViewportSizing.height(
                            displayMode: presentation.request.displayMode,
                            requestedHeight: minimumFlowHeight,
                            contentHeight: presentation.layout.size.height
                        ),
                        originalPaths: presentation.topology.paths,
                        onOpenPath: openPathInConnections,
                        onOpenProxies: openProxies(for:)
                    )
                }
            }
        } else {
            HStack(spacing: MicaTheme.Spacing.space2) {
                ProgressView().controlSize(.small)
                Text(MicaStrings.localizedKey("overview.current_data", language: language))
                    .micaThemeFont(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        }
    }

    private var canvasHeight: CGFloat {
        min(max(minimumFlowHeight, 280), 500)
    }

    private func overviewSummary(_ presentation: OverviewTopologyPresentation) -> some View {
        HStack(alignment: .top, spacing: MicaTheme.Spacing.space2) {
            Text(MicaStrings.localized("overview.topology_summary_count \(presentation.topology.connectionCount)", language: language))
            if presentation.summary.mergedNameCount > 0 {
                Text("·")
                Text(MicaStrings.localized("overview.topology_merged_count \(presentation.summary.mergedNameCount) \(presentation.summary.mergedConnectionCount)", language: language))
            }
        }
        .micaThemeFont(.caption)
        .foregroundStyle(MicaTheme.textSecondary)
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private func rebuildPresentation(for request: OverviewTopologyRequest) async {
        do {
            let nextPresentation = try await runtime.presentationCache.resolve(
                request: request,
                connections: connections
            )
            guard !Task.isCancelled else { return }
            runtime.interaction.configure(
                structure: nextPresentation.request.diagramStructure,
                index: nextPresentation.diagramIndex
            )
            runtime.presentation = nextPresentation
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            if runtime.presentation?.request.generation != request.generation {
                runtime.presentation = nil
            }
        }
    }

    private func openPathInConnections(_ path: ConnectionTopology.PathRecord) {
        guard appModel.controllerSessionPresentation.generation == generation,
              runtime.presentation?.request.revision == appModel.connectionsStructureRevision,
              appModel.selectedRouterID == controllerID else { return }
        if let controllerID {
            workspaceStore.stageConnectionNavigation(
                WorkbenchConnectionNavigationSelection(
                    controllerID: controllerID,
                    generation: generation,
                    sourceIndex: path.sourceIndex,
                    reportedConnectionID: path.reportedConnectionID
                )
            )
        }
        destination = .connections
    }

    private func openProxies(for node: ConnectionTopology.Node) {
        guard let target = proxyNavigationTarget(for: node) else { return }
        workspaceStore.stageProxyNavigation(target)
        destination = .proxies
    }

    private func proxyNavigationTarget(
        for node: ConnectionTopology.Node
    ) -> WorkbenchProxyNavigationSelection? {
        guard let controllerID,
              case .policyHop = node.columnID else {
            return nil
        }
        let policyIndex = runtime.policyInspectionCache.resolve(
            revision: appModel.policyGroupCatalogRevision,
            catalog: appModel.policyGroupCatalog
        )
        switch policyIndex.resolve(name: node.name) {
        case .group(let group):
            let nodeName = group.selected.proxyNonBlank
                ?? group.members.lazy.compactMap(\.proxyNonBlank).first
            guard let nodeName else { return nil }
            return ProxyProjection.navigationSelection(
                controllerID: controllerID,
                generation: generation,
                groupOccurrenceID: group.occurrenceID,
                nodeName: nodeName
            )
        case .member(let member):
            return ProxyProjection.navigationSelection(
                controllerID: controllerID,
                generation: generation,
                groupOccurrenceID: member.groupOccurrenceID,
                nodeName: member.name
            )
        case .ambiguous, .missing:
            return nil
        }
    }

    /// Phase 3.3: pinned policy-node selection opens the workspace inspector
    /// with the policy group/member identity; clearing the topology selection
    /// (Escape, blank-canvas activation, session reset) clears the inspector's
    /// policy content through the store's existing plumbing. Hover never
    /// touches the inspector - it only drives the standard tooltip.
    private func syncInspectorSelection(
        with snapshot: OverviewTopologyInteractionSnapshot
    ) {
        guard let selection = snapshot.activeSelection else {
            workspaceStore.clearInspectorSelection(ownedBy: .overview)
            return
        }
        if runtime.displayMode == .overview {
            guard snapshot.isPinned, runtime.focusedPaths == nil,
                  let presentation = runtime.presentation,
                  presentation.request.generation == generation else { return }
            workspaceStore.clearInspectorSelection(ownedBy: .overview)
            runtime.focusPaths(for: selection, presentation: presentation, language: language)
            return
        }
        guard snapshot.isPinned,
              case .node(let nodeID) = selection,
              let node = runtime.presentation?.index.node(id: nodeID),
              case .policyHop = node.columnID else {
            return
        }
        let policyIndex = runtime.policyInspectionCache.resolve(
            revision: appModel.policyGroupCatalogRevision,
            catalog: appModel.policyGroupCatalog
        )
        switch policyIndex.resolve(name: node.name) {
        case .group(let group):
            workspaceStore.selectInspector(
                .proxyGroup(
                    groupName: group.name,
                    groupOccurrenceID: group.occurrenceID
                ),
                from: .overview
            )
        case .member(let member):
            workspaceStore.selectInspector(
                .proxyNode(
                    groupName: member.groupName,
                    groupOccurrenceID: member.groupOccurrenceID,
                    nodeName: member.name
                ),
                from: .overview
            )
        case .ambiguous, .missing:
            workspaceStore.selectInspector(
                .proxyGroup(groupName: node.name, groupOccurrenceID: nil),
                from: .overview
            )
        }
    }
}

private struct OverviewTopologyViewport: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState

    let topology: ConnectionTopology
    let request: OverviewTopologyRequest
    let index: OverviewTopologyIndex
    let layout: OverviewTopologyLayout
    let language: AppLanguage
    let runtime: OverviewTopologyRuntime
    let interaction: OverviewTopologyInteractionState
    let viewportHeight: CGFloat
    let originalPaths: [ConnectionTopology.PathRecord]
    let onOpenPath: (ConnectionTopology.PathRecord) -> Void
    let onOpenProxies: (ConnectionTopology.Node) -> Void

    @State private var scrollPosition = ScrollPosition(x: 0)
    @State private var viewportGeometry = OverviewTopologyViewportGeometry()

    var body: some View {
        let _ = MicaPerformanceObservation.recordDebug(.topologyViewportEvaluation)
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            topologyGraph
                .accessibilityRepresentation {
                    if request.displayMode == .overview {
                        overviewAccessibility
                    } else {
                        OverviewTopologyAccessibilityRepresentation(
                            paths: originalPaths,
                            structure: request.diagramStructure,
                            topologyIndex: index,
                            policyCache: runtime.policyInspectionCache,
                            language: language,
                            interaction: interaction,
                            onOpenPath: onOpenPath,
                            onOpenProxies: onOpenProxies
                        )
                    }
                }
        }
    }

    private var overviewAccessibility: some View {
        VStack {
            ForEach(topology.columns) { column in
                Text(OverviewTopologyProjection.columnTitle(column.id, language: language))
                ForEach(column.nodes) { node in
                    Button {
                        interaction.togglePinnedSelection(.node(node.id))
                    } label: {
                        Text(verbatim: "\(node.name), \(node.connectionCount)")
                    }
                    .accessibilityHint(MicaStrings.localizedKey("overview.topology_related_paths", language: language))
                }
            }
            Text(MicaStrings.localizedKey("overview.topology_related_paths", language: language))
            ForEach(topology.edges) { edge in
                Button {
                    interaction.togglePinnedSelection(.edge(edge.id))
                } label: {
                    Text(verbatim: "\(edge.sourceName) → \(edge.targetName), \(edge.connectionCount)")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Standard hover tooltip carrying the exact label and factual route detail.
    /// Pinned policy fields continue to live in the workspace inspector.
    private var hoverTooltip: String? {
        let snapshot = interaction.snapshot
        guard snapshot.isHovering, let selection = snapshot.activeSelection else {
            return nil
        }
        let label = OverviewTopologyProjection.selectionLabel(
            selection,
            in: index,
            language: language
        )
        let description: String
        if request.displayMode == .overview {
            let count: Int
            switch selection {
            case .node(let id): count = index.node(id: id)?.connectionCount ?? 0
            case .edge(let id): count = index.edge(id: id)?.connectionCount ?? 0
            case .path: count = 1
            }
            description = MicaStrings.localized("overview.topology_summary_count \(count)", language: language)
        } else {
            description = OverviewTopologyProjection.selectionDescription(selection, in: index, language: language)
        }
        return "\(label)\n\(description)"
    }

    private var topologyGraph: some View {
        // Task 08-23 R10: when long chains widen the graph past the panel the
        // viewport scrolls horizontally; the width floor keeps the content
        // pinned to the full panel width otherwise.
        ScrollView(request.displayMode == .overview ? [.vertical] : [.horizontal, .vertical]) {
            LazyVStack(spacing: 0) {
                ForEach(layout.renderBands) { band in
                    OverviewTopologyBandLayers(
                        request: request,
                        band: band,
                        layout: layout,
                        language: language,
                        allowsMotion: allowsMotion,
                        policyStatusRevision: appModel.policyGroupCatalogRevision,
                        nodeStatusByID: nodeStatusByID,
                        interaction: interaction
                    )
                    .equatable()
                }
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .frame(
                width: max(layout.size.width, CGFloat(request.availableWidth)),
                alignment: .center
            )
            .frame(
                minHeight: viewportHeight,
                alignment: request.displayMode == .overview ? .top : .center
            )
        }
        .scrollPosition($scrollPosition)
        .scrollIndicators(
            hasHorizontalOverflow ? .visible : .hidden,
            axes: .horizontal
        )
        .onScrollGeometryChange(for: CGRect.self) { geometry in
            geometry.visibleRect
        } action: { previous, current in
            viewportGeometry.update(current)
            if previous.width <= 0 || previous.size != current.size {
                revealCurrentSelection(in: current)
            }
        }
        .onChange(of: viewportSelection) { _, state in
            guard state.isPinned else { return }
            revealSelection(state.selection, in: viewportGeometry.visibleRect)
        }
        .frame(height: viewportHeight)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(
            MicaTheme.surface,
            in: RoundedRectangle(
                cornerRadius: MicaTheme.Shape.panelRadius,
                style: .continuous
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: MicaTheme.Shape.panelRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: MicaTheme.Shape.panelRadius,
                style: .continuous
            )
            .strokeBorder(
                MicaTheme.separator,
                lineWidth: MicaTheme.Shape.hairline
            )
        }
        .help(hoverTooltip ?? "")
        .focusable()
        .onMoveCommand(perform: movePathSelection)
        .onExitCommand {
            interaction.clearSelection()
        }
        .contextMenu {
            topologyContextMenu
        }
    }

    @ViewBuilder
    private var topologyContextMenu: some View {
        let snapshot = interaction.snapshot

        Button {
            interaction.movePathSelection(by: -1)
        } label: {
            Label(
                MicaStrings.localizedKey(
                    "overview.topology_previous_path",
                    language: language
                ),
                systemImage: "chevron.up"
            )
        }
        .disabled(!interaction.canMovePath(by: -1))

        Button {
            interaction.movePathSelection(by: 1)
        } label: {
            Label(
                MicaStrings.localizedKey(
                    "overview.topology_next_path",
                    language: language
                ),
                systemImage: "chevron.down"
            )
        }
        .disabled(!interaction.canMovePath(by: 1))

        if let selection = snapshot.activeSelection {
            Divider()

            Button {
                interaction.togglePinnedSelection(selection)
            } label: {
                Label(
                    MicaStrings.localizedKey(
                        snapshot.isPinned
                            ? "overview.topology_unpin_selection"
                            : "overview.topology_pin_selection",
                        language: language
                    ),
                    systemImage: snapshot.isPinned
                        ? MicaSymbols.Command.unpin
                        : "pin"
                )
            }

            if snapshot.highlight.paths.count == 1,
               let path = snapshot.highlight.paths.first {
                Button {
                    onOpenPath(path)
                } label: {
                    Label(
                        MicaStrings.localizedKey(
                            WorkbenchDestination.connections.titleKey,
                            language: language
                        ),
                        systemImage: "arrow.right"
                    )
                }
            }

            if request.displayMode == .complete, let policyNode = resolvablePolicyNode(for: selection) {
                Button { onOpenProxies(policyNode) } label: {
                    Label(
                        MicaStrings.localizedKey(
                            WorkbenchDestination.proxies.titleKey,
                            language: language
                        ),
                        systemImage: WorkbenchDestination.proxies.symbolName
                    )
                }
            }

            Button {
                interaction.clearSelection()
            } label: {
                Label(
                    MicaStrings.localizedKey(
                        "overview.topology_clear_selection",
                        language: language
                    ),
                    systemImage: MicaSymbols.Command.close
                )
            }
        }
    }

    private func movePathSelection(_ direction: MoveCommandDirection) {
        switch direction {
        case .up, .left:
            interaction.movePathSelection(by: -1)
        case .down, .right:
            interaction.movePathSelection(by: 1)
        default:
            break
        }
    }

    private var viewportSelection: OverviewTopologyViewportSelection {
        let snapshot = interaction.snapshot
        return OverviewTopologyViewportSelection(
            selection: snapshot.activeSelection,
            isPinned: snapshot.isPinned
        )
    }

    private var hasHorizontalOverflow: Bool {
        let viewportWidth = viewportGeometry.size.width > 0
            ? viewportGeometry.size.width
            : CGFloat(request.availableWidth)
        return layout.size.width > viewportWidth + 1
    }

    private func revealCurrentSelection(in visibleRect: CGRect) {
        let state = viewportSelection
        guard state.isPinned else { return }
        revealSelection(state.selection, in: visibleRect)
    }

    private func revealSelection(
        _ selection: OverviewTopologySelection?,
        in visibleRect: CGRect
    ) {
        guard let target = OverviewTopologyViewportTargetResolver.target(
            for: selection,
            index: index,
            layout: layout
        ) else { return }
        let offsetX = OverviewTopologyViewportTargetResolver.contentOffsetX(
            for: target,
            visibleRect: visibleRect,
            contentWidth: layout.size.width
        )
        let offsetY = OverviewTopologyViewportTargetResolver.contentOffsetY(
            for: target,
            visibleRect: visibleRect,
            contentHeight: layout.size.height
        )
        guard offsetX != nil || offsetY != nil else { return }
        let point = CGPoint(x: offsetX ?? visibleRect.minX, y: offsetY ?? visibleRect.minY)

        if reduceMotion {
            scrollPosition.scrollTo(point: point)
        } else {
            withAnimation(MicaTheme.Motion.reveal) {
                scrollPosition.scrollTo(point: point)
            }
        }
    }

    private func resolvablePolicyNode(
        for selection: OverviewTopologySelection
    ) -> ConnectionTopology.Node? {
        guard case .node(let nodeID) = selection,
              let node = index.node(id: nodeID),
              case .policyHop = node.columnID else {
            return nil
        }
        let policyIndex = runtime.policyInspectionCache.resolve(
            revision: appModel.policyGroupCatalogRevision,
            catalog: appModel.policyGroupCatalog
        )
        switch policyIndex.resolve(name: node.name) {
        case .group(let group):
            return group.selected.proxyNonBlank != nil
                || group.members.contains { $0.proxyNonBlank != nil }
                ? node
                : nil
        case .member:
            return node
        case .ambiguous, .missing:
            return nil
        }
    }

    /// State-change motion gate (design.md §2): Reduce Motion, a paused stream,
    /// and an inactive window all render fully static.
    private var allowsMotion: Bool {
        !reduceMotion
            && controlActiveState != .inactive
            && !runtime.isPaused
            && !appModel.controllerSessionPresentation.controls.dashboardUpdatesPaused
    }

    /// Controller-reported status per node, memoized on the runtime keyed by
    /// (policy catalog revision, topology revision): telemetry-only updates
    /// flip neither key, so they never re-resolve the catalog nor invalidate
    /// the band equality gate (task 08-20 R5).
    private var nodeStatusByID: [String: MicaTheme.Status] {
        guard request.displayMode == .complete else { return [:] }
        return runtime.nodeStatuses(
            topology: topology,
            topologyRevision: request.revision,
            policyRevision: appModel.policyGroupCatalogRevision,
            catalog: appModel.policyGroupCatalog
        )
    }
}

/// Scrolling changes the exact rect used by keyboard reveal, but does not change
/// the graph's layout or horizontal-overflow indicator. Observe only the size;
/// retain pixel-accurate offsets without invalidating all band inputs per frame.
@MainActor
@Observable
final class OverviewTopologyViewportGeometry {
    private(set) var size = CGSize.zero
    @ObservationIgnored private(set) var visibleRect = CGRect.zero

    func update(_ rect: CGRect) {
        visibleRect = rect
        if size != rect.size {
            size = rect.size
        }
    }
}

private struct OverviewTopologyViewportSelection: Equatable {
    let selection: OverviewTopologySelection?
    let isPinned: Bool
}

private struct OverviewTopologyIdleSummary: View {
    let connectionCount: Int
    let unavailablePathCount: Int
    let language: AppLanguage

    var body: some View {
        HStack(spacing: MicaTheme.Spacing.space4) {
            metric(
                value: connectionCount,
                titleKey: "overview.connection_count"
            )

            if unavailablePathCount > 0 {
                Divider()
                    .frame(height: 32)
                metric(
                    value: unavailablePathCount,
                    titleKey: "overview.topology_unavailable_paths"
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, MicaTheme.Spacing.space3)
        .padding(.vertical, MicaTheme.Spacing.space2)
        .accessibilityElement(children: .combine)
    }

    private func metric(value: Int, titleKey: String) -> some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
            Text(verbatim: value.formatted())
                .micaThemeFont(.dataTitle, weight: .semibold)
                .textSelection(.enabled)
            Text(MicaStrings.localizedKey(titleKey, language: language))
                .micaThemeFont(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct OverviewTopologyPathRows: View {
    let paths: [ConnectionTopology.PathRecord]
    let language: AppLanguage
    let interaction: OverviewTopologyInteractionState
    let onOpenPath: (ConnectionTopology.PathRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            HStack(spacing: MicaTheme.Spacing.space2) {
                WorkbenchSymbol(
                    systemName: "point.3.connected.trianglepath.dotted",
                    font: .caption.weight(.semibold),
                    frameSize: 16
                )
                Text(
                    MicaStrings.localizedKey(
                        "dashboard.chain_label",
                        language: language
                    )
                )
                .micaThemeFont(.caption, weight: .semibold)
                Text(verbatim: paths.count.formatted())
                    .micaThemeFont(.dataCaption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            LazyVStack(spacing: 0) {
                ForEach(paths) { path in
                    pathRow(path)
                    if path.id != paths.last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pathRow(
        _ path: ConnectionTopology.PathRecord
    ) -> some View {
        let snapshot = interaction.snapshot
        let isActive = snapshot.activeSelection == .path(path.id)
        let isPinned = isActive && snapshot.isPinned

        return HStack(alignment: .top, spacing: MicaTheme.Spacing.space2) {
            Button {
                interaction.togglePinnedPath(path.id)
            } label: {
                HStack(alignment: .top, spacing: MicaTheme.Spacing.space2) {
                    Image(systemName: isPinned ? "pin.fill" : "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(isActive ? MicaTheme.accent : .secondary)
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            verbatim: OverviewTopologyProjection.pathLabel(
                                path,
                                language: language
                            )
                        )
                        .micaThemeFont(.label, weight: .medium)
                        .textSelection(.enabled)
                        Text(
                            verbatim: OverviewTopologyProjection.pathDescription(
                                path,
                                language: language
                            )
                        )
                        .micaThemeFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isPinned ? .isSelected : [])
            .accessibilityHint(
                MicaStrings.localizedKey(
                    isPinned
                        ? "overview.topology_unpin_selection"
                        : "overview.topology_pin_selection",
                    language: language
                )
            )

            WorkbenchIconCommand(
                titleKey: WorkbenchDestination.connections.titleKey,
                systemImage: "arrow.right"
            ) {
                onOpenPath(path)
            }
        }
        .padding(.horizontal, MicaTheme.Spacing.space2)
        .padding(.vertical, MicaTheme.Spacing.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isActive ? MicaTheme.accent.opacity(0.14) : .clear)
        .contentShape(Rectangle())
    }
}

private struct OverviewTopologyBandLayers: View, @MainActor Equatable {
    let request: OverviewTopologyRequest
    let band: OverviewTopologyLayout.RenderBand
    let layout: OverviewTopologyLayout
    let language: AppLanguage
    let allowsMotion: Bool
    let policyStatusRevision: UInt64
    let nodeStatusByID: [String: MicaTheme.Status]
    let interaction: OverviewTopologyInteractionState

    /// Redraw gate (task 08-20 R5): the status dictionary is deliberately not
    /// compared - its UInt64 revision stands in. Telemetry ticks flip neither
    /// the topology revision nor the policy revision, so they never invalidate
    /// a band; selection changes still propagate through the interaction
    /// reference's observation.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.request == rhs.request
            && lhs.band.id == rhs.band.id
            && lhs.language == rhs.language
            && lhs.allowsMotion == rhs.allowsMotion
            && lhs.policyStatusRevision == rhs.policyStatusRevision
            && lhs.interaction === rhs.interaction
    }

    var body: some View {
        // F1 (trellis-check): tints must come from the FULL layout, not the
        // band slice - edges are admitted to every 352pt band they cross
        // while nodes only appear in one, so a band-local lookup misses
        // cross-band endpoints and seams the gradients at band borders.
        // Derived from layout (== request), so the == revision gate still
        // covers it.
        let tintByNodeID = Dictionary(
            uniqueKeysWithValues: layout.nodes.map { node in
                (
                    node.node.id,
                    OverviewTopologyProjection.columnTint(for: node.node.columnID)
                )
            }
        )
        let density = OverviewTopologyDensityStyle(edgeCount: layout.edges.count, nodeCount: layout.nodes.count)
        ZStack {
            OverviewTopologyBaseBand(
                request: request,
                band: band,
                allowsMotion: allowsMotion,
                nodeStatusByID: nodeStatusByID,
                tintByNodeID: tintByNodeID,
                density: density,
                interaction: interaction
            )
            .equatable()

            OverviewTopologyLabelBand(
                band: band,
                language: language,
                isSummary: request.displayMode == .overview,
                interaction: interaction
            )

            OverviewTopologyHitBand(
                request: request,
                band: band,
                layout: layout,
                interaction: interaction
            )
            .equatable()
        }
        .frame(
            width: band.bounds.width,
            height: band.bounds.height,
            alignment: .topLeading
        )
        .clipped()
    }
}

/// Single drawing layer (task 08-20 R6): one opaque, linear-composited Canvas
/// paints the panel base, the tiered edges, and the node bars - including the
/// accent highlight pass for the active selection. The previous overlay-dim +
/// second-Canvas highlight layer is gone, and no text is resolved here any
/// more (labels live in `OverviewTopologyLabelBand`).
private struct OverviewTopologyBaseBand: View, @MainActor Equatable {
    let request: OverviewTopologyRequest
    let band: OverviewTopologyLayout.RenderBand
    let allowsMotion: Bool
    let nodeStatusByID: [String: MicaTheme.Status]
    /// Full-layout column tints (built by the band layers from `layout`).
    /// Color is not Equatable, but the map is a pure function of `request`,
    /// so == gating on `request` remains exact.
    let tintByNodeID: [String: Color]
    let density: OverviewTopologyDensityStyle
    let interaction: OverviewTopologyInteractionState

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.request == rhs.request
            && lhs.band.id == rhs.band.id
            && lhs.allowsMotion == rhs.allowsMotion
            && lhs.nodeStatusByID == rhs.nodeStatusByID
            && lhs.interaction === rhs.interaction
    }

    var body: some View {
        let snapshot = interaction.snapshot
        let statusByID = nodeStatusByID
        let tintByNodeID = tintByNodeID
        Canvas(
            opaque: true,
            colorMode: .linear,
            rendersAsynchronously: true
        ) { context, size in
            MicaPerformanceObservation.recordDebug(
                .topologyCanvasPresentation,
                metadata: MicaPerformanceMetadata(
                    count: UInt64(band.nodes.count + band.edges.count),
                    revision: request.revision
                )
            )
            MicaPerformanceObservation.recordDebug(
                .topologyBasePresentation,
                metadata: MicaPerformanceMetadata(
                    count: UInt64(band.nodes.count + band.edges.count),
                    revision: request.revision
                )
            )
            // Panel base fill keeps the opaque canvas indistinguishable from
            // the surrounding surface panel.
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(MicaTheme.surface)
            )
            context.translateBy(x: 0, y: -band.bounds.minY)

            if !band.columns.isEmpty {
                context.fill(
                    Path(CGRect(x: 0, y: 0, width: size.width, height: OverviewTopologyLayout.columnHeaderHeight)),
                    with: .color(MicaTheme.Topology.headerSurface)
                )
                context.fill(
                    Path(CGRect(x: 0, y: OverviewTopologyLayout.columnHeaderHeight, width: size.width, height: 0.5)),
                    with: .color(MicaTheme.separator)
                )
            }

            let highlightedEdgeIDs = snapshot.highlight.edgeIDs
            let highlightedNodeIDs = snapshot.highlight.nodeIDs
            let isDimmed = snapshot.activeSelection != nil

            // Ordinary edges carry stage identity with density-bounded ink.
            for edge in band.edges where !highlightedEdgeIDs.contains(edge.edge.id) {
                OverviewTopologyDrawing.drawEdge(
                    edge,
                    sourceTint: tintByNodeID[edge.edge.sourceID]
                        ?? MicaTheme.textTertiary,
                    targetTint: tintByNodeID[edge.edge.targetID]
                        ?? MicaTheme.textTertiary,
                    density: density,
                    isDimmed: isDimmed,
                    in: &context
                )
            }
            // Pass 2: the single dominant trajectory redraws in accent.
            if isDimmed {
                MicaPerformanceObservation.recordDebug(
                    .topologyHighlightPresentation,
                    metadata: MicaPerformanceMetadata(
                        count: UInt64(
                            highlightedNodeIDs.count + highlightedEdgeIDs.count
                        ),
                        revision: request.revision
                    )
                )
                for edge in band.edges where highlightedEdgeIDs.contains(edge.edge.id) {
                    OverviewTopologyDrawing.drawEdge(
                        edge,
                        density: density,
                        isHighlighted: true,
                        in: &context
                    )
                }
            }
            // All cards paint last so even a highlighted route cannot cross a
            // name in another column. Edge ports remain at the card boundary.
            for node in band.nodes {
                OverviewTopologyDrawing.drawNode(
                    node,
                    status: statusByID[node.node.id] ?? .neutral,
                    tint: tintByNodeID[node.node.id] ?? MicaTheme.textTertiary,
                    isDimmed: isDimmed && !highlightedNodeIDs.contains(node.node.id),
                    isHighlighted: highlightedNodeIDs.contains(node.node.id),
                    in: &context
                )
            }
        }
        .accessibilityHidden(true)
        .micaStateChangeAnimation(
            allowsMotion ? MicaTheme.Motion.stateChange : nil,
            value: snapshot.activeSelection
        )
    }
}

/// Text layer (task 08-20 R3/R7): column titles and node labels render through
/// the system text pipeline - no per-redraw Canvas text resolution or width
/// measurement. Positions mirror the geometry engine's label rects exactly;
/// the layer never intercepts hits and stays hidden from accessibility (the
/// graph's accessibility representation owns that contract).
private struct OverviewTopologyLabelBand: View {
    let band: OverviewTopologyLayout.RenderBand
    let language: AppLanguage
    let isSummary: Bool
    let interaction: OverviewTopologyInteractionState

    var body: some View {
        let snapshot = interaction.snapshot
        let hasSelection = snapshot.activeSelection != nil
        let highlightedNodeIDs = snapshot.highlight.nodeIDs

        ZStack(alignment: .topLeading) {
            ForEach(band.columns, id: \.id) { column in
                columnTitle(column)
            }
            ForEach(band.nodes, id: \.node.id) { node in
                let emphasis: LabelEmphasis = if !hasSelection {
                    .standard
                } else if highlightedNodeIDs.contains(node.node.id) {
                    .highlighted
                } else {
                    .dimmed
                }
                nodeLabel(node, emphasis: emphasis)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func columnTitle(
        _ column: OverviewTopologyLayout.ColumnGeometry
    ) -> some View {
        let slice = OverviewTopologyHeaderGeometry.sliceWidth(
            for: column,
            in: band
        )
        return HStack(spacing: 6) {
            Image(systemName: OverviewTopologyDrawing.symbol(for: column.id))
                .foregroundStyle(OverviewTopologyProjection.columnTint(for: column.id))
            Text(verbatim: column.id == .policyHop(0) && isSummary
                ? MicaStrings.localizedKey("overview.topology_entry", language: language)
                : OverviewTopologyProjection.columnTitle(column.id, language: language))
            if column.nodeCount > 0 {
                Text(column.nodeCount.formatted())
                    .micaThemeFont(.dataCaption)
                    .foregroundStyle(MicaTheme.textTertiary)
            }
        }
        .micaThemeFont(.label, weight: .semibold)
        .foregroundStyle(MicaTheme.textSecondary)
        .lineLimit(1)
        .frame(width: slice)
        .position(
            x: OverviewTopologyHeaderGeometry.clampedCenter(
                sliceWidth: slice,
                columnCenterX: column.centerX - band.bounds.minX,
                bandWidth: band.bounds.width
            ),
            y: OverviewTopologyLayout.columnHeaderHeight / 2
        )
    }

    private enum LabelEmphasis: Equatable {
        case standard
        case dimmed
        case highlighted
    }

    private func nodeLabel(
        _ node: OverviewTopologyLayout.NodeGeometry,
        emphasis: LabelEmphasis
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: OverviewTopologyDrawing.symbol(for: node.node.columnID))
                .micaThemeFont(.label, weight: .medium)
                .foregroundStyle(emphasis == .highlighted ? MicaTheme.accent : OverviewTopologyProjection.columnTint(for: node.node.columnID))
                .opacity(emphasis == .dimmed ? 0.4 : 1)
                .frame(width: 16, height: 16)
                .position(x: node.rect.minX + 18 - band.bounds.minX, y: node.rect.midY - band.bounds.minY)

            nodeName(node.node, emphasis: emphasis)
            .micaThemeFont(
                node.node.columnID == .source ? .dataLabel : .label,
                weight: emphasis == .highlighted ? .semibold : .medium
            )
            .foregroundStyle(labelColor(for: emphasis))
            .lineLimit(1)
            .frame(
                width: max(node.labelRect.width, 1),
                alignment: node.labelSide == .leading ? .leading : .trailing
            )
            .position(
                x: node.labelRect.midX - band.bounds.minX,
                y: node.labelRect.midY - band.bounds.minY
            )
        }
    }

    @ViewBuilder
    private func nodeName(_ node: ConnectionTopology.Node, emphasis: LabelEmphasis) -> some View {
        if isSummary {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: node.name)
                Text(verbatim: node.connectionCount.formatted())
                    .micaThemeFont(.dataCaption)
                    .foregroundStyle(emphasis == .dimmed ? MicaTheme.textTertiary : MicaTheme.textSecondary)
            }
        } else if node.columnID == .rule, let separator = node.name.range(of: ": "),
           separator.upperBound < node.name.endIndex {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: String(node.name[separator.upperBound...]))
                Text(verbatim: String(node.name[..<separator.lowerBound]))
                    .micaThemeFont(.caption)
                    .foregroundStyle(emphasis == .dimmed ? MicaTheme.textTertiary : MicaTheme.textSecondary)
            }
        } else {
            Text(verbatim: node.name)
        }
    }

    private func labelColor(for emphasis: LabelEmphasis) -> Color {
        switch emphasis {
        case .standard:
            MicaTheme.textPrimary
        case .dimmed:
            MicaTheme.textTertiary
        case .highlighted:
            MicaTheme.textPrimary
        }
    }
}

private struct OverviewTopologyHitBand: View, @MainActor Equatable {
    let request: OverviewTopologyRequest
    let band: OverviewTopologyLayout.RenderBand
    let layout: OverviewTopologyLayout
    let interaction: OverviewTopologyInteractionState

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.request == rhs.request
            && lhs.band.id == rhs.band.id
            && lhs.interaction === rhs.interaction
    }

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    interaction.setHoveredSelection(
                        layout.hitTest(at: globalPoint(for: location))
                    )
                case .ended:
                    interaction.setHoveredSelection(nil)
                }
            }
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { event in
                        interaction.togglePinnedSelection(
                            layout.hitTest(at: globalPoint(for: event.location))
                        )
                    }
            )
            .accessibilityHidden(true)
    }

    private func globalPoint(for localPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: localPoint.x + band.bounds.minX,
            y: localPoint.y + band.bounds.minY
        )
    }
}

private struct OverviewTopologyAccessibilityRepresentation: View {
    @Environment(AppModel.self) private var appModel

    let paths: [ConnectionTopology.PathRecord]
    let structure: OverviewTopologyStructureRequest
    let topologyIndex: OverviewTopologyIndex
    let policyCache: OverviewPolicyInspectionCache
    let language: AppLanguage
    let interaction: OverviewTopologyInteractionState
    let onOpenPath: (ConnectionTopology.PathRecord) -> Void
    let onOpenProxies: (ConnectionTopology.Node) -> Void

    @State private var policyNodeLowerBound = 0
    @State private var pathLowerBound = 0

    var body: some View {
        let policyIndex = policyCache.resolve(
            revision: appModel.policyGroupCatalogRevision,
            catalog: appModel.policyGroupCatalog
        )
        let policyNodeWindow = topologyIndex.accessibilityPolicyNodeWindow(
            preferredLowerBound: policyNodeLowerBound
        )
        let pathWindow = topologyIndex.accessibilityWindow(
            preferredLowerBound: pathLowerBound
        )

        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            Text(MicaStrings.localizedKey("routing.group_catalog", language: language))
            WorkbenchAccessibilityPageControls(
                window: policyNodeWindow,
                moveToLowerBound: movePolicyNodes
            )
            OverviewTopologyAccessibilityNodes(
                nodes: topologyIndex.accessibilityPolicyNodes(
                    in: policyNodeWindow.range
                ),
                topologyIndex: topologyIndex,
                policyIndex: policyIndex,
                language: language,
                interaction: interaction,
                onOpenProxies: onOpenProxies
            )

            Text(MicaStrings.localizedKey("dashboard.chain_label", language: language))
            WorkbenchAccessibilityPageControls(
                window: pathWindow,
                moveToLowerBound: movePaths
            )
            OverviewTopologyAccessibilityGroup(
                paths: paths,
                pathRange: pathWindow.range,
                language: language,
                interaction: interaction,
                onOpenPath: onOpenPath
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            MicaStrings.localizedKey("overview.topology_title", language: language)
        )
        .onAppear {
            reconcileWindows(reset: true)
        }
        .onChange(of: structure) { previous, next in
            reconcileWindows(reset: previous.generation != next.generation)
        }
        .onChange(of: paths.count) { _, _ in
            reconcileWindows(reset: false)
        }
        .onChange(of: interaction.snapshot) { _, snapshot in
            revealPinnedSelection(snapshot)
        }
    }

    private func movePolicyNodes(to lowerBound: Int) {
        policyNodeLowerBound = topologyIndex.accessibilityPolicyNodeWindow(
            preferredLowerBound: lowerBound
        ).lowerBound
    }

    private func movePaths(to lowerBound: Int) {
        pathLowerBound = topologyIndex.accessibilityWindow(
            preferredLowerBound: lowerBound
        ).lowerBound
    }

    private func reconcileWindows(reset: Bool) {
        if reset {
            policyNodeLowerBound = 0
            pathLowerBound = 0
        }
        movePolicyNodes(to: policyNodeLowerBound)
        movePaths(to: pathLowerBound)
        revealPinnedSelection(interaction.snapshot)
    }

    private func revealPinnedSelection(_ snapshot: OverviewTopologyInteractionSnapshot) {
        guard snapshot.isPinned else { return }
        let selection = snapshot.activeSelection
        switch selection {
        case .node(let nodeID):
            policyNodeLowerBound = topologyIndex.accessibilityPolicyNodeWindow(
                preferredLowerBound: policyNodeLowerBound,
                revealing: nodeID
            ).lowerBound
        case .path(let pathID):
            pathLowerBound = topologyIndex.accessibilityWindow(
                preferredLowerBound: pathLowerBound,
                revealing: pathID
            ).lowerBound
        case .edge, nil:
            break
        }
    }
}

private struct OverviewTopologyAccessibilityNodes: View {
    let nodes: ArraySlice<ConnectionTopology.Node>
    let topologyIndex: OverviewTopologyIndex
    let policyIndex: OverviewPolicyInspectionIndex
    let language: AppLanguage
    let interaction: OverviewTopologyInteractionState
    let onOpenProxies: (ConnectionTopology.Node) -> Void

    var body: some View {
        VStack {
            ForEach(nodes) { node in
                let selection = OverviewTopologySelection.node(node.id)
                let isPinned = interaction.snapshot.isPinned
                    && interaction.snapshot.activeSelection == selection
                let inspection = OverviewPolicyInspectionProjection.snapshot(
                    name: node.name,
                    policyIndex: policyIndex,
                    language: language
                )

                HStack {
                    Button {
                        interaction.togglePinnedSelection(selection)
                    } label: {
                        Text(verbatim: inspection?.title ?? node.name)
                    }
                    .accessibilityValue(accessibilityValue(for: node, inspection: inspection))
                    .accessibilityAddTraits(isPinned ? .isSelected : [])
                    .accessibilityHint(
                        MicaStrings.localizedKey(
                            isPinned
                                ? "overview.topology_unpin_selection"
                                : "overview.topology_pin_selection",
                            language: language
                        )
                    )

                    if canOpenProxies(node) {
                        Button { onOpenProxies(node) } label: {
                            Text(
                                MicaStrings.localizedKey(
                                    WorkbenchDestination.proxies.titleKey,
                                    language: language
                                )
                            )
                        }
                        .accessibilityLabel(
                            "\(MicaStrings.localizedKey(WorkbenchDestination.proxies.titleKey, language: language)), \(inspection?.title ?? node.name)"
                        )
                    }
                }
            }
        }
    }

    private func accessibilityValue(
        for node: ConnectionTopology.Node,
        inspection: OverviewPolicyInspectionSnapshot?
    ) -> String {
        guard let inspection else {
            return OverviewTopologyProjection.selectionDescription(
                .node(node.id),
                in: topologyIndex,
                language: language
            )
        }
        let fieldValues = inspection.fields.map { field in
            let title = field.label.resolved(language: language)
            return "\(title): \(field.displayValue())"
        }
        return ([inspection.subtitle].compactMap { $0 } + fieldValues)
            .compactMap(\.overviewNonBlank)
            .joined(separator: ", ")
    }

    private func canOpenProxies(_ node: ConnectionTopology.Node) -> Bool {
        guard case .policyHop = node.columnID else { return false }
        switch policyIndex.resolve(name: node.name) {
        case .group(let group):
            return group.selected.proxyNonBlank != nil
                || group.members.contains { $0.proxyNonBlank != nil }
        case .member:
            return true
        case .ambiguous, .missing:
            return false
        }
    }
}

private struct OverviewTopologyAccessibilityGroup: View {
    let paths: [ConnectionTopology.PathRecord]
    let pathRange: Range<Int>
    let language: AppLanguage
    let interaction: OverviewTopologyInteractionState
    let onOpenPath: (ConnectionTopology.PathRecord) -> Void

    var body: some View {
        VStack {
            ForEach(paths[pathRange]) { path in
                let isPinned = interaction.snapshot.isPinned
                    && interaction.snapshot.activeSelection == .path(path.id)
                HStack {
                    Button {
                        interaction.togglePinnedPath(path.id)
                    } label: {
                        Text(
                            verbatim: OverviewTopologyProjection.pathLabel(
                                path,
                                language: language
                            )
                        )
                    }
                    .accessibilityValue(
                        OverviewTopologyProjection.pathDescription(
                            path,
                            language: language
                        )
                    )
                    .accessibilityAddTraits(isPinned ? .isSelected : [])
                    .accessibilityHint(
                        MicaStrings.localizedKey(
                            isPinned
                                ? "overview.topology_unpin_selection"
                                : "overview.topology_pin_selection",
                            language: language
                        )
                    )

                    Button {
                        onOpenPath(path)
                    } label: {
                        Text(
                            MicaStrings.localizedKey(
                                WorkbenchDestination.connections.titleKey,
                                language: language
                            )
                        )
                    }
                    .accessibilityLabel(openPathLabel(path))
                }
            }
        }
        .onAppear {
            MicaPerformanceObservation.recordDebug(
                .topologyAccessibilityPresentation,
                metadata: MicaPerformanceMetadata(count: UInt64(pathRange.count))
            )
        }
    }

    private func openPathLabel(_ path: ConnectionTopology.PathRecord) -> String {
        let destination = MicaStrings.localizedKey(
            WorkbenchDestination.connections.titleKey,
            language: language
        )
        let path = OverviewTopologyProjection.pathLabel(path, language: language)
        return "\(destination), \(path)"
    }
}

private enum OverviewTopologyDrawing {
    static func symbol(for column: ConnectionTopology.Column.ID) -> String {
        switch column {
        case .source: "network"
        case .rule: "line.3.horizontal.decrease"
        case .policyHop: "arrow.triangle.branch"
        case .finalOutbound: "arrow.up.right"
        }
    }
    /// Dense graphs reduce background ink; explicit selection stays readable.
    static func drawEdge(
        _ edge: OverviewTopologyLayout.EdgeGeometry,
        sourceTint: Color = MicaTheme.textTertiary,
        targetTint: Color = MicaTheme.textTertiary,
        density: OverviewTopologyDensityStyle,
        isDimmed: Bool = false,
        isHighlighted: Bool = false,
        in context: inout GraphicsContext
    ) {
        let lineWidth = isHighlighted ? min(edge.width, 3) + 1.25 : min(edge.width, density.maximumLineWidth)
        let style = StrokeStyle(
            lineWidth: lineWidth,
            lineCap: .round,
            lineJoin: .round
        )

        if isHighlighted {
            context.stroke(
                edge.drawingPath,
                with: .color(MicaTheme.accent.opacity(0.10)),
                style: StrokeStyle(lineWidth: lineWidth + 5, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                edge.drawingPath,
                with: .color(MicaTheme.accent.opacity(0.88)),
                style: style
            )
            return
        }
        if isDimmed {
            context.stroke(
                edge.drawingPath,
                with: .color(MicaTheme.edgeDimmed.opacity(min(0.6, density.edgeOpacity * 1.5))),
                style: style
            )
            return
        }
        context.stroke(
            edge.drawingPath,
            with: .linearGradient(
                Gradient(colors: [
                    sourceTint.opacity(density.edgeOpacity),
                    targetTint.opacity(density.edgeOpacity),
                ]),
                startPoint: edge.source,
                endPoint: edge.target
            ),
            style: style
        )
    }

    /// Opaque cards keep names separate from the route network. Reported
    /// status uses a small marker instead of coloring every connected edge.
    static func drawNode(
        _ node: OverviewTopologyLayout.NodeGeometry,
        status: MicaTheme.Status,
        tint: Color = MicaTheme.textTertiary,
        isDimmed: Bool = false,
        isHighlighted: Bool = false,
        in context: inout GraphicsContext
    ) {
        context.fill(node.drawingPath, with: .color(MicaTheme.Topology.nodeSurface))
        context.fill(
            node.drawingPath,
            with: .color((isHighlighted ? MicaTheme.accent : tint).opacity(isHighlighted ? 0.12 : 0.025))
        )
        context.stroke(
            node.drawingPath,
            with: .color(isHighlighted ? MicaTheme.accent : tint.opacity(isDimmed ? 0.12 : 0.35)),
            lineWidth: isHighlighted ? 1.25 : 0.75
        )
        if status != .neutral {
            context.fill(
                Path(ellipseIn: CGRect(x: node.rect.maxX - 10, y: node.rect.midY - 2.5, width: 5, height: 5)),
                with: .color(status.color.opacity(isDimmed ? 0.3 : 1))
            )
        }
    }
}
