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
                    top: MicaSpacing.tight,
                    leading: MicaSpacing.row,
                    bottom: MicaSpacing.tight,
                    trailing: MicaSpacing.row
                )
            )
            .listRowBackground(Color.clear)

            destinationSection(.workbench, destinations: WorkbenchDestination.workbenchTabCases)
            destinationSection(
                .controllerManagement,
                destinations: WorkbenchDestination.controllerManagementCases
            )
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .tint(MicaStyle.accent)
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
            Text(
                MicaStrings.localizedKey(
                    group.titleKey,
                    language: language
                )
            )
            .micaFont(.caption2, weight: .medium)
            .foregroundStyle(.secondary)
            .padding(.leading, MicaSpacing.row)
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
            HStack(spacing: MicaSpacing.row) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(isSelected ? MicaStyle.accent : .clear)
                    .frame(width: 3, height: 18)
                    .accessibilityHidden(true)

                Image(systemName: destination.symbolName)
                    .foregroundStyle(isSelected ? MicaStyle.accent : .secondary)
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
                .micaFont(.callout)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(.primary)
                .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.leading, MicaSpacing.tight)
            .padding(.trailing, MicaSpacing.space2)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(
                        cornerRadius: 6,
                        style: .continuous
                    )
                    .fill(MicaStyle.navigationSelectionFill)
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
