import MicaCore
import SwiftUI

struct WorkbenchControllerSelectorItem: Identifiable, Equatable, Sendable {
    let id: RouterProfile.ID
    let profile: RouterProfile
    let displayName: String
    let endpointURL: String
    let compactEndpoint: String
    let symbolName: String

    init(profile: RouterProfile) {
        id = profile.id
        self.profile = profile
        displayName = profile.displayName
        endpointURL = profile.endpointURL
        compactEndpoint = Self.formatCompactEndpoint(profile.endpointURL)
        symbolName = profile.controllerKind.editorSymbol
    }

    private static func formatCompactEndpoint(_ raw: String) -> String {
        guard let url = URL(string: raw), let host = url.host else {
            return raw
        }
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }
}

struct WorkbenchControllerSelectorSnapshot: Equatable, Sendable {
    let items: [WorkbenchControllerSelectorItem]
    let selectedID: RouterProfile.ID?
    let selectedItem: WorkbenchControllerSelectorItem?

    init(profiles: [RouterProfile], selectedID: RouterProfile.ID?) {
        items = profiles.map(WorkbenchControllerSelectorItem.init(profile:))
        self.selectedID = selectedID
        selectedItem = items.first { $0.id == selectedID }
    }
}

struct WorkbenchSidebarControllerSwitcher: View {
    @Environment(AppModel.self) private var appModel

    let isEnabled: Bool
    let onSelectController: (RouterProfile) -> Void
    let onAddController: () -> Void
    let onManageControllers: () -> Void

    var body: some View {
        WorkbenchControllerSelector(
            snapshot: WorkbenchControllerSelectorSnapshot(
                profiles: appModel.routers,
                selectedID: appModel.selectedRouterID
            ),
            isEnabled: isEnabled,
            canTest: appModel.canTestSelectedRouter,
            onSelect: { onSelectController($0.profile) },
            onAddController: onAddController,
            onManageControllers: onManageControllers,
            onTestController: appModel.testSelectedRouter
        )
    }
}

private struct WorkbenchControllerSelector: View {
    @Environment(\.micaAppLanguage) private var language
    @State private var isHovered = false

    let snapshot: WorkbenchControllerSelectorSnapshot
    let isEnabled: Bool
    let canTest: Bool
    let onSelect: (WorkbenchControllerSelectorItem) -> Void
    let onAddController: () -> Void
    let onManageControllers: () -> Void
    let onTestController: () -> Void

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MicaTheme.Metrics.moduleRadius, style: .continuous)
    }

    var body: some View {
        Menu {
            if !snapshot.items.isEmpty {
                Section {
                    ForEach(snapshot.items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            Label(
                                "\(item.displayName) (\(item.compactEndpoint))",
                                systemImage: item.id == snapshot.selectedID
                                    ? "checkmark"
                                    : item.symbolName
                            )
                        }
                        .disabled(!isEnabled)
                        .help(item.endpointURL)
                        .accessibilityValue(Text(verbatim: item.endpointURL))
                        .accessibilityAddTraits(
                            item.id == snapshot.selectedID ? .isSelected : []
                        )
                    }
                }
            }

            Section {
                Button(action: onAddController) {
                    Label(
                        localized("sidebar.add_controller"),
                        systemImage: "plus"
                    )
                }
                Button(action: onManageControllers) {
                    Label(
                        localized("sidebar.controllers"),
                        systemImage: "server.rack"
                    )
                }
            }

            if snapshot.selectedItem != nil {
                Section {
                    Button(action: onTestController) {
                        Label(
                            localized("dashboard.help_test_controller"),
                            systemImage: MicaSymbols.Command.test
                        )
                    }
                    .disabled(!canTest)
                }
            }
        } label: {
            HStack(spacing: MicaTheme.Spacing.space2) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: snapshot.selectedItem?.symbolName ?? "server.rack")
                        .symbolRenderingMode(.monochrome)
                        .micaThemeFont(.body, weight: .medium)
                        .foregroundStyle(MicaTheme.accent)
                        .frame(width: 28, height: 28)
                        .background(
                            MicaTheme.accent.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )

                    WorkbenchControllerStatusDot()
                        .offset(x: 2, y: 2)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: controllerName)
                        .micaThemeFont(.body, weight: .semibold)
                        .foregroundStyle(MicaTheme.textPrimary)
                        .lineLimit(1)

                    Text(
                        verbatim: snapshot.selectedItem?.compactEndpoint
                            ?? localized("sidebar.add_controller")
                    )
                    .micaThemeFont(.caption)
                    .foregroundStyle(MicaTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }

                Spacer(minLength: MicaTheme.Spacing.space1)

                Image(systemName: "chevron.up.chevron.down")
                    .micaThemeFont(.caption, weight: .semibold)
                    .foregroundStyle(MicaTheme.textSecondary)
            }
            .padding(.horizontal, MicaTheme.Spacing.space2)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(isHovered ? MicaTheme.surfaceHover : MicaTheme.surface, in: cardShape)
            .overlay {
                cardShape.strokeBorder(
                    isHovered ? MicaTheme.surfaceBorderStrong : MicaTheme.surfaceBorder,
                    lineWidth: 1
                )
            }
            .contentShape(cardShape)
            .opacity(isEnabled ? 1 : 0.72)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { isHovered = $0 }
        .micaStateChangeAnimation(MicaTheme.Motion.press, value: isHovered)
        .accessibilityLabel(Text(localized("settings.active_controller")))
        .accessibilityValue(Text(verbatim: controllerName))
        .help(snapshot.selectedItem?.endpointURL ?? localized("sidebar.controllers"))
    }

    private var controllerName: String {
        snapshot.selectedItem?.displayName ?? localized("settings.none")
    }

    private func localized(_ key: String) -> String {
        MicaStrings.localizedKey(key, language: language)
    }
}

private struct WorkbenchControllerStatusDot: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if appModel.selectedRouter != nil {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .overlay {
                    Circle().stroke(MicaTheme.surface, lineWidth: 1.5)
                }
        }
    }

    private var statusColor: Color {
        switch appModel.controllerSessionPresentation.state {
        case .live:
            MicaTheme.statusOK
        case .connecting, .staleReconnecting, .partial:
            MicaTheme.statusWarning
        case .failed, .failedBeforeFirstSnapshot:
            MicaTheme.statusError
        case .idle, .stopped:
            MicaTheme.textTertiary
        }
    }
}
