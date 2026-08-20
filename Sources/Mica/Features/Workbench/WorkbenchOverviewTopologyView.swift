import Foundation
import MicaCore
import SwiftUI

struct OverviewTopologySection: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let runtime: OverviewTopologyRuntime
    @Binding var destination: WorkbenchDestination

    var body: some View {
        let catalog = appModel.connectionsCatalog
        OverviewFlatSection(
            "overview.topology_title",
            systemImage: "point.3.connected.trianglepath.dotted",
            accessory: {
                if !catalog.connections.isEmpty {
                    OverviewTopologyHeaderControls(runtime: runtime)
                }
            }
        ) {
            OverviewTopologyWorkspace(
                connections: catalog.connections,
                controllerID: appModel.selectedRouterID,
                generation: appModel.controllerSessionPresentation.generation,
                revision: catalog.structureRevision,
                language: language,
                runtime: runtime,
                destination: $destination
            )
        }
    }
}

/// Second-bucketed live-signal value retained for the pause/motion projection
/// contract (`motionProjectionIsStaticForPauseInactiveAndReduceMotion`). The flat
/// Mica Ops renderer no longer threads it into band rendering; a later phase
/// removes the remaining consumers with the neon visual system.
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

            topologyBody(for: request)
                .frame(
                    minHeight: CGFloat(resolvedMinimumFlowHeight),
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
                    if runtime.isExpanded {
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
                            OverviewTopologyPathRows(
                                paths: presentation.topology.paths,
                                language: language,
                                interaction: runtime.interaction,
                                onOpenPath: openPathInConnections
                            )
                        }
                    } else {
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
                        }
                        .accessibilityRepresentation {
                            OverviewTopologyAccessibilityRepresentation(
                                paths: presentation.topology.paths,
                                groups: presentation.index.accessibilityGroups,
                                nodes: presentation.topology.nodes,
                                includesPaths: true,
                                topologyIndex: presentation.index,
                                policyCache: runtime.policyInspectionCache,
                                language: language,
                                interaction: runtime.interaction,
                                onOpenPath: openPathInConnections,
                                onOpenProxies: openProxies
                            )
                        }
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
                        onOpenProxies: openProxies
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
        if let controllerID,
           let connectionID = path.reportedConnectionID.overviewNonBlank {
            workspaceStore.stageConnectionNavigation(
                WorkbenchConnectionNavigationSelection(
                    controllerID: controllerID,
                    generation: generation,
                    connectionID: connectionID
                )
            )
        }
        destination = .connections
    }

    private func openProxies() {
        destination = .proxies
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
            switch workspaceStore.inspectorSelection {
            case .proxyGroup, .proxyNode:
                workspaceStore.selectInspector(.none)
            case .none, .connection, .rule, .log, .source, .controller:
                break
            }
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
            workspaceStore.selectInspector(.proxyGroup(groupName: group.name))
        case .member(let member):
            workspaceStore.selectInspector(
                .proxyNode(groupName: member.groupName, nodeName: member.name)
            )
        case .ambiguous, .missing:
            workspaceStore.selectInspector(.proxyGroup(groupName: node.name))
        }
    }
}

