import SwiftUI

struct OverviewMotionState: Equatable, Sendable {
    let allowsMotion: Bool

    static func resolve(
        reduceMotion: Bool,
        isWindowActive: Bool,
        isPaused: Bool
    ) -> OverviewMotionState {
        OverviewMotionState(
            allowsMotion: !reduceMotion && isWindowActive && !isPaused
        )
    }
}

enum OverviewCyberSurfaceRole: Sendable {
    case telemetry
    case topology
    case auxiliary
    case hud

    var tint: Color {
        switch self {
        case .telemetry, .topology, .hud:
            MicaStyle.signalCyan
        case .auxiliary:
            MicaStyle.signalViolet
        }
    }

    var fill: Color {
        switch self {
        case .hud:
            MicaStyle.secondaryContentFill
        case .telemetry, .topology, .auxiliary:
            MicaStyle.contentFill
        }
    }

    var bloomOpacity: Double {
        switch self {
        case .telemetry: 0.12
        case .topology: 0.10
        case .auxiliary: 0.06
        case .hud: 0.18
        }
    }
}

private struct OverviewCyberSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let role: OverviewCyberSurfaceRole
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(role.fill)
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                role.tint.opacity(differentiateWithoutColor ? 0.78 : 0.62),
                                MicaStyle.signalViolet.opacity(0.28),
                                MicaStyle.separator.opacity(0.38),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: differentiateWithoutColor ? 1.5 : 1
                    )
            }
            .shadow(
                color: role.tint.opacity(role.bloomOpacity),
                radius: role == .hud ? 18 : 12,
                x: 0,
                y: role == .hud ? 8 : 4
            )
    }
}

extension View {
    func overviewCyberSurface(
        _ role: OverviewCyberSurfaceRole,
        cornerRadius: CGFloat = MicaBounds.moduleRadius
    ) -> some View {
        modifier(
            OverviewCyberSurfaceModifier(
                role: role,
                cornerRadius: cornerRadius
            )
        )
    }
}

struct OverviewLatestSampleMark: View {
    let tint: Color
    let trigger: Int
    let motionState: OverviewMotionState

    var body: some View {
        if motionState.allowsMotion {
            mark
                .phaseAnimator([0.0, 1.0, 0.0], trigger: trigger) { content, phase in
                    content
                        .scaleEffect(1 + phase * 0.42)
                        .opacity(1 - phase * 0.18)
                } animation: { phase in
                    phase > 0
                        ? .easeOut(duration: 0.22)
                        : .easeInOut(duration: 0.34)
                }
        } else {
            mark
        }
    }

    private var mark: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.48), lineWidth: 1.5)
                .frame(width: 14, height: 14)
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}
