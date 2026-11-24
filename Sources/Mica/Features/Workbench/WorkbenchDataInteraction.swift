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

    static func height(for fontScale: AppFontScale, lines: Int = 2) -> CGFloat {
        if lines <= 1 {
            return max(30, ceil(28 * fontScale.multiplier))
        }
        return max(40, ceil(42 * fontScale.multiplier))
    }
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
    @State private var mode: WorkbenchDataWidthMode = .compact

    init(
        budget: WorkbenchDataWidthBudget,
        @ViewBuilder content: @escaping (WorkbenchDataWidthMode) -> Content
    ) {
        self.budget = budget
        self.content = content
    }

    var body: some View {
        let widthBudget = budget
#if DEBUG
        resolvedContent(for: mode)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: WorkbenchDataWidthMode.self) { proxy in
                widthBudget.mode(for: proxy.size.width)
            } action: { _, nextMode in
                if mode != nextMode {
                    mode = nextMode
                }
            }
#else
        content(mode)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: WorkbenchDataWidthMode.self) { proxy in
                widthBudget.mode(for: proxy.size.width)
            } action: { _, nextMode in
                if mode != nextMode {
                    mode = nextMode
                }
            }
#endif
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

struct WorkbenchDataScrollDelivery: Equatable {
    let generation: UUID
    let request: WorkbenchDataScrollRequest?
    let restorationID: String?
}

struct WorkbenchDataScrollDeliveryState {
    private var previous: WorkbenchDataScrollDelivery?

    mutating func target(
        for delivery: WorkbenchDataScrollDelivery,
        isUserScrolling: Bool
    ) -> String? {
        let previous = self.previous
        self.previous = delivery
        if previous?.generation != delivery.generation {
            return delivery.request?.id ?? (isUserScrolling ? nil : delivery.restorationID)
        }
        if previous?.request?.token != delivery.request?.token, let request = delivery.request {
            return request.id
        }
        if previous?.restorationID != delivery.restorationID, !isUserScrolling {
            return delivery.restorationID
        }
        return nil
    }
}

private struct WorkbenchDataScrollReadiness: Equatable {
    let delivery: WorkbenchDataScrollDelivery
    let tableID: ObjectIdentifier?
}

enum WorkbenchDataScrollTransition: Equatable {
    case began
    case ended
}

/// The native table's user-scroll rules, kept free of AppKit and real time
/// so they can be verified with explicit instants. An explicit gesture
/// (trackpad begin/end, which also brackets momentum) ends only with its end
/// notification. Scroll ticks outside a gesture form a wheel burst that ends
/// once no tick arrives for `wheelIdleDelay`.
struct WorkbenchScrollInteractionState: Equatable {
    enum Phase: Equatable { case idle, gesture, wheel }

    static let wheelIdleDelay = Duration.milliseconds(150)

    let wheelIdleDelay: Duration
    private(set) var phase = Phase.idle
    private(set) var wheelIdleDeadline: ContinuousClock.Instant?

    init(wheelIdleDelay: Duration = Self.wheelIdleDelay) {
        self.wheelIdleDelay = wheelIdleDelay
    }

    mutating func beginGesture() -> WorkbenchDataScrollTransition? {
        wheelIdleDeadline = nil
        let wasIdle = phase == .idle
        phase = .gesture
        return wasIdle ? .began : nil
    }

    /// Starts or extends a wheel burst; ticks inside a gesture are ignored.
    mutating func didScroll(at now: ContinuousClock.Instant) -> WorkbenchDataScrollTransition? {
        guard phase != .gesture else { return nil }
        let wasIdle = phase == .idle
        phase = .wheel
        wheelIdleDeadline = now.advanced(by: wheelIdleDelay)
        return wasIdle ? .began : nil
    }

    /// Ends the wheel burst once its latest deadline has passed.
    mutating func wheelIdleElapsed(at now: ContinuousClock.Instant) -> WorkbenchDataScrollTransition? {
        guard phase == .wheel, let deadline = wheelIdleDeadline, deadline <= now else {
            return nil
        }
        phase = .idle
        wheelIdleDeadline = nil
        return .ended
    }

