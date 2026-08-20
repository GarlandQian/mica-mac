import Foundation
import MicaCore
import SwiftUI

// MARK: - Shared management structure

enum WorkbenchManagementMetrics {
    static let formCanvasWidth: CGFloat = 1_040
    static let maximumCanvasWidth: CGFloat = 1_180
    static let controllerListWidth: CGFloat = 320
}

enum WorkbenchManagementWidthMode: Equatable, Sendable {
    case compact
    case regular

    init(availableWidth: CGFloat) {
        self = availableWidth < MicaTheme.Metrics.wideThreshold ? .compact : .regular
    }
}

extension EnvironmentValues {
    @Entry var workbenchManagementWidthMode: WorkbenchManagementWidthMode = .regular
}

struct WorkbenchManagementCanvas<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let widthMode = WorkbenchManagementWidthMode(
                availableWidth: geometry.size.width
            )

            ScrollView {
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space4) {
                    content
                }
                .padding(.horizontal, MicaTheme.Metrics.pagePadding(for: geometry.size.width))
                .padding(.vertical, MicaTheme.Spacing.space4)
                .frame(
                    maxWidth: WorkbenchManagementMetrics.maximumCanvasWidth,
                    alignment: .topLeading
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .micaObserveScrollPerformance()
            .environment(\.workbenchManagementWidthMode, widthMode)
        }
    }
}

struct WorkbenchManagementFormCanvas<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let widthMode = WorkbenchManagementWidthMode(
                availableWidth: geometry.size.width
            )

            Form {
                content
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .contentMargins(
                .horizontal,
                MicaTheme.Metrics.pagePadding(for: geometry.size.width),
                for: .scrollContent
            )
            .contentMargins(.top, MicaTheme.Spacing.space3, for: .scrollContent)
            .micaObserveScrollPerformance()
            .frame(
                maxWidth: WorkbenchManagementMetrics.formCanvasWidth,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.workbenchManagementWidthMode, widthMode)
        }
    }
}

struct WorkbenchManagementHeader: View {
    @Environment(\.micaAppLanguage) private var language

    let systemImage: String
    let titleKey: String
    var detail: String?
    var value: String?
    var tint = MicaTheme.textSecondary

    var body: some View {
        HStack(alignment: .top, spacing: MicaTheme.Spacing.space2) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: MicaTheme.Spacing.space2) {
                    Text(MicaStrings.localizedKey(titleKey, language: language))
                        .micaThemeFont(.body, weight: .semibold)

                    if let value = value?.managementNonEmpty {
                        Text(verbatim: value)
                            .micaThemeFont(.dataCaption, weight: .semibold)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if let detail = detail?.managementNonEmpty {
                    Text(verbatim: detail)
                        .micaThemeFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct WorkbenchManagementInlineState: View {
    let systemImage: String
    let title: String
    var detail: String?
    var tint: Color = .secondary
    var isLoading = false

    var body: some View {
        HStack(alignment: .top, spacing: MicaTheme.Spacing.space3) {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: MicaTheme.Spacing.space1) {
                Text(verbatim: title)
                    .micaThemeFont(.label, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = detail?.managementNonEmpty {
                    Text(verbatim: detail)
                        .micaThemeFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, MicaTheme.Spacing.space2)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct WorkbenchFormRow<Control: View>: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.workbenchManagementWidthMode) private var widthMode

    let titleKey: String
    var detailKey: String?
    var isBusy = false
    private let control: Control

    init(
        _ titleKey: String,
        detailKey: String? = nil,
        isBusy: Bool = false,
        @ViewBuilder control: () -> Control
    ) {
        self.titleKey = titleKey
        self.detailKey = detailKey
        self.isBusy = isBusy
        self.control = control()
    }

    /// Typography can grow without changing the information architecture.
    /// Only the actual available width decides when the columns stack.
    private var usesStackedLayout: Bool {
        widthMode == .compact
    }

    var body: some View {
        Group {
            if usesStackedLayout {
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                    label
                    controlColumn
                }
            } else {
                HStack(alignment: .top, spacing: MicaTheme.Spacing.space3) {
                    label
                        .frame(width: MicaTheme.Metrics.formLabelWidth, alignment: .leading)
                    controlColumn
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(MicaStrings.localizedKey(titleKey, language: language))
                .micaThemeFont(.label, weight: .medium)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let detailKey {
                Text(MicaStrings.localizedKey(detailKey, language: language))
                    .micaThemeFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var controlColumn: some View {
        HStack(alignment: .center, spacing: MicaTheme.Spacing.space2) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
            control
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .labelsHidden()
    }
}

struct WorkbenchFormValue: View {
    let value: String
    var monospaced = false
    var placeholder = false

    var body: some View {
        Text(verbatim: value)
            .micaThemeFont(monospaced ? .dataBody : .body)
            .foregroundStyle(placeholder ? .secondary : .primary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkbenchOperationLine<Command: View>: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(\.workbenchManagementWidthMode) private var widthMode

    let systemImage: String
    let tint: Color
    let titleKey: String
    let detailKey: String
    var reason: String?
    var isRunning = false
    private let command: Command

    init(
        systemImage: String,
        tint: Color,
        titleKey: String,
        detailKey: String,
        reason: String? = nil,
        isRunning: Bool = false,
        @ViewBuilder command: () -> Command
    ) {
        self.systemImage = systemImage
        self.tint = tint
        self.titleKey = titleKey
        self.detailKey = detailKey
        self.reason = reason
        self.isRunning = isRunning
        self.command = command()
    }

    var body: some View {
        Group {
            switch widthMode {
            case .regular:
                HStack(alignment: .top, spacing: MicaTheme.Spacing.space3) {
                    explanation
                    Spacer(minLength: MicaTheme.Spacing.space3)
                    commandColumn
                }
            case .compact:
                VStack(alignment: .leading, spacing: MicaTheme.Spacing.space2) {
                    explanation
                    commandColumn
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: MicaTheme.Metrics.controlMinHeight, alignment: .leading)
        .padding(.vertical, MicaTheme.Spacing.space1)
    }

    private var explanation: some View {
        HStack(alignment: .top, spacing: MicaTheme.Spacing.space2) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(MicaStrings.localizedKey(titleKey, language: language))
                    .micaThemeFont(.label, weight: .medium)

                Text(MicaStrings.localizedKey(detailKey, language: language))
                    .micaThemeFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let reason = reason?.managementNonEmpty {
                    Text(verbatim: reason)
                        .micaThemeFont(.caption)
                        .foregroundStyle(MicaTheme.statusWarning)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
        }
    }

    private var commandColumn: some View {
        HStack(spacing: MicaTheme.Spacing.space2) {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
            command
        }
        .frame(
            minWidth: 150,
            maxWidth: .infinity,
            minHeight: MicaTheme.Metrics.controlMinHeight,
            alignment: .trailing
        )
    }
}

extension String {
    var managementNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

func workbenchDisplayableDate(_ date: Date?) -> Date? {
    guard let date, date.timeIntervalSince1970 >= 31_536_000 else {
        return nil
    }
    return date
}
