import AppKit
import MicaCore
import SwiftUI

struct ConnectionsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkspaceUIState.self) private var uiState
    @Environment(\.micaAppLanguage) private var language

    @Binding var searchText: String
    @State private var store = ConnectionsStore()
    @State private var selectedConnectionID: String?

    var body: some View {
        let _ = store.sync(
            activeCatalog: appModel.connectionsCatalog,
            closedRecords: appModel.dashboardSessionControls.closedConnectionRecords,
            closedRevision: appModel.dashboardSessionControls.closedConnectionsRevision
        )

        VStack(spacing: 0) {
            headerBar
            MicaHairlineDivider()
            contentView
        }
        .background(MicaTheme.canvas)
        .onAppear {
            store.searchQuery = searchText
        }
        .onChange(of: searchText) { _, newValue in
            store.searchQuery = newValue
        }
        .onChange(of: selectedConnectionID) { _, id in
            if let id {
                uiState.selectInspector(.connection(id: id))
            } else if case .connection = uiState.inspectorSelection {
                uiState.dismissInspector()
            }
        }
    }

    private var headerBar: some View {
        let canCloseAll = appModel.controllerSessionPresentation.state.allowsLiveCommands
            && !appModel.hasConnectionOperationInFlight
            && !appModel.connectionsCatalog.connections.isEmpty

        return HStack(spacing: MicaTheme.Spacing.md) {
            Picker("", selection: $store.scope) {
                ForEach(ConnectionsScope.allCases) { scope in
                    Text(L(scope.titleKey, language: language)).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 190)

            Text(verbatim: "\(store.rows.count)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(MicaTheme.textSecondary)

            ConnectionsTrafficTotalsPill()

            Spacer(minLength: MicaTheme.Spacing.sm)

            if store.scope == .active {
                Button(role: .destructive) {
                    appModel.closeAllConnections()
                } label: {
                    Label(L("action.close_all", language: language), systemImage: "xmark.circle")
                }
                .disabled(!canCloseAll || appModel.closingAllConnections)
            } else {
                Button(role: .destructive) {
                    appModel.clearClosedConnections()
                } label: {
                    Label(L("traffic.clear_closed", language: language), systemImage: "trash")
                }
                .disabled(store.totalClosedCount == 0)
            }
        }
        .padding(.horizontal, MicaTheme.Spacing.lg)
        .padding(.vertical, MicaTheme.Spacing.sm)
    }

    @ViewBuilder
    private var contentView: some View {
        let totalInScope = store.scope == .active ? store.totalActiveCount : store.totalClosedCount

        if totalInScope == 0 {
            MicaEmptyStateView(
                systemImage: "arrow.up.arrow.down.circle",
                title: L(
                    store.scope == .active ? "dashboard.no_active_connections" : "traffic.no_closed_connections_title",
                    language: language
                ),
                message: L(
                    store.scope == .active ? "traffic.no_active_connections_message" : "traffic.no_closed_connections",
                    language: language
                )
            )
        } else if store.rows.isEmpty {
            MicaEmptyStateView(
                systemImage: "magnifyingglass",
                title: L("dashboard.no_matching_connections", language: language),
                actionTitle: L("action.clear_search", language: language),
                action: { searchText = "" }
            )
        } else {
            Table(store.rows, selection: $selectedConnectionID, sortOrder: $store.sortOrder) {
                TableColumn(L("traffic.connection_host", language: language), value: \.host) { row in
                    Text(verbatim: row.host)
                        .font(.callout)
                        .foregroundStyle(MicaTheme.textPrimary)
                        .lineLimit(1)
                }
                .width(min: 180, ideal: 250)

                TableColumn(L("traffic.connection_process", language: language), value: \.process) { row in
                    Text(verbatim: row.process)
                        .font(.caption)
                        .foregroundStyle(MicaTheme.textSecondary)
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 110, max: 160)

                TableColumn(L("dashboard.col_chain", language: language), value: \.chain) { row in
                    Text(verbatim: row.chain)
                        .font(.caption)
                        .foregroundStyle(MicaTheme.textSecondary)
                        .lineLimit(1)
                }
                .width(min: 140, ideal: 210)

                TableColumn(L("dashboard.tab_rules", language: language), value: \.rule) { row in
                    Text(verbatim: row.rule)
                        .font(.caption)
                        .foregroundStyle(MicaTheme.textTertiary)
                        .lineLimit(1)
                }
                .width(min: 100, ideal: 150)

                TableColumn(L("dashboard.col_download", language: language), value: \.downloadBytes) { row in
                    Text(verbatim: MicaFormatters.formatBytes(row.downloadBytes))
                        .font(.system(.caption, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(MicaTheme.textPrimary)
                }
                .width(min: 72, ideal: 86, max: 110)

                TableColumn(L("dashboard.col_upload", language: language), value: \.uploadBytes) { row in
                    Text(verbatim: MicaFormatters.formatBytes(row.uploadBytes))
                        .font(.system(.caption, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(MicaTheme.textSecondary)
                }
                .width(min: 72, ideal: 86, max: 110)

                TableColumn(L("overview.download_rate", language: language), value: \.totalRate) { row in
                    Text(verbatim: row.isActive && row.totalRate > 0 ? MicaFormatters.formatRate(row.totalRate) : row.durationText)
                        .font(.system(.caption, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(row.totalRate > 0 ? MicaTheme.chartDownload : MicaTheme.textTertiary)
                }
                .width(min: 80, ideal: 96, max: 120)
            }
            .contextMenu(forSelectionType: String.self) { selectedIDs in
                if let id = selectedIDs.first, let item = store.item(id: id) {
                    if item.isActive, canCloseConnection {
                        Button(L("action.close_connection", language: language), role: .destructive) {
                            appModel.closeConnection(item.snapshot)
                        }
                    }
                    Button(L("action.copy_host", language: language)) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.host, forType: .string)
                    }
                    Button(L("action.copy_process", language: language)) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.process, forType: .string)
                    }
                }
            }
        }
    }

    private var canCloseConnection: Bool {
        guard let router = appModel.selectedRouter else { return false }
        let action: UnifiedControllerAction = appModel.runtimeControllerKind(for: router) == .surgeCompatible
            ? .killActiveRequest
            : .closeConnection
        return appModel.controllerSessionPresentation.state.allowsLiveCommands
            && appModel.supportsUnifiedAction(action)
            && !appModel.hasConnectionOperationInFlight
    }
}

private struct ConnectionsTrafficTotalsPill: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let rate = appModel.liveTrafficRate
        HStack(spacing: MicaTheme.Spacing.sm) {
            Text(verbatim: "↑ \(MicaFormatters.formatRate(rate.upload))")
                .foregroundStyle(MicaTheme.chartUpload)
            Text(verbatim: "↓ \(MicaFormatters.formatRate(rate.download))")
                .foregroundStyle(MicaTheme.chartDownload)
        }
        .font(.system(.caption, design: .monospaced))
        .monospacedDigit()
    }
}