private struct OverviewTopologyViewport: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.micaAppFontScale) private var fontScale

    let topology: ConnectionTopology
    let request: OverviewTopologyRequest
    let index: OverviewTopologyIndex
    let layout: OverviewTopologyLayout
    let language: AppLanguage
    let runtime: OverviewTopologyRuntime
    let interaction: OverviewTopologyInteractionState
    let showsPathRows: Bool
    let onOpenPath: (ConnectionTopology.PathRecord) -> Void
    let onOpenProxies: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            topologyGraph
                .accessibilityRepresentation {
                    OverviewTopologyAccessibilityRepresentation(
                        paths: topology.paths,
                        groups: index.accessibilityGroups,
                        nodes: topology.nodes,
                        includesPaths: !showsPathRows,
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
        LazyVStack(spacing: 0) {
            ForEach(layout.renderBands) { band in
                OverviewTopologyBandLayers(
                    request: request,
                    band: band,
                    layout: layout,
                    language: language,
                    fontScale: fontScale,
                    allowsMotion: allowsMotion,
                    nodeStatusByID: nodeStatusByID,
                    interaction: interaction
                )
                .equatable()
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
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

            if isPolicySelection(selection) {
                Button(action: onOpenProxies) {
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

    private func isPolicySelection(_ selection: OverviewTopologySelection) -> Bool {
        guard case .node(let nodeID) = selection,
              let node = index.node(id: nodeID),
              case .policyHop = node.columnID else {
            return false
        }
        return true
    }

    /// State-change motion gate (design.md §2): Reduce Motion, a paused stream,
    /// and an inactive window all render fully static.
    private var allowsMotion: Bool {
        !reduceMotion
            && controlActiveState != .inactive
            && !runtime.isPaused
            && !appModel.controllerSessionPresentation.controls.dashboardUpdatesPaused
    }

    /// Controller-reported status per node. Only policy-hop nodes resolve a
    /// reportable signal (policy-catalog latency); every other node stays neutral.
    private var nodeStatusByID: [String: MicaTheme.Status] {
        let policyIndex = runtime.policyInspectionCache.resolve(
            revision: appModel.policyGroupCatalogRevision,
            catalog: appModel.policyGroupCatalog
        )
        var statuses: [String: MicaTheme.Status] = [:]
        for node in topology.nodes {
            guard case .policyHop = node.columnID else { continue }
            statuses[node.id] = OverviewTopologyNodeStatus.resolve(
                name: node.name,
                policyIndex: policyIndex
            )
        }
        return statuses
    }
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
    let fontScale: AppFontScale
    let allowsMotion: Bool
    let nodeStatusByID: [String: MicaTheme.Status]
    let interaction: OverviewTopologyInteractionState

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.request == rhs.request
            && lhs.band.id == rhs.band.id
            && lhs.language == rhs.language
            && lhs.fontScale == rhs.fontScale
            && lhs.allowsMotion == rhs.allowsMotion
            && lhs.nodeStatusByID == rhs.nodeStatusByID
            && lhs.interaction === rhs.interaction
    }

    var body: some View {
        ZStack {
            OverviewTopologyBaseBand(
                request: request,
                band: band,
                language: language,
                fontScale: fontScale,
                nodeStatusByID: nodeStatusByID
            )
            .equatable()

            OverviewTopologyHighlightBand(
                band: band,
                fontScale: fontScale,
                allowsMotion: allowsMotion,
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
    }
}

private struct OverviewTopologyBaseBand: View, @MainActor Equatable {
    let request: OverviewTopologyRequest
    let band: OverviewTopologyLayout.RenderBand
    let language: AppLanguage
    let fontScale: AppFontScale
    let nodeStatusByID: [String: MicaTheme.Status]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.request == rhs.request
            && lhs.band.id == rhs.band.id
            && lhs.language == rhs.language
            && lhs.fontScale == rhs.fontScale
            && lhs.nodeStatusByID == rhs.nodeStatusByID
    }

    var body: some View {
        Canvas(
            opaque: false,
            colorMode: .nonLinear,
            rendersAsynchronously: true
        ) { context, _ in
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
            context.translateBy(x: 0, y: -band.bounds.minY)

            for edge in band.edges {
                OverviewTopologyDrawing.drawEdge(edge, in: &context)
            }

            for column in band.columns {
                let title = context.resolve(
                    Text(
                        verbatim: OverviewTopologyProjection.columnTitle(
                            column.id,
                            language: language
                        )
                    )
                    .font(MicaTheme.font(for: .label, scale: fontScale, weight: .semibold))
                    .foregroundStyle(MicaTheme.textSecondary)
                )
                context.draw(
                    title,
                    at: CGPoint(
                        x: column.centerX,
                        y: OverviewTopologyLayout.columnHeaderHeight / 2
                    ),
                    anchor: .center
                )
            }

            for node in band.nodes {
                OverviewTopologyDrawing.drawNode(
                    node,
                    status: nodeStatusByID[node.node.id] ?? .neutral,
                    fontScale: fontScale,
                    in: &context
                )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct OverviewTopologyHighlightBand: View {
    let band: OverviewTopologyLayout.RenderBand
    let fontScale: AppFontScale
    let allowsMotion: Bool
    let interaction: OverviewTopologyInteractionState

    var body: some View {
        let snapshot = interaction.snapshot

        ZStack {
            MicaTheme.canvas
                .opacity(snapshot.activeSelection == nil ? 0 : 0.34)

            Canvas { context, _ in
                guard snapshot.activeSelection != nil else { return }
                MicaPerformanceObservation.recordDebug(
                    .topologyHighlightPresentation,
                    metadata: MicaPerformanceMetadata(
                        count: UInt64(
                            snapshot.highlight.nodeIDs.count
                                + snapshot.highlight.edgeIDs.count
                        )
                    )
                )
                context.translateBy(x: 0, y: -band.bounds.minY)

                for edge in band.edges
                    where snapshot.highlight.edgeIDs.contains(edge.edge.id) {
                    OverviewTopologyDrawing.drawEdge(
                        edge,
                        isHighlighted: true,
                        in: &context
                    )
                }
                for node in band.nodes
                    where snapshot.highlight.nodeIDs.contains(node.node.id) {
                    OverviewTopologyDrawing.drawNode(
                        node,
                        status: .neutral,
                        isHighlighted: true,
                        fontScale: fontScale,
                        in: &context
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .micaStateChangeAnimation(
            allowsMotion ? MicaTheme.Motion.stateChange : nil,
            value: snapshot.activeSelection
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
    let groups: [OverviewTopologyIndex.AccessibilityGroup]
    let nodes: [ConnectionTopology.Node]
    let includesPaths: Bool
    let topologyIndex: OverviewTopologyIndex
    let policyCache: OverviewPolicyInspectionCache
    let language: AppLanguage
    let interaction: OverviewTopologyInteractionState
    let onOpenPath: (ConnectionTopology.PathRecord) -> Void
    let onOpenProxies: () -> Void

    var body: some View {
        let policyIndex = policyCache.resolve(
            revision: appModel.policyGroupCatalogRevision,
            catalog: appModel.policyGroupCatalog
        )

        LazyVStack {
            OverviewTopologyAccessibilityNodes(
                nodes: policyNodes,
                topologyIndex: topologyIndex,
                policyIndex: policyIndex,
                language: language,
                interaction: interaction,
                onOpenProxies: onOpenProxies
            )

            if includesPaths {
                ForEach(groups) { group in
                    OverviewTopologyAccessibilityGroup(
                        paths: paths,
                        pathRange: group.pathRange,
                        language: language,
                        interaction: interaction,
                        onOpenPath: onOpenPath
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            MicaStrings.localizedKey("overview.topology_title", language: language)
        )
    }

    private var policyNodes: [ConnectionTopology.Node] {
        nodes.filter { node in
            if case .policyHop = node.columnID {
                return true
            }
            return false
        }
    }
}

private struct OverviewTopologyAccessibilityNodes: View {
    let nodes: [ConnectionTopology.Node]
    let topologyIndex: OverviewTopologyIndex
    let policyIndex: OverviewPolicyInspectionIndex
    let language: AppLanguage
    let interaction: OverviewTopologyInteractionState
    let onOpenProxies: () -> Void

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

                    Button(action: onOpenProxies) {
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

private enum OverviewTopologyNodeStatus {
    /// Maps the controller-reported policy latency to a Mica Ops status. Missing
    /// or non-positive delays carry no status and stay on the neutral surface.
    static func resolve(
        name: String,
        policyIndex: OverviewPolicyInspectionIndex
    ) -> MicaTheme.Status {
        let delay: Int?
        switch policyIndex.resolve(name: name) {
        case .group(let group):
            delay = group.selectedMember.delay
        case .member(let member):
            delay = member.delay
        case .ambiguous, .missing:
            delay = nil
        }
        guard let delay, delay > 0 else { return .neutral }
        switch LatencyHealthGrade.allCases.first(where: { $0.includes(delay: delay) }) {
        case .fast?, .normal?:
            return .ok
        case .slow?:
            return .warning
        case .timeout?:
            return .error
        case nil:
            return .neutral
        }
    }
}

private enum OverviewTopologyDrawing {
    /// Flat Mica Ops edge: one quiet 1.5pt neutral cubic stroke; the
    /// active/hovered/pinned trajectory redraws at 2pt in the signal accent.
    /// No gradient ribbons, glow, bloom, or energy strokes.
    static func drawEdge(
        _ edge: OverviewTopologyLayout.EdgeGeometry,
        isHighlighted: Bool = false,
        in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: edge.source)
        path.addCurve(to: edge.target, control1: edge.control1, control2: edge.control2)
        context.stroke(
            path,
            with: .color(isHighlighted ? MicaTheme.accent : MicaTheme.textSecondary),
            lineWidth: isHighlighted ? 2 : 1.5
        )
    }

    /// Node bar: controller-reported status color when the policy catalog reports
    /// one, neutral raised surface otherwise; the active path redraws in accent.
    static func drawNode(
        _ node: OverviewTopologyLayout.NodeGeometry,
        status: MicaTheme.Status,
        isHighlighted: Bool = false,
        fontScale: AppFontScale,
        in context: inout GraphicsContext
    ) {
        if isHighlighted {
            context.fill(node.drawingPath, with: .color(MicaTheme.accent))
        } else if status == .neutral {
            context.fill(node.drawingPath, with: .color(MicaTheme.surfaceRaised))
            context.stroke(
                node.drawingPath,
                with: .color(MicaTheme.separator),
                lineWidth: MicaTheme.Shape.hairline
            )
        } else {
            context.fill(node.drawingPath, with: .color(status.color))
        }
        let label = context.resolve(
            Text(verbatim: node.node.name)
                .font(MicaTheme.font(for: .label, scale: fontScale))
                .foregroundStyle(.primary)
        )
        let labelPoint: CGPoint
        let labelAnchor: UnitPoint
        switch node.labelSide {
        case .leading:
            labelPoint = CGPoint(x: node.labelRect.minX, y: node.labelRect.midY)
            labelAnchor = .leading
        case .trailing:
            let measuredLabelWidth = label.measure(
                in: CGSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: node.labelRect.height
                )
            ).width
            if measuredLabelWidth <= node.labelRect.width {
                labelPoint = CGPoint(x: node.labelRect.maxX, y: node.labelRect.midY)
                labelAnchor = .trailing
            } else {
                labelPoint = CGPoint(x: node.labelRect.minX, y: node.labelRect.midY)
                labelAnchor = .leading
            }
        }
        var labelContext = context
        labelContext.clip(to: Path(node.labelRect))
        labelContext.draw(
            label,
            at: labelPoint,
            anchor: labelAnchor
        )
    }

}
