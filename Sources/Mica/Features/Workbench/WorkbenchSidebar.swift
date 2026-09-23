import MicaCore
import SwiftUI

struct WorkbenchSidebarView: View {
    @Environment(\.micaAppLanguage) private var language

    @Binding var destination: WorkbenchDestination

    let isControllerSwitchingEnabled: Bool
    let onSelectController: (RouterProfile) -> Void
    let onAddController: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WorkbenchSidebarControllerSwitcher(
                isEnabled: isControllerSwitchingEnabled,
                onSelectController: onSelectController,
                onAddController: onAddController,
                onManageControllers: { destination = .controllers }
            )
            .padding(.horizontal, MicaTheme.Spacing.space3)
            .padding(.vertical, MicaTheme.Spacing.space2)

            List(selection: selection) {
                ForEach(WorkbenchDestination.Group.allCases) { group in
                    Section {
                        ForEach(group.destinations) { item in
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
                            .padding(.vertical, 2)
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
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .tint(MicaTheme.accent)
        .navigationTitle("Mica")
    }

    private var selection: Binding<WorkbenchDestination?> {
        Binding(
            get: { destination },
            set: { next in
                guard let next, next != destination else { return }
                destination = next
            }
        )
    }
}
