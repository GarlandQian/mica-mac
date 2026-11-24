import MicaCore
import SwiftUI

struct WorkbenchSidebarView: View {
    @Environment(\.micaAppLanguage) private var language

    @Binding var destination: WorkbenchDestination

    var isEditingController: Bool = false
    let isControllerSwitchingEnabled: Bool
    let onSelectController: (RouterProfile) -> Void
    let onAddController: () -> Void

    var body: some View {
        List(selection: selection) {
            ForEach(WorkbenchDestination.Group.allCases) { group in
                Section {
                    ForEach(group.destinations) { item in
                        HStack(spacing: MicaTheme.Spacing.space2) {
                            Label {
                                Text(
                                    MicaStrings.localizedKey(
                                        item.titleKey,
                                        language: language
                                    )
                                )
                                .micaThemeFont(.body)
                                .lineLimit(1)
                            } icon: {
                                Image(systemName: item.symbolName)
                                    .symbolRenderingMode(.monochrome)
                            }

                            Spacer(minLength: 4)

                            WorkbenchSidebarDestinationBadge(destination: item)
                        }
                        .padding(.vertical, 3)
                        .tag(item)
                        .help(
                            MicaStrings.localizedKey(
                                item.titleKey,
                                language: language
                            )
                        )
                    }
                } header: {
                    Text(
                        MicaStrings.localizedKey(
                            group.titleKey,
                            language: language
                        )
                    )
                    .micaThemeFont(.caption, weight: .semibold)
                    .foregroundStyle(MicaTheme.textTertiary)
                }
            }
        }
        .listStyle(.sidebar)
        // The controller switcher stays pinned while navigation scrolls
        // beneath it with the native Liquid Glass scroll-edge effect.
        .safeAreaBar(edge: .top, spacing: 0) {
            WorkbenchSidebarControllerSwitcher(
                isEnabled: isControllerSwitchingEnabled,
                onSelectController: onSelectController,
                onAddController: onAddController,
                onManageControllers: { destination = .controllers }
            )
            .padding(.horizontal, MicaTheme.Spacing.space2)
            .padding(.bottom, MicaTheme.Spacing.space2)
        }
        .tint(MicaTheme.accent)
        .navigationTitle("Mica")
    }

    private var selection: Binding<WorkbenchDestination?> {
        Binding(
            get: { isEditingController ? nil : destination },
            set: { next in
                guard let next else { return }
                guard isEditingController || next != destination else { return }
                destination = next
            }
        )
    }
}

private struct WorkbenchSidebarDestinationBadge: View {
    let destination: WorkbenchDestination

    var body: some View {
        switch destination {
        case .connections:
            WorkbenchConnectionsSidebarBadge()
        case .logs:
            WorkbenchLogsSidebarBadge()
        case .diagnostics:
            WorkbenchDiagnosticsSidebarBadge()
        default:
            EmptyView()
        }
    }
}

private struct WorkbenchConnectionsSidebarBadge: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let count = appModel.connectionsCatalog.connections.count
        if appModel.selectedRouter != nil, count > 0 {
            Text(verbatim: count > 999 ? "999+" : count.formatted())
                .micaThemeFont(.dataCaption, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(MicaTheme.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(MicaTheme.surfaceHover, in: Capsule())
        }
    }
}

private struct WorkbenchLogsSidebarBadge: View {
    @Environment(AppModel.self) private var appModel
    @State private var lastCheckedRevision: UInt64 = 0
    @State private var hasErrorLogs = false

    var body: some View {
        Circle()
            .fill(MicaTheme.statusError)
            .frame(width: 6, height: 6)
            .opacity(appModel.selectedRouter != nil && hasErrorLogs ? 1 : 0)
            .accessibilityHidden(true)
            .onAppear {
                syncErrorIndicator()
            }
            .onChange(of: appModel.logsCatalog.entriesRevision) { _, _ in
                syncErrorIndicator()
            }
            .onChange(of: appModel.selectedRouterID) { _, _ in
                hasErrorLogs = false
                lastCheckedRevision = 0
                syncErrorIndicator()
            }
    }

    private func syncErrorIndicator() {
        let catalog = appModel.logsCatalog
        guard appModel.selectedRouter != nil, !catalog.entries.isEmpty else {
            hasErrorLogs = false
            lastCheckedRevision = catalog.entriesRevision
            return
        }
        guard catalog.entriesRevision != lastCheckedRevision else { return }
        if lastCheckedRevision != 0,
           catalog.entriesRevision == lastCheckedRevision &+ 1,
           case let .delta(dropped, appended) = catalog.lastChange,
           dropped.isEmpty {
            if !hasErrorLogs {
                hasErrorLogs = appended.contains(where: Self.isErrorEntry)
            }
        } else {
            hasErrorLogs = catalog.entries.contains(where: Self.isErrorEntry)
        }
        lastCheckedRevision = catalog.entriesRevision
    }

    private static func isErrorEntry(_ entry: ControllerLogEntry) -> Bool {
        let raw = (entry.message.level ?? entry.message.type)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return raw == "error" || raw == "err" || raw == "fatal" || raw == "panic"
    }
}

private struct WorkbenchDiagnosticsSidebarBadge: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if appModel.selectedRouter != nil, let tint = indicatorTint {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
        }
    }

    private var indicatorTint: Color? {
        switch appModel.controllerHealth.summary {
        case .wrongTarget, .authFailed, .offline:
            MicaTheme.statusError
        case .partial:
            MicaTheme.statusWarning
        case .ready, .checking, .unknown:
            nil
        }
    }
}
