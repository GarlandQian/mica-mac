import Foundation
import MicaCore
import SwiftUI

struct WorkbenchConnectionsView: View {
    var appModel: AppModel
    @Binding var searchText: String

    @Environment(\.micaAppLanguage) private var appLanguage
    @Environment(\.micaFontMultiplier) private var fontMultiplier
    @State private var tab: ConnectionSessionTab = .active
    @State private var selectedConnectionID: String?
    @State private var pendingCloseID: String?
    @State private var pendingCloseGroupID: String?
    @State private var pendingCloseAll = false
    @State private var groupsByOwner = false
    @State private var connectionSortOrder = ConnectionWorkbenchPresentation.defaultSortOrder

    var body: some View {
        VStack(spacing: 0) {
            commandRow
            Divider()
            surfaceContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .background(MicaStyle.pageFill)
        .onChange(of: appModel.selectedRouterID) {
            tab = .active
            selectedConnectionID = nil
            pendingCloseID = nil
            pendingCloseGroupID = nil
            pendingCloseAll = false
        }
        .onChange(of: sourceConnections.map(\.id)) { _, ids in
            selectedConnectionID = ConnectionWorkbenchPresentation.reconciledSelection(
                selectedConnectionID,
                in: sourceConnections
            )
            if let pendingCloseID, !ids.contains(pendingCloseID) {
                self.pendingCloseID = nil
            }
            if let pendingCloseGroupID,
               !connectionOwnerGroups.contains(where: { $0.id == pendingCloseGroupID }) {
                self.pendingCloseGroupID = nil
            }
        }
        .onChange(of: groupsByOwner) {
            pendingCloseGroupID = nil
        }
    }

    private var commandRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker(
                    MicaStrings.localizedKey("traffic.connection_tab", language: appLanguage),
                    selection: $tab
                ) {
                    Text(MicaStrings.localizedKey("traffic.connection_tab_active", language: appLanguage))
                        .tag(ConnectionSessionTab.active)
                    Text(MicaStrings.localizedKey("traffic.connection_tab_closed", language: appLanguage))
                        .tag(ConnectionSessionTab.closed)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280 * fontMultiplier)
                .accessibilityLabel(MicaStrings.localizedKey("traffic.connection_tab", language: appLanguage))

                Text(
                    MicaStrings.localized(
                        "traffic.connection_count_pair \(appModel.dashboard.connections.count) \(appModel.dashboardSessionControls.closedConnections.count)",
                        language: appLanguage
                    )
                )
                .font(.system(size: 11.5 * fontMultiplier, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

                Toggle(
                    MicaStrings.localizedKey("traffic.group_connections_by_owner", language: appLanguage),
                    isOn: $groupsByOwner
                )
                .toggleStyle(.checkbox)
                .disabled(sourceConnections.isEmpty)

                Spacer()

                if tab == .active {
                    Button {
                        pendingCloseAll = true
                        pendingCloseID = nil
                    } label: {
                        MicaLabel("action.close_all", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(MicaStyle.signalRed)
                    .disabled(
                            appModel.dashboard.connections.isEmpty
                                || appModel.isBusy
                            || !supportsCloseAll
                    )
                    .accessibilityLabel(MicaStrings.localizedKey("action.close_all", language: appLanguage))
                } else {
                    Button {
                        appModel.clearClosedConnections()
                        selectedConnectionID = nil
                        pendingCloseID = nil
                    } label: {
                        MicaLabel("traffic.clear_closed", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(appModel.dashboardSessionControls.closedConnections.isEmpty)
                    .help(MicaStrings.localizedKey("traffic.help_clear_closed", language: appLanguage))
                }
            }

            if let activeConnectionStaleMessage {
                Label(activeConnectionStaleMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5 * fontMultiplier, weight: .medium))
                    .foregroundStyle(MicaStyle.signalAmber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if pendingCloseAll {
                closeAllConfirmation
            }

            if pendingCloseGroupID != nil {
                closeGroupConfirmation
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(MicaStyle.contentFill)
    }

    private var activeConnectionStaleMessage: String? {
        guard tab == .active,
              !appModel.dashboard.connections.isEmpty,
              case .failed(let message) = appModel.controllerHealth.status(for: .connections) else {
            return nil
        }
        return MicaStrings.localized("data.stale_detail \(message)", language: appLanguage)
    }

    private var closeAllConfirmation: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(
                MicaStrings.localized(
                    "dashboard.confirm_close_all_message \(appModel.dashboard.connections.count) \(selectedRouterName)",
                    language: appLanguage
                )
            )
            .font(.system(size: 12 * fontMultiplier))
            .foregroundStyle(MicaStyle.signalRed)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(MicaStrings.localizedKey("action.cancel", language: appLanguage)) {
                    pendingCloseAll = false
                }
                .buttonStyle(.bordered)

                Button(MicaStrings.localizedKey("dashboard.confirm_close_all_button", language: appLanguage)) {
                    appModel.closeAllConnections()
                    pendingCloseAll = false
                }
                .buttonStyle(.borderedProminent)
                .tint(MicaStyle.signalRed)
                .disabled(appModel.isBusy || !supportsCloseAll)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MicaStrings.localizedKey("dashboard.confirm_close_all_title", language: appLanguage))
    }

    @ViewBuilder
    private var closeGroupConfirmation: some View {
        if let group = pendingCloseGroup {
            VStack(alignment: .leading, spacing: 7) {
                Text(
                    MicaStrings.localized(
                        "dashboard.confirm_close_connection_group_message \(group.connectionCount) \(connectionGroupLabel(group)) \(selectedRouterName)",
                        language: appLanguage
                    )
                )
                .font(.system(size: 12 * fontMultiplier))
                .foregroundStyle(MicaStyle.signalRed)
                .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button(MicaStrings.localizedKey("action.cancel", language: appLanguage)) {
                        pendingCloseGroupID = nil
                    }
                    .buttonStyle(.bordered)

                    Button(MicaStrings.localizedKey("action.close_connection_group", language: appLanguage)) {
                        appModel.closeConnectionGroup(
                            group.connections,
                            groupID: group.id,
                            groupLabel: connectionGroupLabel(group)
                        )
                        pendingCloseGroupID = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MicaStyle.signalRed)
                    .disabled(appModel.isBusy || !supportsGroupedClose)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(MicaStrings.localizedKey("action.close_connection_group", language: appLanguage))
        }
    }

    @ViewBuilder
    private var surfaceContent: some View {
        switch surfaceState {
        case .unavailable:
            unavailableState(
                titleKey: "traffic.data_not_loaded",
                message: MicaStrings.localizedKey("overview.no_controller_data", language: appLanguage)
            )
        case .empty:
            unavailableState(
                titleKey: tab == .active ? "dashboard.no_active_connections" : "traffic.no_closed_connections",
                message: MicaStrings.localizedKey("overview.config_not_reported", language: appLanguage)
            )
        case .filteredEmpty:
            unavailableState(
                titleKey: "dashboard.no_matching_connections",
                message: MicaStrings.localizedKey("traffic.empty_filtered", language: appLanguage)
            )
        case .content:
            connectionTable
                .inspector(isPresented: inspectorPresented) {
                    connectionInspector
                        .inspectorColumnWidth(min: 290 * fontMultiplier, ideal: 360 * fontMultiplier, max: 520 * fontMultiplier)
                }
        }
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { selectedConnectionID != nil },
            set: { presented in
                if !presented { selectedConnectionID = nil }
            }
        )
    }

    private var connectionTable: some View {
        Table(
            of: ConnectionSnapshot.self,
            selection: $selectedConnectionID,
            sortOrder: $connectionSortOrder
        ) {
            TableColumn(MicaStrings.localizedKey("traffic.connection_host", language: appLanguage), value: \.sortableHost) { connection in
                VStack(alignment: .leading, spacing: 3) {
                    Text(primaryHost(connection))
                        .font(.system(size: 12 * fontMultiplier, weight: .medium))
                    Text(address(connection.metadata?.destinationIP, port: connection.metadata?.destinationPort))
                        .font(.system(size: 10.5 * fontMultiplier, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .width(min: 190 * fontMultiplier, ideal: 270 * fontMultiplier)

            TableColumn(MicaStrings.localizedKey("dashboard.col_id", language: appLanguage)) { connection in
                Text(connection.id)
                    .font(.system(size: 11 * fontMultiplier, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .width(min: 180 * fontMultiplier, ideal: 260 * fontMultiplier)

            TableColumn(MicaStrings.localizedKey("traffic.connection_process", language: appLanguage)) { connection in
                Text(processSummary(connection))
                    .font(.system(size: 11 * fontMultiplier))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .width(min: 160 * fontMultiplier, ideal: 250 * fontMultiplier)

            TableColumn(MicaStrings.localizedKey("traffic.connection_network", language: appLanguage)) { connection in
                Text(networkLabel(connection))
                    .font(.system(size: 11 * fontMultiplier, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .width(min: 105 * fontMultiplier, ideal: 140 * fontMultiplier)

            TableColumn(MicaStrings.localizedKey("dashboard.col_chain", language: appLanguage)) { connection in
                Text(routeChain(connection))
                    .font(.system(size: 11 * fontMultiplier))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .width(min: 160 * fontMultiplier, ideal: 260 * fontMultiplier)

            TableColumn(MicaStrings.localizedKey("dashboard.col_upload", language: appLanguage), value: \.sortableUpload) { connection in
                transferSummary(total: connection.upload, speed: connection.uploadSpeed)
            }
            .width(min: 98 * fontMultiplier, ideal: 120 * fontMultiplier)

            TableColumn(MicaStrings.localizedKey("dashboard.col_download", language: appLanguage), value: \.sortableDownload) { connection in
                transferSummary(total: connection.download, speed: connection.downloadSpeed)
            }
            .width(min: 98 * fontMultiplier, ideal: 120 * fontMultiplier)

            TableColumn(MicaStrings.localizedKey("traffic.start_time", language: appLanguage), value: \.sortableStart) { connection in
                Text(reported(connection.start))
                    .font(.system(size: 11 * fontMultiplier, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .width(min: 130 * fontMultiplier, ideal: 170 * fontMultiplier)
        } rows: {
            if groupsByOwner {
                ForEach(connectionOwnerGroups) { group in
                    Section {
                        ForEach(group.connections) { connection in
                            TableRow(connection)
                        }
                    } header: {
                        connectionGroupHeader(group)
                    }
                }
            } else {
                ForEach(sortedConnections) { connection in
                    TableRow(connection)
                }
            }
        }
        .tableStyle(.inset)
        .accessibilityLabel(MicaStrings.localizedKey("dashboard.tab_connections", language: appLanguage))
    }

    private func connectionGroupHeader(_ group: WorkbenchConnectionOwnerGroup) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(connectionGroupLabel(group))
                    .font(.system(size: 11.5 * fontMultiplier, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let processPath = group.processPath {
                    Text(processPath)
                        .font(.system(size: 10 * fontMultiplier, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(
                MicaStrings.localized(
                    "traffic.connection_group_summary \(group.connectionCount) \(byteRate(group.uploadSpeed)) \(byteRate(group.downloadSpeed))",
                    language: appLanguage
                )
            )
            .font(.system(size: 10.5 * fontMultiplier, design: .monospaced))
            .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if tab == .active, supportsGroupedClose {
                Button {
                    pendingCloseGroupID = group.id
                    pendingCloseID = nil
                    pendingCloseAll = false
                } label: {
                    if appModel.closingConnectionGroupID == group.id {
                        ProgressView()
                    } else {
                        Image(systemName: "xmark.circle")
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .foregroundStyle(MicaStyle.signalRed)
                .disabled(appModel.isBusy)
                .help(MicaStrings.localizedKey("traffic.help_close_connection_group", language: appLanguage))
                .accessibilityLabel(MicaStrings.localizedKey("action.close_connection_group", language: appLanguage))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var connectionInspector: some View {
        if let connection = selectedConnection {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        MicaText("traffic.detail_connection")
                            .font(.system(size: 15 * fontMultiplier, weight: .semibold))
                        Text(primaryHost(connection))
                            .font(.system(size: 12.5 * fontMultiplier, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(connection.id)
                            .font(.system(size: 11 * fontMultiplier, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()
                    WorkbenchInspectorValueRow(titleKey: "dashboard.col_id", value: connection.id, monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.connection_host", value: primaryHost(connection))
                    WorkbenchInspectorValueRow(titleKey: "traffic.connection_process", value: reported(connection.metadata?.process))
                    WorkbenchInspectorValueRow(titleKey: "traffic.connection_process_path", value: reported(connection.metadata?.processPath), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.connection_network", value: reported(connection.metadata?.network), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.connection_type", value: reported(connection.metadata?.type), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.connection_source", value: address(connection.metadata?.sourceIP, port: connection.metadata?.sourcePort), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.connection_destination", value: address(connection.metadata?.destinationIP, port: connection.metadata?.destinationPort), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.inbound_address", value: address(connection.metadata?.inboundIP, port: connection.metadata?.inboundPort), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.inbound_name", value: reported(connection.metadata?.inboundName))
                    WorkbenchInspectorValueRow(titleKey: "traffic.dns_mode", value: reported(connection.metadata?.dnsMode))
                    WorkbenchInspectorValueRow(titleKey: "traffic.sniff_host", value: reported(connection.metadata?.sniffHost))
                    WorkbenchInspectorValueRow(titleKey: "traffic.remote_destination", value: reported(connection.metadata?.remoteDestination), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.special_proxy", value: reported(connection.metadata?.specialProxy))
                    WorkbenchInspectorValueRow(titleKey: "traffic.special_rules", value: reported(connection.metadata?.specialRules), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.connection_uid", value: connection.metadata?.uid.map(String.init) ?? unavailableValue, monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "dashboard.col_rule", value: reported(connection.rule))
                    WorkbenchInspectorValueRow(titleKey: "dashboard.col_payload", value: reported(connection.rulePayload), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "dashboard.col_chain", value: routeChain(connection))
                    WorkbenchInspectorValueRow(titleKey: "traffic.provider_chain", value: providerRouteChain(connection))
                    WorkbenchInspectorValueRow(titleKey: "dashboard.col_upload", value: byteCount(connection.upload), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.upload_speed", value: byteRate(connection.uploadSpeed), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "dashboard.col_download", value: byteCount(connection.download), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.download_speed", value: byteRate(connection.downloadSpeed), monospaced: true)
                    WorkbenchInspectorValueRow(titleKey: "traffic.start_time", value: reported(connection.start), monospaced: true)
                    WorkbenchInspectorValueRow(
                        titleKey: "traffic.connection_logs",
                        value: reported(connection.metadata?.connectionLogs?.joined(separator: "\n")),
                        monospaced: true
                    )
                    WorkbenchInspectorValueRow(
                        titleKey: "traffic.connection_metadata_fields",
                        value: reported(connection.metadata?.additionalFieldsText),
                        monospaced: true
                    )
                    WorkbenchInspectorValueRow(
                        titleKey: "traffic.connection_additional_fields",
                        value: reported(connection.additionalFieldsText),
                        monospaced: true
                    )

                    if tab == .active {
                        Divider()
                        closeControl(connection)
                    }
                }
            }
            .background(MicaStyle.contentFill)
        } else {
            ContentUnavailableView {
                Label {
                    MicaText("traffic.detail_connection")
                } icon: {
                    Image(systemName: "sidebar.right")
                }
            } description: {
                MicaText("traffic.context_empty_connection")
            }
            .background(MicaStyle.contentFill)
        }
    }

    private func closeControl(_ connection: ConnectionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if pendingCloseID == connection.id {
                Text(
                    MicaStrings.localized(
                        "dashboard.confirm_close_connection_message \(selectedRouterName)",
                        language: appLanguage
                    )
                )
                .font(.system(size: 12 * fontMultiplier))
                .foregroundStyle(MicaStyle.signalRed)
                .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button(MicaStrings.localizedKey("action.cancel", language: appLanguage)) {
                        pendingCloseID = nil
                    }
                    .buttonStyle(.bordered)

                    Button(MicaStrings.localizedKey("dashboard.confirm_close_connection_button", language: appLanguage)) {
                        appModel.closeConnection(connection)
                        pendingCloseID = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MicaStyle.signalRed)
                    .disabled(appModel.isBusy || !supportsSingleClose)
                }
            } else {
                Button {
                    pendingCloseID = connection.id
                    pendingCloseAll = false
                } label: {
                    MicaLabel("action.close_connection", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .tint(MicaStyle.signalRed)
                .disabled(appModel.isBusy || !supportsSingleClose)
                .help(MicaStrings.localizedKey("traffic.help_inspector_close_connection", language: appLanguage))
            }
        }
        .padding(12)
    }

    private func unavailableState(titleKey: String, message: String) -> some View {
        ContentUnavailableView {
            Label {
                MicaText(titleKey)
            } icon: {
                Image(systemName: "link")
            }
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sourceConnections: [ConnectionSnapshot] {
        switch tab {
        case .active:
            appModel.dashboard.connections
        case .closed:
            appModel.dashboardSessionControls.closedConnections
        }
    }

    private var filteredConnections: [ConnectionSnapshot] {
        ConnectionWorkbenchPresentation.filtered(sourceConnections, matching: searchText)
    }

    private var sortedConnections: [ConnectionSnapshot] {
        ConnectionWorkbenchPresentation.ordered(filteredConnections, using: connectionSortOrder)
    }

    private var connectionOwnerGroups: [WorkbenchConnectionOwnerGroup] {
        ConnectionWorkbenchPresentation.ownerGroups(sortedConnections)
    }

    private var pendingCloseGroup: WorkbenchConnectionOwnerGroup? {
        guard let pendingCloseGroupID else { return nil }
        return connectionOwnerGroups.first { $0.id == pendingCloseGroupID }
    }

    private var selectedConnection: ConnectionSnapshot? {
        guard let selectedConnectionID else { return nil }
        return sourceConnections.first { $0.id == selectedConnectionID }
    }

    private var supportsGroupedClose: Bool {
        guard supportsSingleClose,
              let router = appModel.selectedRouter else {
            return false
        }
        return appModel.runtimeControllerKind(for: router) != .singBoxCompatible
    }

    private var supportsSingleClose: Bool {
        guard let router = appModel.selectedRouter else { return false }
        let action: UnifiedControllerAction = appModel.runtimeControllerKind(for: router) == .surgeCompatible
            ? .killActiveRequest
            : .closeConnection
        return appModel.supportsUnifiedAction(action)
    }

    private var supportsCloseAll: Bool {
        guard let router = appModel.selectedRouter else { return false }
        let action: UnifiedControllerAction = appModel.runtimeControllerKind(for: router) == .surgeCompatible
            ? .killActiveRequest
            : .closeAllConnections
        return appModel.supportsUnifiedAction(action)
    }

    private var surfaceState: WorkbenchDataSurfaceState {
        WorkbenchDataSurfaceState.resolve(
            isUnavailable: tab == .active && !appModel.dashboard.hasBaseSnapshot && sourceConnections.isEmpty,
            sourceCount: sourceConnections.count,
            visibleCount: filteredConnections.count
        )
    }

    private func primaryHost(_ connection: ConnectionSnapshot) -> String {
        connection.metadata?.host?.nilIfEmpty
            ?? connection.metadata?.sniffHost?.nilIfEmpty
            ?? connection.metadata?.destinationIP?.nilIfEmpty
            ?? unavailableValue
    }

    private func processSummary(_ connection: ConnectionSnapshot) -> String {
        [connection.metadata?.process?.nilIfEmpty, connection.metadata?.processPath?.nilIfEmpty]
            .compactMap { $0 }
            .joined(separator: "\n")
            .nilIfEmpty ?? unavailableValue
    }

    private func networkLabel(_ connection: ConnectionSnapshot) -> String {
        [connection.metadata?.network?.nilIfEmpty, connection.metadata?.type?.nilIfEmpty]
            .compactMap { $0 }
            .joined(separator: " / ")
            .nilIfEmpty ?? unavailableValue
    }

    private func routeChain(_ connection: ConnectionSnapshot) -> String {
        let chain = connection.chains?.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
        return chain.isEmpty ? unavailableValue : chain.joined(separator: " / ")
    }

    private func providerRouteChain(_ connection: ConnectionSnapshot) -> String {
        let chain = connection.providerChains?.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? []
        return chain.isEmpty ? unavailableValue : chain.joined(separator: " / ")
    }

    private func connectionGroupLabel(_ group: WorkbenchConnectionOwnerGroup) -> String {
        switch group.owner {
        case .inner:
            return MicaStrings.localizedKey("traffic.connection_group_inner", language: appLanguage)
        case .process(let value), .source(let value):
            return value
        case .unreported:
            return MicaStrings.localizedKey("traffic.connection_group_unreported", language: appLanguage)
        }
    }

    private func transferSummary(total: Int?, speed: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(byteCount(total))
                .font(.system(size: 11 * fontMultiplier, design: .monospaced))
            Text(byteRate(speed))
                .font(.system(size: 10 * fontMultiplier, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func address(_ host: String?, port: String?) -> String {
        let host = host?.nilIfEmpty
        let port = port?.nilIfEmpty
        switch (host, port) {
        case let (.some(host), .some(port)):
            return host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
        case let (.some(host), .none):
            return host
        case let (.none, .some(port)):
            return port
        case (.none, .none):
            return unavailableValue
        }
    }

    private func reported(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? unavailableValue
    }

    private func byteCount(_ bytes: Int?) -> String {
        guard let bytes else { return unavailableValue }
        let formatter = ByteCountFormatter()
        formatter.allowsNonnumericFormatting = false
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(max(bytes, 0)))
    }

    private func byteRate(_ bytes: Int?) -> String {
        guard let bytes else { return unavailableValue }
        return MicaStrings.localized("traffic.bytes_per_second \(byteCount(bytes))", language: appLanguage)
    }

    private var unavailableValue: String {
        MicaStrings.localizedKey("overview.config_not_reported", language: appLanguage)
    }

    private var selectedRouterName: String {
        appModel.selectedRouter?.displayName ?? unavailableValue
    }
}
