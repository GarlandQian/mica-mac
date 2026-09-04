import Foundation
import MicaCore
import SwiftUI

// MARK: - Shared data-page views

extension View {
    func micaWorkbenchTable(accessibilityLabel: String) -> some View {
        tableStyle(.bordered(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
            .background(MicaTheme.canvas)
            .tint(MicaTheme.accent)
            .environment(\.defaultMinListRowHeight, WorkbenchDataRowGeometry.height)
            .accessibilityLabel(accessibilityLabel)
    }
}

/// Owns bounded table semantics without exposing the native `NSTableView`
/// accessibility subtree or participating in pointer interaction.
struct WorkbenchTableAccessibilityHost: View, @MainActor Equatable {
    let payload: WorkbenchTableAccessibilityPayload
    let dispatch: (WorkbenchTableAccessibilityIntent) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.payload == rhs.payload
    }

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityRepresentation {
                WorkbenchResolvedTableAccessibilityRepresentation(
                    payload: payload,
                    dispatch: dispatch
                )
            }
    }
}

struct WorkbenchAccessibilityPageControls: View {
    @Environment(\.micaAppLanguage) private var language

    let window: WorkbenchAccessibilityWindow
    let moveToLowerBound: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
            Text(pageLabel)
            Text(rangeLabel)

            HStack {
                if let previousLowerBound = window.previousLowerBound {
                    Button(
                        MicaStrings.localizedKey("traffic.previous_page", language: language)
                    ) {
                        moveToLowerBound(previousLowerBound)
                    }
                }

                if let nextLowerBound = window.nextLowerBound {
                    Button(
                        MicaStrings.localizedKey("traffic.next_page", language: language)
                    ) {
                        moveToLowerBound(nextLowerBound)
                    }
                }
            }
        }
    }

    private var pageLabel: String {
        MicaStrings.localized(
            "traffic.page_label \(window.pageNumber) \(window.pageCount) \(window.totalCount)",
            language: language
        )
    }

    private var rangeLabel: String {
        let first = window.range.isEmpty ? 0 : window.lowerBound + 1
        return MicaStrings.localized(
            "traffic.range_label \(first) \(window.upperBound) \(window.totalCount)",
            language: language
        )
    }
}

private struct WorkbenchResolvedTableAccessibilityRepresentation: View {
    let payload: WorkbenchTableAccessibilityPayload
    let dispatch: (WorkbenchTableAccessibilityIntent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            WorkbenchResolvedTableAccessibilityPageControls(
                payload: payload,
                dispatch: dispatch
            )

            if !payload.sortControls.isEmpty {
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
                    ForEach(payload.sortControls) { control in
                        Button {
                            dispatch(
                                .setSort(
                                    id: control.id,
                                    ascending: control.targetAscending,
                                    scope: payload.scope
                                )
                            )
                        } label: {
                            Text(verbatim: control.title)
                        }
                        .accessibilityValue(Text(verbatim: control.value ?? ""))
                        .accessibilityHint(Text(verbatim: control.hint))
                        .accessibilityAddTraits(control.isSelected ? .isSelected : [])
                    }
                }
            }

            ForEach(payload.rows) { row in
                accessibleRow(row)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: payload.title))
    }

    @ViewBuilder
    private func accessibleRow(_ row: WorkbenchTableAccessibilityPayload.Row) -> some View {
        let rowButton = Button {
            dispatch(.selectRow(id: row.id, scope: payload.scope))
        } label: {
            Text(verbatim: row.summary)
        }
        .accessibilityAddTraits(row.isSelected ? .isSelected : [])

        if let action = row.namedAction {
            rowButton.accessibilityAction(named: Text(verbatim: action.title)) {
                dispatch(
                    .performNamedAction(
                        rowID: row.id,
                        actionID: action.id,
                        scope: payload.scope
                    )
                )
            }
        } else {
            rowButton
        }
    }
}

