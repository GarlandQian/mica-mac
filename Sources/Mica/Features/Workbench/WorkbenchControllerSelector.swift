import MicaCore
import SwiftUI

struct WorkbenchControllerSelectorItem: Identifiable, Equatable, Sendable {
    let id: RouterProfile.ID
    let profile: RouterProfile
    let displayName: String
    let endpointURL: String
    let symbolName: String

    init(profile: RouterProfile) {
        id = profile.id
        self.profile = profile
        displayName = profile.displayName
        endpointURL = profile.endpointURL
        symbolName = profile.controllerKind.editorSymbol
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

    let snapshot: WorkbenchControllerSelectorSnapshot
    let isEnabled: Bool
    let canTest: Bool
    let onSelect: (WorkbenchControllerSelectorItem) -> Void
    let onAddController: () -> Void
    let onManageControllers: () -> Void
    let onTestController: () -> Void

    var body: some View {
        Menu {
            Section {
                ForEach(snapshot.items) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        Label(
                            "\(item.displayName) (\(item.endpointURL))",
                            systemImage: item.id == snapshot.selectedID
                                ? "checkmark"
                                : item.symbolName
                        )
                    }
                    .help(item.endpointURL)
                    .accessibilityValue(Text(verbatim: item.endpointURL))
                    .accessibilityAddTraits(
                        item.id == snapshot.selectedID ? .isSelected : []
                    )
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
                Image(systemName: snapshot.selectedItem?.symbolName ?? "server.rack")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(MicaTheme.textSecondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: controllerName)
                        .micaThemeFont(.body, weight: .semibold)
                        .foregroundStyle(MicaTheme.textPrimary)
                        .lineLimit(1)

                    Text(verbatim: snapshot.selectedItem?.endpointURL
                        ?? localized("sidebar.add_controller"))
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
            .padding(.vertical, MicaTheme.Spacing.space2)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(!isEnabled)
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