    mutating func finish() -> WorkbenchDataScrollTransition? {
        wheelIdleDeadline = nil
        guard phase != .idle else { return nil }
        phase = .idle
        return .ended
    }
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

    func apply(_ transition: WorkbenchDataScrollTransition) {
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
    let onReachedBottom: () -> Void
    let onAnchorCommit: (String?) -> Void
    private let content: Content
    private let rowIndex: (String) -> Int?
    private let rowID: (Int) -> String?

    @State private var anchorID: String?
    @State private var phaseState = WorkbenchDataScrollPhaseState()
    @State private var deliveryState = WorkbenchDataScrollDeliveryState()
    @State private var tableLifecycle: WorkbenchNativeTableLifecycle
    @State private var readyTableID: ObjectIdentifier?

    init(
        generation: UUID,
        restorationID: String?,
        request: WorkbenchDataScrollRequest? = nil,
        anchor: UnitPoint = .top,
        wheelIdleDelay: Duration = WorkbenchScrollInteractionState.wheelIdleDelay,
        interaction: WorkbenchDataInteractionCoordinator,
        rowIndex: @escaping (String) -> Int?,
        rowID: @escaping (Int) -> String?,
        onInteractionBegan: @escaping () -> Void = {},
        onInteractionEnded: @escaping () -> Void = {},
        onReachedBottom: @escaping () -> Void = {},
        onAnchorCommit: @escaping (String?) -> Void = { _ in },
        @ViewBuilder content: () -> Content
    ) {
        self.generation = generation
        self.restorationID = restorationID
        self.request = request
        self.anchor = anchor
        self.interaction = interaction
        self.rowIndex = rowIndex
        self.rowID = rowID
        self.onInteractionBegan = onInteractionBegan
        self.onInteractionEnded = onInteractionEnded
        self.onReachedBottom = onReachedBottom
        self.onAnchorCommit = onAnchorCommit
        self.content = content()
        _tableLifecycle = State(initialValue: WorkbenchNativeTableLifecycle(wheelIdleDelay: wheelIdleDelay))
    }

    var body: some View {
        content
                .background {
                    WorkbenchTableLifecycleMarker(
                        lifecycle: tableLifecycle,
                        edge: .before,
                        onReady: { readyTableID = $0 },
                        onDetach: { if readyTableID == $0 { readyTableID = nil } },
                        onInteraction: handleNativeScroll
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .overlay {
                    WorkbenchTableLifecycleMarker(
                        lifecycle: tableLifecycle,
                        edge: .after,
                        onReady: { readyTableID = $0 },
                        onDetach: { if readyTableID == $0 { readyTableID = nil } },
                        onInteraction: handleNativeScroll
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .task(id: WorkbenchDataScrollReadiness(delivery: scrollDelivery, tableID: readyTableID)) {
                    let delivery = scrollDelivery
                    guard readyTableID != nil else { return }
                    await Task.yield()
                    guard !Task.isCancelled,
                          let target = deliveryState.target(
                            for: delivery,
                            isUserScrolling: phaseState.isUserScrolling
                          ) else { return }
                    anchorID = target
                    tableLifecycle.scrollToRow(anchor: anchor) { rowIndex(target) }
                }
                .onChange(of: generation) {
                    tableLifecycle.cancelScroll()
                    finishInteractionIfNeeded()
                    anchorID = nil
                }
                .onDisappear {
                    tableLifecycle.cancelScroll()
                    finishInteractionIfNeeded()
                    commitVisibleAnchor()
                }
    }

    private var scrollDelivery: WorkbenchDataScrollDelivery {
        WorkbenchDataScrollDelivery(
            generation: generation,
            request: request,
            restorationID: restorationID
        )
    }

    private func handleNativeScroll(_ transition: WorkbenchDataScrollTransition) {
        if let changed = phaseState.update(isUserScrolling: transition == .began) {
            apply(changed)
        }
        if transition == .ended {
            commitVisibleAnchor()
            if anchor.y > 0.5, tableLifecycle.isScrolledNearBottom {
                onReachedBottom()
            }
        }
    }

    private func commitVisibleAnchor() {
        guard let index = tableLifecycle.visibleRowIndex(preferringLast: anchor.y > 0.5),
              let id = rowID(index) else { return }
        anchorID = id
        onAnchorCommit(id)
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
