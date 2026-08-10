import Foundation
import MicaCore
import SwiftUI

struct OverviewTopologySection: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let runtime: OverviewTopologyModuleRuntime
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

private struct OverviewTopologyHeaderControls: View {
    @Environment(\.micaAppLanguage) private var language

    let runtime: OverviewTopologyModuleRuntime

    var body: some View {
        HStack(spacing: MicaSpacing.row) {
            if runtime.isPaused {
                Text(
                    MicaStrings.localizedKey(
                        "overview.chart_paused",
                        language: language
                    )
                )
                .micaFont(.caption, weight: .semibold)
                .foregroundStyle(MicaStyle.signalAmber)
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
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore

    let connections: [ConnectionSnapshot]
    let controllerID: RouterProfile.ID?
    let generation: UUID
    let revision: UInt64
    let language: AppLanguage
    let runtime: OverviewTopologyModuleRuntime
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
            VStack(alignment: .leading, spacing: MicaSpacing.module) {
                if presentation.topology.isEmpty {
                    if runtime.isExpanded {
                        VStack(alignment: .leading, spacing: MicaSpacing.row) {
                            OverviewTopologyIdleSummary(
                                connectionCount: presentation.topology.connectionCount,
                                unavailablePathCount: presentation.topology.routeUnavailableCount,
                                language: language
                            )
                            .frame(
                                height: OverviewTopologyLayout.selectionDetailHeight,
                                alignment: .leading
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
                        VStack(alignment: .leading, spacing: MicaSpacing.row) {
                            OverviewTopologyIdleSummary(
                                connectionCount: presentation.topology.connectionCount,
                                unavailablePathCount: presentation.topology.routeUnavailableCount,
                                language: language
                            )
                            .frame(
                                height: OverviewTopologyLayout.selectionDetailHeight,
                                alignment: .leading
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
                                language: language,
                                interaction: runtime.interaction,
                                onOpenPath: openPathInConnections
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
                        interaction: runtime.interaction,
                        showsPathRows: runtime.isExpanded,
                        onOpenPath: openPathInConnections
                    )
                }
            }
        } else {
            HStack(spacing: MicaSpacing.row) {
                ProgressView().controlSize(.small)
                Text(MicaStrings.localizedKey("overview.current_data", language: language))
                    .micaFont(.caption)
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
}

private struct OverviewTopologyViewport: View {
    let topology: ConnectionTopology
    let request: OverviewTopologyRequest
    let index: OverviewTopologyIndex
    let layout: OverviewTopologyLayout
    let language: AppLanguage
    let interaction: OverviewTopologyInteractionState
    let showsPathRows: Bool
    let onOpenPath: (ConnectionTopology.PathRecord) -> Void

    @Environment(\.micaAppFontScale) private var fontScale

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            if showsPathRows {
                topologyGraph
                    .accessibilityHidden(true)
                OverviewTopologyPathRows(
                    paths: topology.paths,
                    language: language,
                    interaction: interaction,
                    onOpenPath: onOpenPath
                )
            } else {
                topologyGraph
                    .accessibilityRepresentation {
                        OverviewTopologyAccessibilityRepresentation(
                            paths: topology.paths,
                            groups: index.accessibilityGroups,
                            language: language,
                            interaction: interaction,
                            onOpenPath: onOpenPath
                        )
                    }
            }
        }
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
                    interaction: interaction
                )
                .equatable()
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .background(MicaStyle.contentFill)
        .frame(height: layout.size.height)
        .frame(maxWidth: .infinity, alignment: .center)
        .clipShape(.rect(cornerRadius: MicaBounds.moduleRadius))
        .overlay {
            RoundedRectangle(cornerRadius: MicaBounds.moduleRadius)
                .stroke(MicaStyle.separator.opacity(0.5), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            OverviewTopologySelectionDetail(
                connectionCount: topology.connectionCount,
                unavailablePathCount: topology.routeUnavailableCount,
                index: index,
                language: language,
                interaction: interaction,
                onOpenPath: onOpenPath
            )
            .padding(.top, OverviewTopologyLayout.columnHeaderHeight)
            .padding(.horizontal, MicaSpacing.row)
        }
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
}

private struct OverviewTopologySelectionDetail: View {
    let connectionCount: Int
    let unavailablePathCount: Int
    let index: OverviewTopologyIndex
    let language: AppLanguage
    let interaction: OverviewTopologyInteractionState
    let onOpenPath: (ConnectionTopology.PathRecord) -> Void

    var body: some View {
        let snapshot = interaction.snapshot

        ZStack(alignment: .topLeading) {
            if let selection = snapshot.activeSelection {
                let label = OverviewTopologyProjection.selectionLabel(
                    selection,
                    in: index,
                    language: language
                )
                let description = OverviewTopologyProjection.selectionDescription(
                    selection,
                    in: index,
                    language: language
                )

                HStack(alignment: .top, spacing: MicaSpacing.space2) {
                    WorkbenchSymbol(
                        systemName: "pin.fill",
                        tint: MicaStyle.signalCyan,
                        font: .callout.weight(.semibold),
                        frameSize: 20
                    )
                        .opacity(snapshot.isPinned ? 1 : 0)
                    VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                        Text(verbatim: label)
                            .micaFont(.callout, weight: .semibold)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .textSelection(.enabled)
                        Text(verbatim: description)
                            .micaFont(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                    if snapshot.highlight.paths.count == 1,
                       let path = snapshot.highlight.paths.first {
                        WorkbenchIconCommand(
                            titleKey: WorkbenchDestination.connections.titleKey,
                            systemImage: "arrow.right"
                        ) {
                            onOpenPath(path)
                        }
                    }
                }
                .padding(.horizontal, MicaSpacing.module)
                .padding(.vertical, MicaSpacing.row)
                .help("\(label)\n\(description)")
            } else {
                OverviewTopologyIdleSummary(
                    connectionCount: connectionCount,
                    unavailablePathCount: unavailablePathCount,
                    language: language
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(
            height: OverviewTopologyLayout.selectionDetailHeight,
            alignment: .topLeading
        )
    }
}

private struct OverviewTopologyIdleSummary: View {
    let connectionCount: Int
    let unavailablePathCount: Int
    let language: AppLanguage

    var body: some View {
        HStack(spacing: MicaSpacing.section) {
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
        .padding(.horizontal, MicaSpacing.module)
        .padding(.vertical, MicaSpacing.row)
        .accessibilityElement(children: .combine)
    }

    private func metric(value: Int, titleKey: String) -> some View {
        VStack(alignment: .leading, spacing: MicaSpacing.tight) {
            Text(verbatim: value.formatted())
                .micaFont(.title3, weight: .semibold, design: .monospaced)
                .textSelection(.enabled)
            Text(MicaStrings.localizedKey(titleKey, language: language))
                .micaFont(.caption)
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
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            HStack(spacing: MicaSpacing.row) {
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
                .micaFont(.caption, weight: .semibold)
                Text(verbatim: paths.count.formatted())
                    .micaFont(.caption, design: .monospaced)
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

        return HStack(alignment: .top, spacing: MicaSpacing.row) {
            Button {
                interaction.togglePinnedPath(path.id)
            } label: {
                HStack(alignment: .top, spacing: MicaSpacing.row) {
                    Image(systemName: isPinned ? "pin.fill" : "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(isActive ? MicaStyle.signalCyan : .secondary)
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            verbatim: OverviewTopologyProjection.pathLabel(
                                path,
                                language: language
                            )
                        )
                        .micaFont(.callout, weight: .medium)
                        .textSelection(.enabled)
                        Text(
                            verbatim: OverviewTopologyProjection.pathDescription(
                                path,
                                language: language
                            )
                        )
                        .micaFont(.caption)
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
        .padding(.horizontal, MicaSpacing.row)
        .padding(.vertical, MicaSpacing.row)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isActive ? MicaStyle.accentSoft : .clear)
        .contentShape(Rectangle())
    }
}

private struct OverviewTopologyBandLayers: View, @MainActor Equatable {
    let request: OverviewTopologyRequest
    let band: OverviewTopologyLayout.RenderBand
    let layout: OverviewTopologyLayout
    let language: AppLanguage
    let fontScale: AppFontScale
    let interaction: OverviewTopologyInteractionState

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.request == rhs.request
            && lhs.band.id == rhs.band.id
            && lhs.language == rhs.language
            && lhs.fontScale == rhs.fontScale
            && lhs.interaction === rhs.interaction
    }

    var body: some View {
        ZStack {
            OverviewTopologyBaseBand(
                request: request,
                band: band,
                language: language,
                fontScale: fontScale
            )
            .equatable()

            OverviewTopologyHighlightBand(
                band: band,
                fontScale: fontScale,
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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.request == rhs.request
            && lhs.band.id == rhs.band.id
            && lhs.language == rhs.language
            && lhs.fontScale == rhs.fontScale
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
                    .font(
                        .system(
                            size: fontScale.pointSize(for: MicaTextStyle.callout.basePointSize),
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.secondary)
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
                    fontPointSize: fontScale.pointSize(
                        for: MicaTextStyle.callout.basePointSize
                    ),
                    in: &context
                )
            }
        }
        .background(MicaStyle.contentFill)
        .accessibilityHidden(true)
    }
}

private struct OverviewTopologyHighlightBand: View {
    let band: OverviewTopologyLayout.RenderBand
    let fontScale: AppFontScale
    let interaction: OverviewTopologyInteractionState

    var body: some View {
        let snapshot = interaction.snapshot

        ZStack {
            MicaStyle.contentFill
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
                        isHighlighted: true,
                        fontPointSize: fontScale.pointSize(
                            for: MicaTextStyle.callout.basePointSize
                        ),
                        in: &context
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
    let paths: [ConnectionTopology.PathRecord]
    let groups: [OverviewTopologyIndex.AccessibilityGroup]
    let language: AppLanguage
    let interaction: OverviewTopologyInteractionState
    let onOpenPath: (ConnectionTopology.PathRecord) -> Void

    var body: some View {
        LazyVStack {
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            MicaStrings.localizedKey("dashboard.chain_label", language: language)
        )
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
    static func drawEdge(
        _ edge: OverviewTopologyLayout.EdgeGeometry,
        isHighlighted: Bool = false,
        in context: inout GraphicsContext
    ) {
        let sourceColor = isHighlighted
            ? MicaStyle.signalCyan
            : stageColor(for: edge.edge.sourceLayer)
        let targetColor = isHighlighted
            ? MicaStyle.signalCyan
            : stageColor(for: edge.edge.targetLayer)
        context.fill(
            edge.drawingPath,
            with: .linearGradient(
                Gradient(colors: [
                    sourceColor.opacity(isHighlighted ? 0.92 : 0.38),
                    targetColor.opacity(isHighlighted ? 0.92 : 0.38),
                ]),
                startPoint: edge.source,
                endPoint: edge.target
            )
        )
        if isHighlighted {
            context.stroke(
                edge.drawingPath,
                with: .color(Color.primary.opacity(0.62)),
                lineWidth: 1
            )
        }
    }

    static func drawNode(
        _ node: OverviewTopologyLayout.NodeGeometry,
        isHighlighted: Bool = false,
        fontPointSize: CGFloat,
        in context: inout GraphicsContext
    ) {
        let color = isHighlighted
            ? MicaStyle.signalCyan
            : stageColor(for: node.node.layer)
        context.fill(
            node.drawingPath,
            with: .color(color.opacity(isHighlighted ? 1 : 0.82))
        )
        if isHighlighted {
            context.stroke(
                node.drawingPath,
                with: .color(Color.primary.opacity(0.72)),
                lineWidth: 1
            )
        }
        let label = context.resolve(
            Text(verbatim: node.node.name)
                .font(.system(size: fontPointSize))
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

    private static func stageColor(
        for layer: ConnectionTopology.Layer
    ) -> Color {
        switch layer {
        case .source:
            MicaStyle.signalViolet
        case .rule:
            MicaStyle.signalAmber
        case .proxyEntry:
            MicaStyle.signalCyan
        case .proxyExit:
            MicaStyle.signalMint
        }
    }
}
