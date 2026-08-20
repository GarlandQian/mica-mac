import SwiftUI

extension RouterEditorView {
    func handshakeRow(
        _ title: String,
        value: String,
        state: ConnectionCheckState
    ) -> some View {
        RouterEditorHandshakeRow(title: title, value: value, state: state)
    }
}

private struct RouterEditorHandshakeRow: View {
    @Environment(\.workbenchManagementWidthMode) private var widthMode

    let title: String
    let value: String
    let state: ConnectionCheckState

    var body: some View {
        Group {
            if widthMode == .compact {
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                    label
                    valueLabel
                }
            } else {
                HStack(alignment: .top, spacing: MicaTheme.Spacing.space3) {
                    label
                        .frame(width: MicaTheme.Metrics.formLabelWidth, alignment: .leading)
                    valueLabel
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private var label: some View {
        Label(title, systemImage: state.iconName)
            .micaThemeFont(.label, weight: .medium)
            .labelStyle(MicaStatusLabelStyle(tint: state.tint))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueLabel: some View {
        Text(verbatim: value)
            .micaThemeFont(.label)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
