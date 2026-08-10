import Foundation
import MicaCore
import SwiftUI

// MARK: - Shared data-page structure

enum WorkbenchDataWidthMode: Equatable {
    case full
    case compact
    case stacked
}

enum WorkbenchDataRowGeometry {
    /// Stable table geometry avoids row churn while leaving enough room for
    /// the two-line data cells used by Connections, Rules, Sources, and Logs.
    static let height: CGFloat = 40
}

struct WorkbenchDataWidthBudget: Equatable {
    let fullMinimum: CGFloat
    let compactMinimum: CGFloat

    func mode(for width: CGFloat) -> WorkbenchDataWidthMode {
        if width >= fullMinimum {
            .full
        } else if width >= compactMinimum {
            .compact
        } else {
            .stacked
        }
    }
}

struct WorkbenchDataResponsive<Content: View>: View {
    let budget: WorkbenchDataWidthBudget
    private let content: (WorkbenchDataWidthMode) -> Content

    init(
        budget: WorkbenchDataWidthBudget,
        @ViewBuilder content: @escaping (WorkbenchDataWidthMode) -> Content
    ) {
        self.budget = budget
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
#if DEBUG
            resolvedContent(for: budget.mode(for: proxy.size.width))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
#else
            content(budget.mode(for: proxy.size.width))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
        }
    }

#if DEBUG
    private func resolvedContent(for mode: WorkbenchDataWidthMode) -> Content {
        MicaPerformanceObservation.recordDebug(
            .dataTableEvaluation,
            metadata: MicaPerformanceMetadata(count: 1)
        )
        return content(mode)
    }
#endif
}

struct WorkbenchDataScrollRequest: Equatable {
    let id: String
    let token: UUID

    init(id: String, token: UUID = UUID()) {
        self.id = id
        self.token = token
    }
}

enum WorkbenchDataScrollTransition: Equatable {
    case began
    case ended
}

struct WorkbenchDataScrollPhaseState: Equatable {
    private(set) var isUserScrolling = false

    mutating func update(isUserScrolling nextValue: Bool) -> WorkbenchDataScrollTransition? {
        guard nextValue != isUserScrolling else { return nil }
        isUserScrolling = nextValue
        return nextValue ? .began : .ended
    }

    mutating func reset() {
        isUserScrolling = false
    }
}

@MainActor
private final class WorkbenchScrollPerformanceTracker {
    private var isScrolling = false

    func update(_ phase: ScrollPhase) {
        let nextIsScrolling = phase != .idle
        guard nextIsScrolling != isScrolling else { return }
        isScrolling = nextIsScrolling
        record(isScrolling: nextIsScrolling)
    }

    func finish() {
        guard isScrolling else { return }
        isScrolling = false
        record(isScrolling: false)
    }

    private func record(isScrolling: Bool) {
        MicaPerformanceObservation.recordDebug(
            .scrollPhase,
            metadata: MicaPerformanceMetadata(
                count: 1,
                revision: isScrolling ? 1 : 2
            )
        )
    }
}

@MainActor
private struct WorkbenchScrollPerformanceModifier: ViewModifier {
    @State private var tracker = WorkbenchScrollPerformanceTracker()

    func body(content: Content) -> some View {
#if DEBUG
        content
            .onScrollPhaseChange { _, phase in
                tracker.update(phase)
            }
            .onDisappear {
                tracker.finish()
            }
#else
        content
#endif
    }
}

@MainActor
final class WorkbenchDataInteractionCoordinator {
    private(set) var isUserScrolling = false

    fileprivate func apply(_ transition: WorkbenchDataScrollTransition) {
        switch transition {
        case .began:
            isUserScrolling = true
        case .ended:
            isUserScrolling = false
        }
    }

    fileprivate func reset() {
        isUserScrolling = false
    }
}

struct WorkbenchDataTableViewport<Content: View>: View {
    let generation: UUID
    let restorationID: String?
    let request: WorkbenchDataScrollRequest?
    let anchor: UnitPoint
    let interaction: WorkbenchDataInteractionCoordinator
    let onInteractionBegan: () -> Void
    let onInteractionEnded: () -> Void
    let onAnchorCommit: (String?) -> Void
    private let content: Content

    @State private var anchorID: String?
    @State private var phaseState = WorkbenchDataScrollPhaseState()

    init(
        generation: UUID,
        restorationID: String?,
        request: WorkbenchDataScrollRequest? = nil,
        anchor: UnitPoint = .top,
        interaction: WorkbenchDataInteractionCoordinator,
        onInteractionBegan: @escaping () -> Void = {},
        onInteractionEnded: @escaping () -> Void = {},
        onAnchorCommit: @escaping (String?) -> Void = { _ in },
        @ViewBuilder content: () -> Content
    ) {
        self.generation = generation
        self.restorationID = restorationID
        self.request = request
        self.anchor = anchor
        self.interaction = interaction
        self.onInteractionBegan = onInteractionBegan
        self.onInteractionEnded = onInteractionEnded
        self.onAnchorCommit = onAnchorCommit
        self.content = content()
    }

    var body: some View {
        content
            .scrollPosition(id: $anchorID, anchor: anchor)
            .onAppear {
                if anchorID == nil {
                    anchorID = restorationID
                }
            }
            .onChange(of: generation) {
                finishInteractionIfNeeded()
                anchorID = restorationID
            }
            .onChange(of: restorationID) { _, nextID in
                if !phaseState.isUserScrolling {
                    anchorID = nextID
                }
            }
            .onChange(of: request) { _, nextRequest in
                if let nextRequest {
                    anchorID = nextRequest.id
                }
            }
            .onScrollPhaseChange { _, phase in
                handleScrollPhase(phase)
            }
            .onDisappear {
                finishInteractionIfNeeded()
                onAnchorCommit(anchorID)
            }
    }

    private func handleScrollPhase(_ phase: ScrollPhase) {
        let isUserScrolling = switch phase {
        case .tracking, .interacting, .decelerating:
            true
        case .idle, .animating:
            false
        }

        if let transition = phaseState.update(isUserScrolling: isUserScrolling) {
            apply(transition)
        }

        if phase == .idle {
            onAnchorCommit(anchorID)
        }
    }

    private func finishInteractionIfNeeded() {
        if let transition = phaseState.update(isUserScrolling: false) {
            apply(transition)
        } else {
            interaction.reset()
        }
        phaseState.reset()
    }

    private func apply(_ transition: WorkbenchDataScrollTransition) {
#if DEBUG
        MicaPerformanceObservation.recordDebug(
            .scrollPhase,
            metadata: MicaPerformanceMetadata(
                count: 1,
                revision: transition == .began ? 1 : 2
            )
        )
#endif
        interaction.apply(transition)
        switch transition {
        case .began:
            onInteractionBegan()
        case .ended:
            onInteractionEnded()
        }
    }
}

extension View {
    func micaObserveScrollPerformance() -> some View {
        modifier(WorkbenchScrollPerformanceModifier())
    }
}
