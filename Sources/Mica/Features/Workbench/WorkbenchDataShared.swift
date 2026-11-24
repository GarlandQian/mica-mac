import AppKit
import Foundation
import MicaCore
import SwiftUI

// MARK: - Shared data-page views

extension View {
    func micaWorkbenchTable(accessibilityLabel: String, lines: Int = 2) -> some View {
        modifier(WorkbenchTableStyleModifier(accessibilityLabel: accessibilityLabel, lines: lines))
    }
}

private struct WorkbenchTableStyleModifier: ViewModifier {
    @Environment(\.micaAppFontScale) private var fontScale

    let accessibilityLabel: String
    let lines: Int

    func body(content: Content) -> some View {
        // Inset rows with continuous selection capsules, as in macOS 27
        // content lists; the page fill stays continuous beneath the rows.
        content
            .tableStyle(.inset)
            .alternatingRowBackgrounds(.disabled)
            .scrollContentBackground(.hidden)
            .background(MicaTheme.canvas)
            .tint(MicaTheme.accent)
            .environment(
                \.defaultMinListRowHeight,
                WorkbenchDataRowGeometry.height(for: fontScale, lines: lines)
            )
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
        if isActive {
            ProgressView()
                .controlSize(.small)
                .frame(
                    width: MicaTheme.Metrics.iconControlSize,
                    height: MicaTheme.Metrics.controlMinHeight
                )
                .accessibilityLabel(
                    MicaStrings.localizedKey(titleKey, language: language)
                )
        }
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
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.micaAppFontScale) private var fontScale

    let title: String
    var detail: String?
    let systemImage: String?
    var tint: Color = .secondary
    var titleIsMonospaced = false
    var detailIsMonospaced = true

