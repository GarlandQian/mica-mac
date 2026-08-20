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

/// Text-style input for `WorkbenchDataText` (task 08-17 Phase 7): the roles
/// map by point size onto `MicaTheme.TextRole` inside the view, keeping the
/// long-standing call sites (`style: .caption, design: .monospaced`) stable
/// while the superseded design-system file is deleted.
enum MicaTextStyle: Sendable, Equatable {
    case largeTitle
    case title
    case title2
    case title3
    case headline
    case body
    case callout
    case subheadline
    case footnote
    case caption
    case caption2
}

struct WorkbenchDataText: View {
    let value: String
    var style: MicaTextStyle = .callout
    var weight: Font.Weight?
    var design: Font.Design = .default
    var tone: HierarchicalShapeStyle = .primary
    var alignment: Alignment = .leading
    var maximumLineCount = 1

    var body: some View {
        Text(verbatim: value)
            .micaThemeFont(Self.themeRole(for: style, design: design), weight: weight)
            .foregroundStyle(tone)
            .lineLimit(maximumLineCount)
            .truncationMode(.tail)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    /// Transitional bridge from the superseded text-style enum to MicaTheme
    /// roles by point size; removed with the old design system in Phase 7.3
    /// (task 08-17 Phase 4C).
    private static func themeRole(for style: MicaTextStyle, design: Font.Design) -> MicaTheme.TextRole {
        if design == .monospaced {
            switch style {
            case .largeTitle: return .dataHeroLarge
            case .title: return .dataHero
            case .title2, .title3: return .dataTitle
            case .headline, .body: return .dataBody
            case .callout: return .dataLabel
            case .subheadline, .footnote, .caption, .caption2: return .dataCaption
            }
        }
        switch style {
        case .largeTitle: return .heroLarge
        case .title: return .hero
        case .title2: return .title
        case .title3: return .title3
        case .headline, .body: return .body
        case .callout: return .label
        case .subheadline, .footnote, .caption, .caption2: return .caption
        }
    }
}

struct WorkbenchDataMetric: View {
    let value: String
    var tone: HierarchicalShapeStyle = .primary

    var body: some View {
        WorkbenchDataText(
            value: value,
            style: .caption,
            design: .monospaced,
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
