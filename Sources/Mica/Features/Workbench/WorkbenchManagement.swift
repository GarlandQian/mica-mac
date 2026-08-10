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
        self = availableWidth < MicaBounds.wideThreshold ? .compact : .regular
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
                VStack(alignment: .leading, spacing: MicaSpacing.section) {
                    content
                }
                .padding(.horizontal, MicaBounds.pagePadding(for: geometry.size.width))
                .padding(.vertical, MicaSpacing.section)
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
                MicaBounds.pagePadding(for: geometry.size.width),
                for: .scrollContent
            )
            .contentMargins(.top, MicaSpacing.module, for: .scrollContent)
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
    var tint = MicaDesignTokens.signalCyan

    var body: some View {
        HStack(alignment: .top, spacing: MicaSpacing.row) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: MicaSpacing.row) {
                    Text(MicaStrings.localizedKey(titleKey, language: language))
                        .micaFont(.headline)

                    if let value = value?.managementNonEmpty {
                        Text(verbatim: value)
                            .micaFont(.caption, weight: .semibold, design: .monospaced)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if let detail = detail?.managementNonEmpty {
                    Text(verbatim: detail)
                        .micaFont(.caption)
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
        HStack(alignment: .top, spacing: MicaSpacing.module) {
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

            VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                Text(verbatim: title)
                    .micaFont(.callout, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = detail?.managementNonEmpty {
                    Text(verbatim: detail)
                        .micaFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, MicaSpacing.row)
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
                VStack(alignment: .leading, spacing: MicaSpacing.row) {
                    label
                    controlColumn
                }
            } else {
                HStack(alignment: .top, spacing: MicaSpacing.module) {
                    label
                        .frame(width: MicaBounds.formLabelWidth, alignment: .leading)
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
                .micaFont(.callout, weight: .medium)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let detailKey {
                Text(MicaStrings.localizedKey(detailKey, language: language))
                    .micaFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var controlColumn: some View {
        HStack(alignment: .center, spacing: MicaSpacing.row) {
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
            .micaFont(.body, design: monospaced ? .monospaced : .default)
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
                HStack(alignment: .top, spacing: MicaSpacing.module) {
                    explanation
                    Spacer(minLength: MicaSpacing.module)
                    commandColumn
                }
            case .compact:
                VStack(alignment: .leading, spacing: MicaSpacing.row) {
                    explanation
                    commandColumn
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: MicaBounds.controlMinHeight, alignment: .leading)
        .padding(.vertical, MicaSpacing.tight)
    }

    private var explanation: some View {
        HStack(alignment: .top, spacing: MicaSpacing.row) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(MicaStrings.localizedKey(titleKey, language: language))
                    .micaFont(.callout, weight: .medium)

                Text(MicaStrings.localizedKey(detailKey, language: language))
                    .micaFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let reason = reason?.managementNonEmpty {
                    Text(verbatim: reason)
                        .micaFont(.caption)
                        .foregroundStyle(MicaDesignTokens.signalAmber)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
        }
    }

    private var commandColumn: some View {
        HStack(spacing: MicaSpacing.row) {
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
            minHeight: MicaBounds.controlMinHeight,
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
