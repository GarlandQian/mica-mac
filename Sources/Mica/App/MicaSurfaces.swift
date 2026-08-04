import SwiftUI

/// Status labels keep controller state readable in both appearances: the
/// project palette identifies the symbol while semantic text supplies the
/// required contrast. Meaning is therefore never carried by color alone.
struct MicaStatusLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            configuration.icon
                .foregroundStyle(tint)
            configuration.title
                .foregroundStyle(.primary)
        }
    }
}
