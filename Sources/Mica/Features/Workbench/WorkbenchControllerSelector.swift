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
        let items = profiles.map(WorkbenchControllerSelectorItem.init(profile:))
        self.items = items
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
        let snapshot = WorkbenchControllerSelectorSnapshot(
            profiles: appModel.routers,
            selectedID: appModel.selectedRouterID
        )

        WorkbenchControllerSelector(
            snapshot: snapshot,
            isEnabled: isEnabled,
            onSelect: select,
            onAddController: onAddController,
            onManageControllers: onManageControllers
        )
    }

    private func select(_ item: WorkbenchControllerSelectorItem) {
        onSelectController(item.profile)
    }
}

private struct WorkbenchControllerSelector: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    let snapshot: WorkbenchControllerSelectorSnapshot
    let isEnabled: Bool
    let onSelect: (WorkbenchControllerSelectorItem) -> Void
    let onAddController: () -> Void
    let onManageControllers: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : MicaTheme.Motion.reveal) {
                    isExpanded.toggle()
                }
            } label: {
                currentControllerLabel(
                    snapshot.selectedItem,
                    isExpanded: isExpanded
                )
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)

            if isExpanded {
                switcherContents
                    .padding(.top, MicaTheme.Spacing.space1)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .tint(MicaTheme.accent)
        .accessibilityLabel(
            Text(
                MicaStrings.localizedKey(
                    "settings.active_controller",
                    language: language
                )
            )
        )
        .accessibilityValue(
            Text(
                verbatim: selectedControllerAccessibilityValue(
                    snapshot.selectedItem
                )
            )
        )
        .help(selectedControllerHelp(snapshot.selectedItem))
        .onChange(of: isEnabled) { _, isEnabled in
            if !isEnabled {
                isExpanded = false
            }
        }
    }

    private var switcherContents: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if snapshot.items.isEmpty {
                Text(
                    MicaStrings.localizedKey(
                        "settings.none",
                        language: language
                    )
                )
                .micaThemeFont(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, MicaTheme.Spacing.space2)
                .frame(
                    maxWidth: .infinity,
                    minHeight: MicaTheme.Metrics.controlMinHeight,
                    alignment: .leading
                )
            } else {
                ForEach(snapshot.items) { item in
                    controllerButton(
                        item,
                        isSelected: item.id == snapshot.selectedID
                    )
                }
            }

            Divider()
                .padding(.vertical, MicaTheme.Spacing.space1)

            switcherAction(
                titleKey: "sidebar.add_controller",
                systemImage: "plus"
            ) {
                isExpanded = false
                onAddController()
            }

            switcherAction(
                titleKey: "sidebar.controllers",
                systemImage: "server.rack"
            ) {
                isExpanded = false
                onManageControllers()
            }
        }
    }

    private func currentControllerLabel(
        _ selectedItem: WorkbenchControllerSelectorItem?,
        isExpanded: Bool
    ) -> some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            Image(systemName: selectedControllerSymbol(selectedItem))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(selectedControllerTint(selectedItem))
                .frame(width: 18)
                .accessibilityHidden(true)

            Text(verbatim: selectedControllerName(selectedItem))
                .micaThemeFont(.label, weight: .semibold)
                .foregroundStyle(selectedItem == nil ? .secondary : .primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .micaThemeFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, MicaTheme.Spacing.space2)
        .frame(
            maxWidth: .infinity,
            minHeight: 36,
            alignment: .leading
        )
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(MicaTheme.accent.opacity(0.14).opacity(0.55))
        )
        .contentShape(Rectangle())
    }

    private func controllerButton(
        _ item: WorkbenchControllerSelectorItem,
        isSelected: Bool
    ) -> some View {
        Button {
            isExpanded = false
            onSelect(item)
        } label: {
            HStack(alignment: .center, spacing: MicaTheme.Spacing.space2) {
                Image(
                    systemName: isSelected
                        ? "checkmark.circle.fill"
                        : item.symbolName
                )
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isSelected ? MicaTheme.accent : .secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.displayName)
                        .micaThemeFont(.label)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(verbatim: item.endpointURL)
                        .micaThemeFont(.dataCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, MicaTheme.Spacing.space2)
            .padding(.vertical, MicaTheme.Spacing.space1)
            .frame(
                maxWidth: .infinity,
                minHeight: MicaTheme.Metrics.controlMinHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(
                        cornerRadius: MicaTheme.Metrics.badgeRadius,
                        style: .continuous
                    )
                    .fill(MicaTheme.accent.opacity(0.14))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: item.displayName))
        .accessibilityValue(
            Text(verbatim: controllerAccessibilityValue(item, isSelected: isSelected))
        )
        .help(item.endpointURL)
    }

    private func switcherAction(
        titleKey: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        let title = MicaStrings.localizedKey(titleKey, language: language)

        return Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: MicaTheme.Metrics.controlMinHeight,
                alignment: .leading
            )
            .padding(.horizontal, MicaTheme.Spacing.space2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(Text(title))
    }

    private func selectedControllerName(
        _ selectedItem: WorkbenchControllerSelectorItem?
    ) -> String {
        selectedItem?.displayName
            ?? MicaStrings.localizedKey("settings.none", language: language)
    }

    private func selectedControllerSymbol(
        _ selectedItem: WorkbenchControllerSelectorItem?
    ) -> String {
        selectedItem?.symbolName ?? "server.rack"
    }

    private func selectedControllerTint(
        _ selectedItem: WorkbenchControllerSelectorItem?
    ) -> Color {
        selectedItem == nil ? .secondary : MicaTheme.accent
    }

    private func selectedControllerHelp(
        _ selectedItem: WorkbenchControllerSelectorItem?
    ) -> String {
        selectedItem?.endpointURL
            ?? MicaStrings.localizedKey("sidebar.controllers", language: language)
    }

    private func selectedControllerAccessibilityValue(
        _ selectedItem: WorkbenchControllerSelectorItem?
    ) -> String {
        guard let endpoint = selectedItem?.endpointURL else {
            return selectedControllerName(selectedItem)
        }

        return [selectedControllerName(selectedItem), endpoint]
            .joined(separator: "\n")
    }

    private func controllerAccessibilityValue(
        _ item: WorkbenchControllerSelectorItem,
        isSelected: Bool
    ) -> String {
        guard isSelected else { return item.endpointURL }

        return [
            MicaStrings.localizedKey("settings.active_controller", language: language),
            item.endpointURL,
        ]
        .joined(separator: "\n")
    }
}