private struct WorkbenchResolvedTableAccessibilityPageControls: View {
    let payload: WorkbenchTableAccessibilityPayload
    let dispatch: (WorkbenchTableAccessibilityIntent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
            Text(verbatim: payload.pageLabel)
            Text(verbatim: payload.rangeLabel)

            HStack {
                if let previousPage = payload.previousPage {
                    pageButton(previousPage)
                }

                if let nextPage = payload.nextPage {
                    pageButton(nextPage)
                }
            }
        }
    }

    private func pageButton(
        _ action: WorkbenchTableAccessibilityPayload.PageAction
    ) -> some View {
        Button {
            dispatch(
                .movePage(
                    lowerBound: action.lowerBound,
                    scope: payload.scope
                )
            )
        } label: {
            Text(verbatim: action.title)
        }
    }
}

struct WorkbenchDataActivityIndicator: View {
    @Environment(\.micaAppLanguage) private var language

    let isActive: Bool
    let titleKey: String

    var body: some View {
        Group {
            if isActive {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(
                        MicaStrings.localizedKey(titleKey, language: language)
                    )
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        }
        .frame(
            width: MicaTheme.Metrics.iconControlSize,
            height: MicaTheme.Metrics.controlMinHeight
        )
    }
}

struct WorkbenchDataBrowserScaffold<Commands: View, Supplementary: View, Content: View>: View {
    let staleMessage: String?
    private let commands: Commands
    private let supplementary: Supplementary
    private let content: Content

    init(
        staleMessage: String?,
        @ViewBuilder commands: () -> Commands,
        @ViewBuilder supplementary: () -> Supplementary,
        @ViewBuilder content: () -> Content
    ) {
        self.staleMessage = staleMessage
        self.commands = commands()
        self.supplementary = supplementary()
        self.content = content()
    }

    var body: some View {
        WorkbenchPageScaffold {
            VStack(spacing: 0) {
                commands

                if let staleMessage {
                    WorkbenchStaleNotice(message: staleMessage)
                }

                supplementary
            }
        } content: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MicaTheme.canvas)
        }
    }
}

struct WorkbenchDataPrimaryCell: View {
    let title: String
    var detail: String?
    let systemImage: String
    var tint: Color = .secondary
    var titleIsMonospaced = false
    var detailIsMonospaced = true

    var body: some View {
        HStack(alignment: .center, spacing: MicaTheme.Spacing.space2) {
            Image(systemName: systemImage)
                .micaThemeFont(.caption, weight: .semibold)
                .foregroundStyle(tint)
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                    .micaThemeFont(
                        titleIsMonospaced ? .dataLabel : .label,
                        weight: .semibold
                    )
                    .lineLimit(1)
                    .textSelection(.enabled)

                if let detail = detail?.dataNonEmpty {
                    Text(verbatim: detail)
                        .micaThemeFont(detailIsMonospaced ? .dataCaption : .caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: WorkbenchDataRowGeometry.height,
            maxHeight: WorkbenchDataRowGeometry.height,
            alignment: .leading
        )
        .accessibilityElement(children: .combine)
    }
}

struct WorkbenchDataText: View {
    let value: String
    var role: MicaTheme.TextRole = .label
    var weight: Font.Weight?
    var tone: HierarchicalShapeStyle = .primary
    var alignment: Alignment = .leading
    var maximumLineCount = 1

    var body: some View {
        Text(verbatim: value)
            .micaThemeFont(role, weight: weight)
            .foregroundStyle(tone)
            .lineLimit(maximumLineCount)
            .truncationMode(.tail)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}

struct WorkbenchDataMetric: View {
    let value: String
    var tone: HierarchicalShapeStyle = .primary

    var body: some View {
        WorkbenchDataText(
            value: value,
            role: .dataCaption,
            tone: tone,
            alignment: .trailing
        )
        .monospacedDigit()
    }
}

struct WorkbenchDataInlineConfirmation: View {
    @Environment(\.micaAppLanguage) private var language

    let message: String
    let confirmTitleKey: String
    let isConfirmEnabled: Bool
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MicaTheme.Spacing.space3) { confirmationContent }
            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) { confirmationContent }
        }
        .padding(.horizontal, MicaTheme.Metrics.chromeHorizontalPadding)
        .padding(.vertical, MicaTheme.Spacing.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaTheme.statusError.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
        .onExitCommand(perform: cancel)
    }

