import SwiftUI

extension RouterEditorView {
    func handshakeRow(
        _ title: String,
        value: String,
        state: ConnectionCheckState
    ) -> some View {
        LabeledContent {
            Text(verbatim: value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        } label: {
            Label(title, systemImage: state.iconName)
                .foregroundStyle(state.tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}
