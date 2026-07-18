import SwiftUI

struct WorkbenchSidebarView: View {
    @Environment(\.micaAppLanguage) private var appLanguage

    @Binding var destination: WorkbenchDestination

    var body: some View {
        List(selection: $destination) {
            ForEach(WorkbenchDestination.Group.allCases) { group in
                Section {
                    ForEach(WorkbenchDestination.allCases.filter { $0.group == group }) { item in
                        Label(MicaStrings.localizedKey(item.titleKey, language: appLanguage), systemImage: item.symbolName)
                            .tag(item)
                            .accessibilityLabel(MicaStrings.localizedKey(item.titleKey, language: appLanguage))
                    }
                } header: {
                    MicaText(group.titleKey)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Mica")
        .accessibilityLabel("Mica")
    }
}
