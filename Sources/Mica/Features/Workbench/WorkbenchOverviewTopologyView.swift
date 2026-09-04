import Foundation
import MicaCore
import SwiftUI

struct OverviewTopologySection: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language
    @State private var structureInput: OverviewTopologyCatalogInput?

    let runtime: OverviewTopologyRuntime
    @Binding var destination: WorkbenchDestination

    var body: some View {
        let request = OverviewTopologyCatalogRequest.observing(appModel)
        let visibleInput = structureInput?.visible(for: request)
        OverviewFlatSection(
            "overview.topology_title",
            systemImage: "point.3.connected.trianglepath.dotted",
            accessory: {
                if visibleInput?.connections.isEmpty == false {
                    OverviewTopologyHeaderControls(runtime: runtime)
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

private struct OverviewTopologyHeaderControls: View {
    @Environment(\.micaAppLanguage) private var language

    let runtime: OverviewTopologyRuntime

    var body: some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
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
            WorkbenchIconCommand(
                titleKey: runtime.isExpanded
                    ? "overview.show_less"
                    : "overview.show_all",
                systemImage: runtime.isExpanded
                    ? "list.bullet.indent"
                    : "list.bullet"
            ) {
                runtime.isExpanded.toggle()
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
    @Binding var destination: WorkbenchDestination

    var body: some View {
        if connections.isEmpty {
            OverviewInlineState(
                titleKey: "overview.topology_empty",
                detailKey: "overview.topology_empty_detail"
            )
        } else {
            let freezesPresentation = runtime.isPaused
                || runtime.interaction.snapshot.isHovering
            let presentationRevision = freezesPresentation
                ? runtime.presentation?.request.revision ?? revision
                : revision
            let resolvedMinimumFlowHeight = minimumFlowHeight(
                for: runtime.availableWidth
            )
            let request = OverviewTopologyRequest(
                generation: generation,
                revision: presentationRevision,
                availableWidth: runtime.availableWidth,
                minimumFlowHeight: resolvedMinimumFlowHeight
            )
            let visibleTopologyIsEmpty = runtime.presentation.flatMap { presentation in
                presentation.canRemainVisible(whileResolving: request)
                    ? presentation.topology.isEmpty
                    : nil
            }
            let reservedMinimumHeight = OverviewTopologyHeightReservation.minimumHeight(
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

    private func minimumFlowHeight(for availableWidth: Int) -> Int {
        let scaledHeight = CGFloat(max(availableWidth, 1)) * 0.56
        return Int(min(max(scaledHeight, 680), 920).rounded())
    }

    @ViewBuilder
    private func topologyBody(for request: OverviewTopologyRequest) -> some View {
        if let presentation = runtime.presentation,
           presentation.canRemainVisible(whileResolving: request) {
            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space3) {
                if presentation.topology.isEmpty {
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

                        if runtime.isExpanded {
                            OverviewTopologyPathRows(
                                paths: presentation.topology.paths,
                                language: language,
                                interaction: runtime.interaction,
                                onOpenPath: openPathInConnections
                            )
                            .accessibilityHidden(true)
                        }
                    }
                    .accessibilityRepresentation {
                        OverviewTopologyAccessibilityRepresentation(
                            paths: presentation.topology.paths,
                            structure: presentation.request.structure,
                            topologyIndex: presentation.index,
                            policyCache: runtime.policyInspectionCache,
                            language: language,
                            interaction: runtime.interaction,
                            onOpenPath: openPathInConnections,
                            onOpenProxies: openProxies(for:)
                        )
                    }
                } else {
                    OverviewTopologyViewport(
                        topology: presentation.topology,
                        request: presentation.request,
                        index: presentation.index,
                        layout: presentation.layout,
                        language: language,
                        runtime: runtime,
                        interaction: runtime.interaction,
                        showsPathRows: runtime.isExpanded,
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

    @MainActor
    private func rebuildPresentation(for request: OverviewTopologyRequest) async {
        do {
            let nextPresentation = try await runtime.presentationCache.resolve(
                request: request,
                connections: connections
            )
            guard !Task.isCancelled else { return }
            runtime.interaction.configure(
                structure: nextPresentation.request.structure,
                index: nextPresentation.index
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
    let showsPathRows: Bool
    let onOpenPath: (ConnectionTopology.PathRecord) -> Void
    let onOpenProxies: (ConnectionTopology.Node) -> Void

    @State private var scrollPosition = ScrollPosition(x: 0)
    @State private var visibleTopologyRect = CGRect.zero

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            topologyGraph
                .accessibilityRepresentation {
                    OverviewTopologyAccessibilityRepresentation(
                        paths: topology.paths,
                        structure: request.structure,
                        topologyIndex: index,
                        policyCache: runtime.policyInspectionCache,
                        language: language,
                        interaction: interaction,
                        onOpenPath: onOpenPath,
                        onOpenProxies: onOpenProxies
                    )
                }

            if showsPathRows {
                OverviewTopologyPathRows(
                    paths: topology.paths,
                    language: language,
                    interaction: interaction,
                    onOpenPath: onOpenPath
                )
                .accessibilityHidden(true)
            }
        }
    }

    /// Standard hover tooltip carrying the truthful route label of the hovered
    /// element (Phase 3.3 replaced the node-anchored hover HUD with this).
    private var hoverTooltip: String? {
        let snapshot = interaction.snapshot
        guard snapshot.isHovering, let selection = snapshot.activeSelection else {
            return nil
        }
        return OverviewTopologyProjection.selectionLabel(
            selection,
            in: index,
            language: language
        )
    }

    private var topologyGraph: some View {
        // Task 08-23 R10: when long chains widen the graph past the panel the
        // viewport scrolls horizontally; the width floor keeps the content
        // pinned to the full panel width otherwise.
        ScrollView(.horizontal) {
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
        }
        .scrollPosition($scrollPosition)
        .scrollIndicators(
            hasHorizontalOverflow ? .visible : .hidden,
            axes: .horizontal
        )
        .onScrollGeometryChange(for: CGRect.self) { geometry in
            geometry.visibleRect
        } action: { previous, current in
            visibleTopologyRect = current
            if previous.width <= 0 || previous.size != current.size {
                revealCurrentSelection(in: current)
            }
        }
        .onChange(of: viewportSelection) { _, state in
            guard state.isPinned else { return }
            revealSelection(state.selection, in: visibleTopologyRect)
        }
        .frame(height: layout.size.height)
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

            if let policyNode = resolvablePolicyNode(for: selection) {
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
        let viewportWidth = visibleTopologyRect.width > 0
            ? visibleTopologyRect.width
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
        ), let offset = OverviewTopologyViewportTargetResolver.contentOffsetX(
            for: target,
            visibleRect: visibleRect,
            contentWidth: layout.size.width
        ) else {
            return
        }

        if reduceMotion {
            scrollPosition.scrollTo(x: offset)
        } else {
            withAnimation(MicaTheme.Motion.reveal) {
                scrollPosition.scrollTo(x: offset)
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
        runtime.nodeStatuses(
            topology: topology,
            topologyRevision: request.revision,
            policyRevision: appModel.policyGroupCatalogRevision,
            catalog: appModel.policyGroupCatalog
        )
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
        ZStack {
            OverviewTopologyBaseBand(
                request: request,
                band: band,
                allowsMotion: allowsMotion,
                nodeStatusByID: nodeStatusByID,
                tintByNodeID: tintByNodeID,
                interaction: interaction
            )
            .equatable()

            OverviewTopologyLabelBand(
                band: band,
                language: language
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

            // Column identity ticks under the titles (task 08-23 R4).
            for column in band.columns {
                let slice = OverviewTopologyHeaderGeometry.sliceWidth(
                    for: column,
                    in: band
                )
                let tickCenterX = band.bounds.minX
                    + OverviewTopologyHeaderGeometry.clampedCenter(
                        sliceWidth: slice,
                        columnCenterX: column.centerX - band.bounds.minX,
                        bandWidth: band.bounds.width
                    )
                context.fill(
                    Path(
                        roundedRect: CGRect(
                            x: tickCenterX - 11,
                            y: band.bounds.minY
                                + OverviewTopologyLayout.columnHeaderHeight - 6,
                            width: 22,
                            height: 2.5
                        ),
                        cornerRadius: 1.25
                    ),
                    with: .color(
                        OverviewTopologyProjection.columnTint(for: column.id)
                            .opacity(0.85)
                    )
                )
            }

            let highlightedEdgeIDs = snapshot.highlight.edgeIDs
            let highlightedNodeIDs = snapshot.highlight.nodeIDs
            let isDimmed = snapshot.activeSelection != nil

            // Pass 1: everything not on the active trajectory, tiered by the
            // controller-reported status of the policy hop the edge touches.
            for edge in band.edges where !highlightedEdgeIDs.contains(edge.edge.id) {
                let targetStatus = statusByID[edge.edge.targetID] ?? .neutral
                let status = targetStatus != .neutral
                    ? targetStatus
                    : statusByID[edge.edge.sourceID] ?? .neutral
                OverviewTopologyDrawing.drawEdge(
                    edge,
                    status: status,
                    sourceTint: tintByNodeID[edge.edge.sourceID]
                        ?? MicaTheme.textTertiary,
                    targetTint: tintByNodeID[edge.edge.targetID]
                        ?? MicaTheme.textTertiary,
                    isDimmed: isDimmed,
                    in: &context
                )
            }
            for node in band.nodes where !highlightedNodeIDs.contains(node.node.id) {
                OverviewTopologyDrawing.drawNode(
                    node,
                    status: statusByID[node.node.id] ?? .neutral,
                    tint: tintByNodeID[node.node.id] ?? MicaTheme.textTertiary,
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
                        isHighlighted: true,
                        in: &context
                    )
                }
                for node in band.nodes where highlightedNodeIDs.contains(node.node.id) {
                    OverviewTopologyDrawing.drawNode(
                        node,
                        status: .neutral,
                        isHighlighted: true,
                        in: &context
                    )
                }
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
    @Environment(\.micaAppFontScale) private var fontScale

    let band: OverviewTopologyLayout.RenderBand
    let language: AppLanguage

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(band.columns, id: \.id) { column in
                columnTitle(column)
            }
            ForEach(band.nodes, id: \.node.id) { node in
                nodeLabel(node)
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
        return Text(
            verbatim: OverviewTopologyProjection.columnTitle(
                column.id,
                language: language
            )
        )
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

    private func nodeLabel(
        _ node: OverviewTopologyLayout.NodeGeometry
    ) -> some View {
        Text(verbatim: node.node.name)
            .micaThemeFont(.label)
            .foregroundStyle(MicaTheme.textPrimary)
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
            return "\(title): \(field.value)"
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
    /// Edge rendering (task 08-23 R9): true sankey ribbons. The geometry
    /// engine already packs flow-proportional widths into the node rects
    /// (edge.width = flow * valueScale, y centers stacked per node), so the
    /// band traces the true width between the packed endpoints - d3-sankey's
    /// closed ribbon construction. Fill priority: selection accent 85% >
    /// dimmed mist > controller-reported status 70% > default
    /// source-to-target column-tint gradient at 45% (the community-consensus
    /// 0.4-0.6 band keeps overlapping flows readable).
    static func drawEdge(
        _ edge: OverviewTopologyLayout.EdgeGeometry,
        status: MicaTheme.Status = .neutral,
        sourceTint: Color = MicaTheme.textTertiary,
        targetTint: Color = MicaTheme.textTertiary,
        isDimmed: Bool = false,
        isHighlighted: Bool = false,
        in context: inout GraphicsContext
    ) {
        let half = max(edge.width, 1.5) / 2
        var ribbon = Path()
        ribbon.move(to: CGPoint(x: edge.source.x, y: edge.source.y - half))
        ribbon.addCurve(
            to: CGPoint(x: edge.target.x, y: edge.target.y - half),
            control1: CGPoint(x: edge.control1.x, y: edge.control1.y - half),
            control2: CGPoint(x: edge.control2.x, y: edge.control2.y - half)
        )
        ribbon.addLine(to: CGPoint(x: edge.target.x, y: edge.target.y + half))
        ribbon.addCurve(
            to: CGPoint(x: edge.source.x, y: edge.source.y + half),
            control1: CGPoint(x: edge.control2.x, y: edge.control2.y + half),
            control2: CGPoint(x: edge.control1.x, y: edge.control1.y + half)
        )
        ribbon.closeSubpath()

        if isHighlighted {
            context.fill(ribbon, with: .color(MicaTheme.accent.opacity(0.85)))
            return
        }
        if isDimmed {
            context.fill(ribbon, with: .color(MicaTheme.edgeDimmed))
            return
        }
        if status != .neutral {
            context.fill(ribbon, with: .color(status.color.opacity(0.7)))
            return
        }
        context.fill(
            ribbon,
            with: .linearGradient(
                Gradient(colors: [
                    sourceTint.opacity(0.45),
                    targetTint.opacity(0.45),
                ]),
                startPoint: edge.source,
                endPoint: edge.target
            )
        )
    }

    /// Node bar (tasks 08-20 R2, 08-23 R9): controller-reported status fill
    /// when the policy catalog reports one; neutral nodes are solid
    /// column-tint anchor bars (sankey standard); the active trajectory
    /// redraws in accent. Labels render in `OverviewTopologyLabelBand`.
    static func drawNode(
        _ node: OverviewTopologyLayout.NodeGeometry,
        status: MicaTheme.Status,
        tint: Color = MicaTheme.textTertiary,
        isDimmed: Bool = false,
        isHighlighted: Bool = false,
        in context: inout GraphicsContext
    ) {
        if isHighlighted {
            context.fill(node.drawingPath, with: .color(MicaTheme.accent))
            return
        }
        if status != .neutral {
            context.fill(
                node.drawingPath,
                with: .color(status.color.opacity(isDimmed ? 0.4 : 1))
            )
            return
        }
        // Neutral anchor bar (task 08-23 R9): solid column-tint block, the
        // sankey community standard - ribbons visually anchor on solid
        // endpoints. Dimmed nodes recede so the active path owns the scene.
        context.fill(
            node.drawingPath,
            with: .color(tint.opacity(isDimmed ? 0.35 : 1))
        )
    }
}
