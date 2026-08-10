import Foundation
import MicaCore
import SwiftUI

// MARK: - Shared data-page views

extension View {
    func micaWorkbenchTable(accessibilityLabel: String) -> some View {
        tableStyle(.bordered(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
            .background(MicaDesignTokens.contentFill)
            .tint(MicaDesignTokens.accent)
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
            width: MicaBounds.iconControlSize,
            height: MicaBounds.controlMinHeight
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
                .background(MicaDesignTokens.pageFill)
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
        HStack(alignment: .center, spacing: MicaSpacing.row) {
            Image(systemName: systemImage)
                .micaFont(.caption, weight: .semibold)
                .foregroundStyle(tint)
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                    .micaFont(
                        .callout,
                        weight: .semibold,
                        design: titleIsMonospaced ? .monospaced : .default
                    )
                    .lineLimit(1)
                    .textSelection(.enabled)

                if let detail = detail?.dataNonEmpty {
                    Text(verbatim: detail)
                        .micaFont(
                            .caption,
                            design: detailIsMonospaced ? .monospaced : .default
                        )
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
    var style: MicaTextStyle = .callout
    var weight: Font.Weight?
    var design: Font.Design = .default
    var tone: HierarchicalShapeStyle = .primary
    var alignment: Alignment = .leading
    var maximumLineCount = 1

    var body: some View {
        Text(verbatim: value)
            .micaFont(style, weight: weight, design: design)
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
            HStack(spacing: MicaSpacing.module) { confirmationContent }
            VStack(alignment: .leading, spacing: MicaSpacing.row) { confirmationContent }
        }
        .padding(.horizontal, MicaBounds.chromeHorizontalPadding)
        .padding(.vertical, MicaSpacing.row)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MicaDesignTokens.signalRed.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
        .onExitCommand(perform: cancel)
    }

    @ViewBuilder
    private var confirmationContent: some View {
        Label {
            Text(verbatim: message)
                .micaFont(.callout)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MicaDesignTokens.signalRed)
        }

        Spacer(minLength: MicaSpacing.row)

        Button(MicaStrings.localizedKey("action.cancel", language: language), action: cancel)
            .frame(minHeight: MicaBounds.controlMinHeight)

        Button(
            MicaStrings.localizedKey(confirmTitleKey, language: language),
            role: .destructive,
            action: confirm
        )
        .buttonStyle(.borderedProminent)
        .tint(MicaDesignTokens.signalRed)
        .disabled(!isConfirmEnabled)
        .frame(minHeight: MicaBounds.controlMinHeight)
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
            LazyVStack(alignment: .leading, spacing: MicaSpacing.section) {
                HStack(alignment: .top, spacing: MicaSpacing.row) {
                    VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                        Text(verbatim: title)
                            .micaFont(.title3, weight: .semibold)
                            .textSelection(.enabled)

                        if let subtitle = subtitle?.dataNonEmpty {
                            Text(verbatim: subtitle)
                                .micaFont(.caption, design: .monospaced)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        if let statusText = statusText?.dataNonEmpty {
                            WorkbenchStatusBadge(text: statusText, tint: statusTint)
                        }
                    }

                    Spacer(minLength: MicaSpacing.row)

                    Button(action: close) {
                        Image(systemName: "xmark")
                            .accessibilityHidden(true)
                    }
                    .buttonStyle(.borderless)
                    .frame(
                        minWidth: MicaBounds.iconControlSize,
                        minHeight: MicaBounds.iconControlSize
                    )
                    .accessibilityLabel(
                        MicaStrings.localizedKey("dashboard.close_inspector", language: language)
                    )
                }

                content
            }
            .padding(MicaSpacing.section)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .micaObserveScrollPerformance()
        .background(MicaDesignTokens.contentFill)
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
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            Text(MicaStrings.localizedKey(titleKey, language: language))
                .micaFont(.caption, weight: .semibold)
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
        HStack(alignment: .top, spacing: MicaSpacing.module) {
            Text(MicaStrings.localizedKey(titleKey, language: language))
                .micaFont(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)

            Text(
                verbatim: value?.dataNonEmpty
                    ?? MicaStrings.localizedKey("overview.config_not_reported", language: language)
            )
            .micaFont(.callout, design: monospaced ? .monospaced : .default)
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
