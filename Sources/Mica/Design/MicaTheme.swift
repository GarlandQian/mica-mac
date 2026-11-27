import AppKit
import SwiftUI

/// Minimal native macOS design tokens and lightweight building blocks.
/// Relies on system semantic surfaces, hairline separators, and calm spacing
/// without card drop shadows or glass hover overlays.
enum MicaTheme {
    // MARK: - Surfaces & Separators

    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let subtleFill = Color.primary.opacity(0.035)
    static let selectedFill = Color.accentColor.opacity(0.12)
    static let separator = Color(nsColor: .separatorColor)
    static let accent = Color(nsColor: .controlAccentColor)

    // MARK: - Text

    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    // MARK: - Status & Metrics

    static let statusOK = Color.green
    static let statusWarning = Color.orange
    static let statusError = Color.red
    static let statusInfo = Color.blue

    static let chartUpload = Color.teal
    static let chartDownload = Color.blue
    static let chartConnections = Color.orange
    static let chartMemory = Color.purple

    enum Status: Sendable, Equatable {
        case ok
        case warning
        case error
        case neutral

        var color: Color {
            switch self {
            case .ok: MicaTheme.statusOK
            case .warning: MicaTheme.statusWarning
            case .error: MicaTheme.statusError
            case .neutral: MicaTheme.textTertiary
            }
        }
    }

    static func latencyColor(for delay: Int?, alive: Bool? = nil) -> Color {
        if alive == false {
            return statusError
        }
        guard let delay else {
            return textTertiary
        }
        if delay <= 0 {
            return statusError
        }
        if delay < 120 {
            return statusOK
        }
        if delay < 350 {
            return statusWarning
        }
        return statusError
    }

    // MARK: - Spacing & Radii

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 6
        static let card: CGFloat = 8
        static let panel: CGFloat = 10
    }
}

// MARK: - Lightweight Reusable Views

struct MicaStatusDot: View {
    let color: Color
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct MicaHairlineDivider: View {
    var axis: Axis = .horizontal

    var body: some View {
        switch axis {
        case .horizontal:
            MicaTheme.separator.frame(maxWidth: .infinity, maxHeight: 1)
        case .vertical:
            MicaTheme.separator.frame(maxWidth: 1, maxHeight: .infinity)
        }
    }
}

struct MicaSectionLabel: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MicaTheme.Spacing.sm) {
            Text(verbatim: title)
                .font(.headline)
                .foregroundStyle(MicaTheme.textPrimary)
            if let detail, !detail.isEmpty {
                Text(verbatim: detail)
                    .font(.caption)
                    .foregroundStyle(MicaTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct MicaEmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: MicaTheme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(MicaTheme.textTertiary)
                .accessibilityHidden(true)

            VStack(spacing: MicaTheme.Spacing.xs) {
                Text(verbatim: title)
                    .font(.headline)
                    .foregroundStyle(MicaTheme.textPrimary)
                    .multilineTextAlignment(.center)

                if let message, !message.isEmpty {
                    Text(verbatim: message)
                        .font(.subheadline)
                        .foregroundStyle(MicaTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.regular)
            }
        }
        .padding(MicaTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MicaKeyValueRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MicaTheme.Spacing.md) {
            Text(verbatim: label)
                .font(.caption)
                .foregroundStyle(MicaTheme.textSecondary)
                .frame(width: 96, alignment: .leading)
            Text(verbatim: value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .foregroundStyle(MicaTheme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }
}

struct MicaInlineBanner: View {
    enum Tone {
        case info
        case warning
        case error

        var color: Color {
            switch self {
            case .info: MicaTheme.statusInfo
            case .warning: MicaTheme.statusWarning
            case .error: MicaTheme.statusError
            }
        }

        var symbol: String {
            switch self {
            case .info: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }
    }

    let tone: Tone
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: MicaTheme.Spacing.sm) {
            Image(systemName: tone.symbol)
                .foregroundStyle(tone.color)
            Text(verbatim: message)
                .font(.callout)
                .foregroundStyle(MicaTheme.textPrimary)
                .lineLimit(2)
            Spacer(minLength: MicaTheme.Spacing.sm)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, MicaTheme.Spacing.md)
        .padding(.vertical, MicaTheme.Spacing.sm)
        .background(tone.color.opacity(0.08))
        .overlay(alignment: .bottom) {
            MicaHairlineDivider()
        }
    }
}
