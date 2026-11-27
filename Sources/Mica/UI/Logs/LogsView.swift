import AppKit
import MicaCore
import SwiftUI

struct LogsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WorkspaceUIState.self) private var uiState
    @Environment(\.micaAppLanguage) private var language

    @Binding var searchText: String
    @State private var store = LogsStore()
    @State private var selectedLogID: String?
    @State private var followLatest = true

    var body: some View {
        let _ = store.sync(catalog: appModel.logsCatalog)

        VStack(spacing: 0) {
            headerBar
            MicaHairlineDivider()
            logsContent
        }
        .background(MicaTheme.canvas)
        .onAppear {
            store.searchQuery = searchText
        }
        .onChange(of: searchText) { _, newValue in
            store.searchQuery = newValue
        }
        .onChange(of: selectedLogID) { _, id in
            if let id {
                uiState.selectInspector(.log(id: id))
            } else if case .log = uiState.inspectorSelection {
                uiState.dismissInspector()
            }
        }
    }

    private var headerBar: some View {
        let isPaused = appModel.controllerSessionPresentation.controls.logsPresentationPaused

        return HStack(spacing: MicaTheme.Spacing.md) {
            Picker("", selection: $store.levelFilter) {
                ForEach(LogLevelFilter.allCases) { level in
                    Text(L(level.labelKey, language: language)).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)

            HStack(spacing: MicaTheme.Spacing.sm) {
                Text(verbatim: "\(store.rows.count)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(MicaTheme.textSecondary)

                if store.errorCount > 0 {
                    Text(verbatim: "E \(store.errorCount)")
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .foregroundStyle(MicaTheme.statusError)
                }

                if store.warningCount > 0 {
                    Text(verbatim: "W \(store.warningCount)")
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .foregroundStyle(MicaTheme.statusWarning)
                }
            }

            Spacer(minLength: MicaTheme.Spacing.sm)

            Toggle(L("traffic.follow_bottom", language: language), isOn: $followLatest)
                .toggleStyle(.checkbox)
                .controlSize(.small)

            Button {
                appModel.toggleControllerLogsPaused()
            } label: {
                Label(
                    L(isPaused ? "live.resume" : "live.pause", language: language),
                    systemImage: isPaused ? "play" : "pause"
                )
            }

            Button {
                appModel.clearControllerLogs()
            } label: {
                Label(L("traffic.clear_logs", language: language), systemImage: "trash")
            }
            .disabled(appModel.logsCatalog.entries.isEmpty)
        }
        .padding(.horizontal, MicaTheme.Spacing.lg)
        .padding(.vertical, MicaTheme.Spacing.sm)
    }

    @ViewBuilder
    private var logsContent: some View {
        if appModel.logsCatalog.entries.isEmpty {
            MicaEmptyStateView(
                systemImage: "doc.text.magnifyingglass",
                title: L("dashboard.no_logs_yet", language: language),
                message: L("dashboard.no_logs_yet_message", language: language)
            )
        } else if store.rows.isEmpty {
            MicaEmptyStateView(
                systemImage: "magnifyingglass",
                title: L("dashboard.no_matching_logs", language: language),
                actionTitle: L("action.clear_search", language: language),
                action: {
                    store.levelFilter = .all
                    searchText = ""
                }
            )
        } else {
            ScrollViewReader { proxy in
                List(store.rows, selection: $selectedLogID) { row in
                    LogEntryRow(row: row)
                        .tag(row.id)
                        .contextMenu {
                            Button(L("action.copy_full_log", language: language)) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(
                                    "[\(row.timeText)] [\(row.level)] \(row.message)",
                                    forType: .string
                                )
                            }
                        }
                }
                .listStyle(.inset)
                .onChange(of: store.rows.last?.id) { _, lastID in
                    guard followLatest, let lastID else { return }
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }
}

private struct LogEntryRow: View, Equatable {
    let row: LogRowItem

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MicaTheme.Spacing.sm) {
            Text(verbatim: row.timeText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(MicaTheme.textTertiary)
                .frame(width: 60, alignment: .leading)

            Text(verbatim: row.level)
                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                .foregroundStyle(levelColor)
                .frame(width: 56, alignment: .leading)

            Text(verbatim: row.message)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(MicaTheme.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }

    private var levelColor: Color {
        switch row.normalizedLevel {
        case "error", "err", "fatal", "panic":
            MicaTheme.statusError
        case "warning", "warn":
            MicaTheme.statusWarning
        case "debug", "trace":
            MicaTheme.textTertiary
        default:
            MicaTheme.statusInfo
        }
    }
}