    @ViewBuilder
    private var confirmationContent: some View {
        Label {
            Text(verbatim: message)
                .micaThemeFont(.label)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MicaTheme.statusError)
        }

        Spacer(minLength: MicaTheme.Spacing.space2)

        Button(MicaStrings.localizedKey("action.cancel", language: language), action: cancel)
            .frame(minHeight: MicaTheme.Metrics.controlMinHeight)

        Button(
            MicaStrings.localizedKey(confirmTitleKey, language: language),
            role: .destructive,
            action: confirm
        )
        .buttonStyle(.borderedProminent)
        .tint(MicaTheme.statusError)
        .disabled(!isConfirmEnabled)
        .frame(minHeight: MicaTheme.Metrics.controlMinHeight)
    }
}

struct WorkbenchDataInspectorShell<Content: View>: View {
    @Environment(\.micaAppLanguage) private var language

    let title: String
    var subtitle: String?
    var statusText: String?
    var statusTint: Color = .secondary
    let close: () -> Void
    private let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        statusText: String? = nil,
        statusTint: Color = .secondary,
        close: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.statusText = statusText
        self.statusTint = statusTint
        self.close = close
        self.content = content()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MicaTheme.Spacing.space4) {
                HStack(alignment: .top, spacing: MicaTheme.Spacing.space2) {
                    VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
                        Text(verbatim: title)
                            .micaThemeFont(.title3)
                            .textSelection(.enabled)

                        if let subtitle = subtitle?.dataNonEmpty {
                            Text(verbatim: subtitle)
                                .micaThemeFont(.dataCaption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        if let statusText = statusText?.dataNonEmpty {
                            WorkbenchStatusBadge(text: statusText, tint: statusTint)
                        }
                    }

                    Spacer(minLength: MicaTheme.Spacing.space2)

                    Button(action: close) {
                        Image(systemName: "xmark")
                            .accessibilityHidden(true)
                    }
                    .buttonStyle(.borderless)
                    .frame(
                        minWidth: MicaTheme.Metrics.iconControlSize,
                        minHeight: MicaTheme.Metrics.iconControlSize
                    )
                    .accessibilityLabel(
                        MicaStrings.localizedKey("dashboard.close_inspector", language: language)
                    )
                }

                content
            }
            .padding(MicaTheme.Spacing.space4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .micaObserveScrollPerformance()
        .background(MicaTheme.surfaceRaised)
    }
}

struct WorkbenchDataInspectorSection<Content: View>: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    private let content: Content

    init(_ titleKey: String, @ViewBuilder content: () -> Content) {
        self.titleKey = titleKey
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
            Text(MicaStrings.localizedKey(titleKey, language: language))
                .micaThemeFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)
            Divider()
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkbenchDataInspectorField: View {
    @Environment(\.micaAppLanguage) private var language

    let titleKey: String
    let value: String?
    var monospaced = false

    var body: some View {
        HStack(alignment: .top, spacing: MicaTheme.Spacing.space3) {
            Text(MicaStrings.localizedKey(titleKey, language: language))
                .micaThemeFont(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)

            Text(
                verbatim: value?.dataNonEmpty
                    ?? MicaStrings.localizedKey("overview.config_not_reported", language: language)
            )
            .micaThemeFont(monospaced ? .dataLabel : .label)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkbenchDataInspectorValueList: View {
    let values: [WorkbenchDataInspectorValue]

    var body: some View {
        ForEach(values) { item in
            WorkbenchDataInspectorField(
                titleKey: item.titleKey,
                value: item.value,
                monospaced: item.monospaced
            )
        }
    }
}
