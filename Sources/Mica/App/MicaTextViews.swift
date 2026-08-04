import SwiftUI

struct MicaText: View {
    @Environment(\.micaAppLanguage) private var appLanguage
    var key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(verbatim: MicaStrings.localizedKey(key, language: appLanguage))
    }
}

struct MicaLabel: View {
    @Environment(\.micaAppLanguage) private var appLanguage
    var key: String
    var systemImage: String

    init(_ key: String, systemImage: String) {
        self.key = key
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(verbatim: MicaStrings.localizedKey(key, language: appLanguage))
        } icon: {
            Image(systemName: systemImage)
        }
    }
}