    var body: some View {
        HStack(alignment: .center, spacing: MicaTheme.Spacing.space2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .micaThemeFont(.caption, weight: .semibold)
                    .foregroundStyle(tint)
                    .frame(width: 16)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 1) {
                let isUnreported = title == MicaStrings.localizedKey(
                    "overview.config_not_reported",
                    language: language
                )
                Text(verbatim: isUnreported ? "—" : title)
                    .micaThemeFont(
                        titleIsMonospaced ? .dataLabel : .label,
                        weight: .semibold
                    )
                    .foregroundStyle(isUnreported ? .tertiary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(title)
                    .accessibilityLabel(Text(verbatim: title))

                if let detail = detail?.dataNonEmpty {
                    Text(verbatim: detail)
                        .micaThemeFont(detailIsMonospaced ? .dataCaption : .caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(detail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: WorkbenchDataRowGeometry.height(for: fontScale),
            alignment: .leading
        )
        .accessibilityElement(children: .combine)
    }
}

struct WorkbenchDataText: View {
    @Environment(\.micaAppLanguage) private var language

    let value: String
    var role: MicaTheme.TextRole = .label
    var weight: Font.Weight?
    var tone: HierarchicalShapeStyle = .primary
    var alignment: Alignment = .leading
    var maximumLineCount = 1

    var body: some View {
        // A scan table repeats the not-reported wording in every row; a quiet
        // dash keeps real values legible while help and VoiceOver still read
        // the complete localized state.
        let isUnreported = value == MicaStrings.localizedKey(
            "overview.config_not_reported",
            language: language
        )

        Text(verbatim: isUnreported ? "—" : value)
            .micaThemeFont(role, weight: weight)
            .foregroundStyle(isUnreported ? .tertiary : tone)
            .lineLimit(maximumLineCount)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: alignment)
            .help(value)
            .accessibilityLabel(Text(verbatim: value))
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
            HStack(spacing: MicaTheme.Spacing.space3) {
                messageLabel
                Spacer(minLength: MicaTheme.Spacing.space2)
                actionButtons
            }
            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                messageLabel
                HStack(spacing: MicaTheme.Spacing.space2) {
                    Spacer(minLength: 0)
                    actionButtons
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, MicaTheme.Metrics.chromeHorizontalPadding)
        .padding(.vertical, MicaTheme.Spacing.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaTheme.statusError.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
        .onExitCommand(perform: cancel)
    }

    private var messageLabel: some View {
        Label {
            Text(verbatim: message)
                .micaThemeFont(.label)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MicaTheme.statusError)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button(MicaStrings.localizedKey("action.cancel", language: language), action: cancel)
            .controlSize(.small)
            .frame(minHeight: MicaTheme.Metrics.controlMinHeight)

        Button(
            MicaStrings.localizedKey(confirmTitleKey, language: language),
            role: .destructive,
            action: confirm
        )
        .buttonStyle(.borderedProminent)
        .tint(MicaTheme.statusError)
        .controlSize(.small)
        .disabled(!isConfirmEnabled)
        .frame(minHeight: MicaTheme.Metrics.controlMinHeight)
    }
}

struct WorkbenchDataInspectorShell<Actions: View, Content: View>: View {
    @Environment(\.micaAppLanguage) private var language

    let title: String
    var subtitle: String?
    var statusText: String?
    var statusTint: Color = .secondary
    let close: () -> Void
    private let actions: Actions
    private let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        statusText: String? = nil,
        statusTint: Color = .secondary,
        close: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.statusText = statusText
        self.statusTint = statusTint
        self.close = close
        self.actions = actions()
        self.content = content()
    }

    init(
        title: String,
        subtitle: String? = nil,
        statusText: String? = nil,
        statusTint: Color = .secondary,
        close: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) where Actions == EmptyView {
        self.init(
            title: title,
            subtitle: subtitle,
            statusText: statusText,
            statusTint: statusTint,
            close: close,
            actions: { EmptyView() },
            content: content
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MicaTheme.Spacing.space3) {
                HStack(alignment: .top, spacing: MicaTheme.Spacing.space2) {
                    VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
                        Text(verbatim: title)
                            .micaThemeFont(.title3)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)

                        if let subtitle = subtitle?.dataNonEmpty {
                            Text(verbatim: subtitle)
                                .micaThemeFont(.dataCaption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }

                        if let statusText = statusText?.dataNonEmpty {
                            WorkbenchStatusBadge(text: statusText, tint: statusTint)
                        }
                    }

                    Spacer(minLength: MicaTheme.Spacing.space2)

                    Button(action: close) {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .buttonStyle(.borderless)
                    .frame(
                        minWidth: MicaTheme.Metrics.iconControlSize,
                        minHeight: MicaTheme.Metrics.iconControlSize
                    )
                    .help(
                        MicaStrings.localizedKey("dashboard.close_inspector", language: language)
                    )
                    .accessibilityLabel(
                        MicaStrings.localizedKey("dashboard.close_inspector", language: language)
                    )
                }

                actions

                content
            }
            .padding(MicaTheme.Spacing.space4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .micaObserveScrollPerformance()
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
                .micaThemeFont(.label, weight: .semibold)
                .foregroundStyle(MicaTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                content
            }
            .padding(MicaTheme.Spacing.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .micaCard(cornerRadius: MicaTheme.Shape.rowRadius)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkbenchDataInspectorField: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.micaAppFontScale) private var fontScale
    @State private var isHovered = false
    @State private var copiedRecently = false

    let titleKey: String
    let value: String?
    var monospaced = false

    var body: some View {
        let reported = value?.dataNonEmpty
        let labelWidth = min(148, max(96, ceil(108 * fontScale.multiplier)))

        HStack(alignment: .top, spacing: MicaTheme.Spacing.space2) {
            Text(MicaStrings.localizedKey(titleKey, language: language))
                .micaThemeFont(.caption)
                .foregroundStyle(MicaTheme.textSecondary)
                .frame(width: labelWidth, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: MicaTheme.Spacing.space1) {
                Text(
                    verbatim: reported
                        ?? MicaStrings.localizedKey("overview.config_not_reported", language: language)
                )
                .micaThemeFont(monospaced ? .dataLabel : .label)
                .foregroundStyle(reported == nil ? MicaTheme.textTertiary : MicaTheme.textPrimary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

                if let reported {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(reported, forType: .string)
                        copiedRecently = true
                    } label: {
                        Image(systemName: copiedRecently ? "checkmark" : "doc.on.doc")
                            .micaThemeFont(.caption)
                            .foregroundStyle(copiedRecently ? MicaTheme.statusOK : MicaTheme.textTertiary)
                    }
                    .buttonStyle(.borderless)
                    .opacity(isHovered || copiedRecently ? 1 : 0)
                    .allowsHitTesting(isHovered || copiedRecently)
                    .help(MicaStrings.localizedKey("action.copy_value", language: language))
                    .accessibilityLabel(MicaStrings.localizedKey("action.copy", language: language))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { isHovered = $0 }
        .onChange(of: value) { _, _ in
            copiedRecently = false
        }
    }
}

/// Reported values keep their rows; every field the controller left
/// unreported collapses into one quiet line that still names each field, so
/// real values are not buried under repeated placeholders.
struct WorkbenchDataInspectorValueList: View {
    @Environment(\.micaAppLanguage) private var language

    let values: [WorkbenchDataInspectorValue]

    var body: some View {
        let notReported = MicaStrings.localizedKey("overview.config_not_reported", language: language)
        let isReported: (WorkbenchDataInspectorValue) -> Bool = { item in
            guard let value = item.value?.dataNonEmpty else { return false }
            return value != notReported
        }
        let reported = values.filter(isReported)
        let unreported = values.filter { !isReported($0) }

        ForEach(reported) { item in
            WorkbenchDataInspectorField(
                titleKey: item.titleKey,
                value: item.value,
                monospaced: item.monospaced
            )
        }

        if !unreported.isEmpty {
            let names = unreported
                .map { MicaStrings.localizedKey($0.titleKey, language: language) }
                .joined(separator: " · ")
            Text("\(Text(verbatim: notReported).fontWeight(.medium))  \(Text(verbatim: names))")
                .micaThemeFont(.caption)
                .foregroundStyle(MicaTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(Text(verbatim: "\(notReported): \(names)"))
        }
    }
}
