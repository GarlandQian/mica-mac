import SwiftUI

/// A bounded reading workspace. Selection is local to this snapshot; opening a
/// live connection is available only while the captured structure still matches.
struct OverviewTopologyFocusedPathsView: View {
    let focus: OverviewTopologyPathFocus
    let language: AppLanguage
    let canNavigate: Bool
    let onOpenPath: (ConnectionTopology.PathRecord) -> Void
    let onReturn: () -> Void

    @State private var selectedPathID: ConnectionTopology.ConnectionOccurrenceID?

    private var selectedPath: ConnectionTopology.PathRecord? {
        focus.paths.first { $0.id == selectedPathID } ?? focus.paths.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            HStack(spacing: MicaTheme.Spacing.space2) {
                Text(verbatim: focus.title)
                    .micaThemeFont(.label, weight: .semibold)
                    .lineLimit(1)
                Text(verbatim: focus.paths.count.formatted())
                    .micaThemeFont(.dataLabel)
                    .foregroundStyle(MicaTheme.textSecondary)
                Spacer(minLength: 0)
                Label(
                    MicaStrings.localizedKey("overview.topology_snapshot", language: language),
                    systemImage: "pause.circle"
                )
                .micaThemeFont(.caption)
                .foregroundStyle(MicaTheme.textSecondary)
            }
            .padding(.horizontal, MicaTheme.Spacing.space3)

            GeometryReader { geometry in
                if geometry.size.width >= 600 {
                    HStack(alignment: .top, spacing: 0) {
                        pathList
                            .frame(width: max(230, geometry.size.width * 0.42))
                        Divider()
                        pathDetail
                    }
                } else {
                    VStack(spacing: 0) {
                        pathList
                            .frame(height: max(112, geometry.size.height * 0.38))
                        Divider()
                        pathDetail
                    }
                }
            }
        }
        .padding(.top, MicaTheme.Spacing.space2)
        .background(MicaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: MicaTheme.Shape.panelRadius))
        .overlay {
            RoundedRectangle(cornerRadius: MicaTheme.Shape.panelRadius)
                .strokeBorder(MicaTheme.separator, lineWidth: MicaTheme.Shape.hairline)
        }
        .onExitCommand(perform: onReturn)
        .onAppear { selectedPathID = focus.paths.first?.id }
    }

    private var pathList: some View {
        List(focus.paths, selection: $selectedPathID) { path in
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "\(path.source ?? unknownSource) → \(path.finalOutbound ?? unknownOutbound)")
                    .micaThemeFont(.label)
                    .lineLimit(2)
                Text(verbatim: OverviewTopologyProjection.pathLabel(path, language: language))
                    .micaThemeFont(.dataCaption)
                    .foregroundStyle(MicaTheme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 3)
            .tag(path.id)
            .accessibilityElement(children: .combine)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityLabel(MicaStrings.localizedKey("overview.topology_related_paths", language: language))
    }

    private var pathDetail: some View {
        ScrollView {
            if let path = selectedPath {
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space3) {
                    HStack {
                        Text(MicaStrings.localizedKey("overview.topology_complete_path", language: language))
                            .micaThemeFont(.label, weight: .semibold)
                        Spacer(minLength: 0)
                        Button {
                            guard canNavigate else { return }
                            onOpenPath(path)
                        } label: {
                            Label(MicaStrings.localizedKey("overview.topology_open_connection", language: language), systemImage: "arrow.up.right")
                        }
                        .buttonStyle(.borderless)
                        .disabled(!canNavigate)
                    }
                    if !canNavigate {
                        Text(MicaStrings.localizedKey("overview.topology_snapshot_changed", language: language))
                            .micaThemeFont(.caption)
                            .foregroundStyle(MicaTheme.textSecondary)
                    }
                    if path.source == nil {
                        stageRow(title: MicaStrings.localizedKey("overview.topology_source", language: language), value: unknownSource, symbol: "questionmark.circle")
                    }
                    ForEach(Array(path.stages.enumerated()), id: \.offset) { _, stage in
                        stageRow(
                            title: OverviewTopologyProjection.columnTitle(stage.columnID, language: language),
                            value: stage.name,
                            symbol: stage.columnID == .source ? "network" : stage.columnID == .finalOutbound ? "arrow.up.right" : "arrow.turn.down.right"
                        )
                    }
                    if path.finalOutbound == nil {
                        stageRow(title: MicaStrings.localizedKey("overview.topology_exit", language: language), value: unknownOutbound, symbol: "questionmark.circle")
                    }
                }
                .padding(MicaTheme.Spacing.space3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func stageRow(title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: MicaTheme.Spacing.space2) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(MicaTheme.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .micaThemeFont(.caption)
                    .foregroundStyle(MicaTheme.textSecondary)
                Text(verbatim: value)
                    .micaThemeFont(.label)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var unknownSource: String {
        MicaStrings.localizedKey("overview.topology_unknown_source", language: language)
    }

    private var unknownOutbound: String {
        MicaStrings.localizedKey("overview.topology_unknown_outbound", language: language)
    }
}
