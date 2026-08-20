import MicaCore
import SwiftUI

// MARK: - Sidebar

struct WorkbenchSidebarView: View {
    @Environment(\.micaAppLanguage) private var language
    @FocusState private var focusedDestination: WorkbenchDestination?

    @Binding var destination: WorkbenchDestination

    let isControllerSwitchingEnabled: Bool
    let onSelectController: (RouterProfile) -> Void
    let onAddController: () -> Void

    var body: some View {
        List {
            Section {
                WorkbenchSidebarControllerSwitcher(
                    isEnabled: isControllerSwitchingEnabled,
                    onSelectController: onSelectController,
                    onAddController: onAddController,
                    onManageControllers: {
                        destination = .controllers
                    }
                )
            }
            .listRowInsets(
                EdgeInsets(
                    top: MicaTheme.Spacing.space1,
                    leading: MicaTheme.Spacing.space2,
                    bottom: MicaTheme.Spacing.space1,
                    trailing: MicaTheme.Spacing.space2
                )
            )
            .listRowBackground(Color.clear)

            destinationSection(.operate, destinations: WorkbenchDestination.operateCases)
            destinationSection(.observe, destinations: WorkbenchDestination.observeCases)
            destinationSection(.manage, destinations: WorkbenchDestination.manageCases)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .tint(MicaTheme.accent)
        .navigationTitle("Mica")
    }

    private func destinationSection(
        _ group: WorkbenchDestination.Group,
        destinations: [WorkbenchDestination]
    ) -> some View {
        Section {
            ForEach(destinations) { item in
                WorkbenchSidebarRow(
                    destination: item,
                    isSelected: item == destination,
                    focusedDestination: $focusedDestination,
                    action: {
                        destination = item
                        if destination == item {
                            focusedDestination = item
                        }
                    },
                    onMove: { direction in
                        moveDestination(from: item, direction: direction)
                    }
                )
                .listRowInsets(
                    EdgeInsets()
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        } header: {
            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                MicaHairlineSeparator()

                Text(
                    MicaStrings.localizedKey(
                        group.titleKey,
                        language: language
                    )
                )
                .micaThemeFont(.caption, weight: .semibold)
                .foregroundStyle(MicaTheme.textSecondary)
                .padding(.leading, MicaTheme.Spacing.space2)
            }
        }
    }

    private func moveDestination(
        from current: WorkbenchDestination,
        direction: MoveCommandDirection
    ) {
        let offset: Int
        switch direction {
        case .up:
            offset = -1
        case .down:
            offset = 1
        case .left, .right:
            return
        @unknown default:
            return
        }

        guard let currentIndex = WorkbenchDestination.sidebarCases.firstIndex(of: current) else {
            return
        }

        let nextIndex = currentIndex + offset
        guard WorkbenchDestination.sidebarCases.indices.contains(nextIndex) else {
            return
        }

        let next = WorkbenchDestination.sidebarCases[nextIndex]
        destination = next
        if destination == next {
            focusedDestination = next
        }
    }
}

private struct WorkbenchSidebarRow: View {
    @Environment(\.micaAppLanguage) private var language

    let destination: WorkbenchDestination
    let isSelected: Bool
    let focusedDestination: FocusState<WorkbenchDestination?>.Binding
    let action: () -> Void
    let onMove: (MoveCommandDirection) -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MicaTheme.Spacing.space2) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(isSelected ? MicaTheme.accent : .clear)
                    .frame(width: 3, height: 18)
                    .accessibilityHidden(true)

                Image(systemName: destination.symbolName)
                    .foregroundStyle(isSelected ? MicaTheme.accent : MicaTheme.textSecondary)
                    .symbolRenderingMode(.monochrome)
                    .symbolVariant(isSelected ? .fill : .none)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                Text(
                    MicaStrings.localizedKey(
                        destination.titleKey,
                        language: language
                    )
                )
                .micaThemeFont(.label)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(MicaTheme.textPrimary)
                .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.leading, MicaTheme.Spacing.space1)
            .padding(.trailing, MicaTheme.Spacing.space2)
            .padding(.vertical, MicaTheme.Spacing.space1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(
                        cornerRadius: MicaTheme.Shape.panelRadius,
                        style: .continuous
                    )
                    .fill(MicaTheme.accent.opacity(0.14))
                }
            }
            .contentShape(.interaction, Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.interaction, Rectangle())
        .focused(focusedDestination, equals: destination)
        .onMoveCommand(perform: onMove)
        .help(
            MicaStrings.localizedKey(
                destination.titleKey,
                language: language
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
