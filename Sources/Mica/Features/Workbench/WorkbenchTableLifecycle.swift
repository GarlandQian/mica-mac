import AppKit
import SwiftUI

@MainActor
final class WorkbenchNativeTableLifecycle {
    enum Edge { case before, after }
    private enum Interaction { case idle, gesture, wheel }

    private weak var before: NSView?
    private weak var after: NSView?
    private weak var table: NSTableView?
    private var frameObservation: NSObjectProtocol?
    private var enabledFrameNotifications = false
    private var inspectionScheduled = false
    private var reportedTableID: ObjectIdentifier?
    private var onReady: (ObjectIdentifier) -> Void = { _ in }
    private var onInteraction: (WorkbenchDataScrollTransition) -> Void = { _ in }
    private var pendingRowIndex: (() -> Int?)?
    private var lastScrollGeometry: CGRect?
    private var scrollCorrections = 0
    private var liveScrollObservations: [NSObjectProtocol] = []
    private var interaction: Interaction = .idle
    private var wheelIdleDeadline: ContinuousClock.Instant?
    private var wheelIdleTask: Task<Void, Never>?
    private var wheelIdleGeneration: UInt64 = 0
    private var isCorrectingScroll = false

    func attach(
        _ marker: NSView,
        edge: Edge,
        onReady: @escaping (ObjectIdentifier) -> Void,
        onInteraction: @escaping (WorkbenchDataScrollTransition) -> Void
    ) {
        self.onReady = onReady
        self.onInteraction = onInteraction
        switch edge {
        case .before: before = marker
        case .after: after = marker
        }
        scheduleInspection()
    }

    func scheduleInspection() {
        if let table, table.window != nil,
           reportedTableID == ObjectIdentifier(table), pendingRowIndex == nil { return }
        guard !inspectionScheduled else { return }
        inspectionScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.inspectionScheduled = false
            self.inspect()
        }
    }

    func detach(_ marker: NSView) {
        guard before === marker || after === marker else { return }
        if before === marker { before = nil }
        if after === marker { after = nil }
        stopObservingFrame()
        cancelScroll()
        removeInteractionObservers()
        table = nil
        reportedTableID = nil
        if before == nil, after == nil {
            onReady = { _ in }
            onInteraction = { _ in }
        }
    }

    func scrollToRow(resolving rowIndex: @escaping () -> Int?) {
        guard let table, table.window != nil else { return }
        finishInteraction()
        pendingRowIndex = rowIndex
        lastScrollGeometry = nil
        scrollCorrections = 0
        observeFrame(of: table)
        correctPendingScroll()
    }

    func cancelScroll() {
        finishInteraction()
        cancelPendingScroll()
    }

    private func cancelPendingScroll() {
        pendingRowIndex = nil
        lastScrollGeometry = nil
        scrollCorrections = 0
        stopObservingFrame()
    }

    func visibleRowIndex(preferringLast: Bool) -> Int? {
        guard let table, table.numberOfRows > 0 else { return nil }
        let rows = table.rows(in: table.visibleRect)
        guard rows.location != NSNotFound, rows.length > 0 else { return nil }
        return preferringLast
            ? min(NSMaxRange(rows) - 1, table.numberOfRows - 1)
            : rows.location
    }

    private func correctPendingScroll() {
        guard let table, let index = pendingRowIndex?(),
              table.window != nil, index >= 0 else {
            cancelScroll()
            return
        }
        guard index < table.numberOfRows else { return }
        let target = table.rect(ofRow: index)
        let visible = table.visibleRect
        if target.intersection(visible).height >= min(target.height, visible.height),
           table.rowView(atRow: index, makeIfNecessary: false) != nil {
            cancelScroll()
            return
        }
        // Automatic row heights replace estimates as the destination is laid
        // out. Correct only when that real geometry changes, never on a timer.
        guard target != lastScrollGeometry else { return }
        guard scrollCorrections < 8 else {
            cancelScroll()
            return
        }
        lastScrollGeometry = target
        scrollCorrections += 1
        isCorrectingScroll = true
        table.scrollRowToVisible(index)
        isCorrectingScroll = false
        scheduleInspection()
    }

    private func inspect() {
        guard let before, let after, before.window != nil,
              before.window === after.window,
              let target = Self.table(between: before, and: after) else { return }
        if table !== target {
            stopObservingFrame()
            removeInteractionObservers()
            table = target
            reportedTableID = nil
            observeInteraction(of: target)
        }
        if reportedTableID == ObjectIdentifier(target) {
            correctPendingScroll()
            return
        }
        let visibleRows = target.rows(in: target.visibleRect)
        if target.numberOfRows > 0,
           target.visibleRect.height > 0,
           visibleRows.length > 0, visibleRows.location != NSNotFound,
           target.rowView(atRow: visibleRows.location, makeIfNecessary: false) != nil {
            let id = ObjectIdentifier(target)
            guard reportedTableID != id else { return }
            reportedTableID = id
            stopObservingFrame()
            onReady(id)
            return
        }
        observeFrame(of: target)
    }

    private func observeFrame(of target: NSTableView) {
        guard frameObservation == nil else { return }
        enabledFrameNotifications = !target.postsFrameChangedNotifications
        target.postsFrameChangedNotifications = true
        frameObservation = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: target,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleInspection() }
        }
    }

    private func observeInteraction(of table: NSTableView) {
        guard let scrollView = table.enclosingScrollView else { return }
        for name in [NSScrollView.willStartLiveScrollNotification,
                     NSScrollView.didLiveScrollNotification,
                     NSScrollView.didEndLiveScrollNotification] {
            let observer = NotificationCenter.default.addObserver(
                forName: name,
                object: scrollView,
                queue: .main
            ) { [weak self, weak table, weak scrollView] _ in
                MainActor.assumeIsolated {
                    guard let self, let table, let scrollView,
                          self.table === table, table.enclosingScrollView === scrollView,
                          table.window != nil, !self.isCorrectingScroll else { return }
                    switch name {
                    case NSScrollView.willStartLiveScrollNotification:
                        self.beginGesture()
                    case NSScrollView.didLiveScrollNotification:
                        self.didScroll(table: table)
                    default:
                        self.finishInteraction()
                    }
                }
            }
            liveScrollObservations.append(observer)
        }
    }

    private func removeInteractionObservers() {
        finishInteraction()
        for observer in liveScrollObservations {
            NotificationCenter.default.removeObserver(observer)
        }
        liveScrollObservations.removeAll()
    }

    private func beginGesture() {
        cancelWheelIdle()
        cancelPendingScroll()
        let wasIdle = interaction == .idle
        interaction = .gesture
        if wasIdle { onInteraction(.began) }
    }

    private func didScroll(table: NSTableView) {
        // A trackpad's explicit begin/end also brackets momentum. A quiet gap
        // must not end that session. NSScrollView documents that legacy mice
        // can emit didLive without a willStart/didEnd pair.
        guard interaction != .gesture else { return }
        let wasIdle = interaction == .idle
        if wasIdle { cancelPendingScroll() }
        interaction = .wheel
        wheelIdleDeadline = ContinuousClock.now.advanced(by: .milliseconds(150))
        if wasIdle { onInteraction(.began) }
        guard wheelIdleTask == nil else { return }
        let generation = wheelIdleGeneration
        wheelIdleTask = Task { @MainActor [weak self, weak table] in
            // Keep one sleeper per wheel burst. Further ticks only move the
            // deadline; they do not cancel and allocate a task per event.
            while !Task.isCancelled {
                guard let self, let table, self.table === table,
                      table.window != nil, self.interaction == .wheel,
                      generation == self.wheelIdleGeneration,
                      let deadline = self.wheelIdleDeadline else { return }
                if deadline > ContinuousClock.now {
                    do { try await Task.sleep(until: deadline, clock: .continuous) }
                    catch { return }
                    continue
                }
                self.wheelIdleTask = nil
                self.wheelIdleDeadline = nil
                self.interaction = .idle
                self.onInteraction(.ended)
                return
            }
        }
    }

    private func cancelWheelIdle() {
        wheelIdleGeneration &+= 1
        wheelIdleTask?.cancel()
        wheelIdleTask = nil
        wheelIdleDeadline = nil
    }

    private func finishInteraction() {
        cancelWheelIdle()
        guard interaction != .idle else { return }
        interaction = .idle
        onInteraction(.ended)
    }

    private func stopObservingFrame() {
        if let frameObservation {
            NotificationCenter.default.removeObserver(frameObservation)
            self.frameObservation = nil
        }
        if enabledFrameNotifications {
            table?.postsFrameChangedNotifications = false
            enabledFrameNotifications = false
        }
    }

    // The paired markers bracket only this viewport's native content. Never
    // search the whole window for its first table, which may be the sidebar.
    private static func table(between before: NSView, and after: NSView) -> NSTableView? {
        var common = before.superview
        while let candidate = common, !after.isDescendant(of: candidate) {
            common = candidate.superview
        }
        guard let common else { return nil }
        var isInside = false
        var reachedEnd = false
        var tables: [NSTableView] = []
        func visit(_ view: NSView) {
            guard !reachedEnd else { return }
            if view === before {
                isInside = true
                return
            }
            if view === after {
                reachedEnd = true
                return
            }
            if let table = view as? NSTableView {
                if isInside { tables.append(table) }
                return
            }
            for child in view.subviews { visit(child) }
        }
        visit(common)
        return reachedEnd && tables.count == 1 ? tables[0] : nil
    }
}

struct WorkbenchTableLifecycleMarker: NSViewRepresentable {
    let lifecycle: WorkbenchNativeTableLifecycle
    let edge: WorkbenchNativeTableLifecycle.Edge
    let onReady: (ObjectIdentifier) -> Void
    let onInteraction: (WorkbenchDataScrollTransition) -> Void

    func makeNSView(context: Context) -> WorkbenchTableLifecycleMarkerView {
        let view = WorkbenchTableLifecycleMarkerView()
        view.setAccessibilityElement(false)
        view.lifecycle = lifecycle
        return view
    }

    func updateNSView(_ nsView: WorkbenchTableLifecycleMarkerView, context: Context) {
        lifecycle.attach(nsView, edge: edge, onReady: onReady, onInteraction: onInteraction)
    }

    static func dismantleNSView(_ nsView: WorkbenchTableLifecycleMarkerView, coordinator: ()) {
        nsView.lifecycle?.detach(nsView)
    }
}

final class WorkbenchTableLifecycleMarkerView: NSView {
    weak var lifecycle: WorkbenchNativeTableLifecycle?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        lifecycle?.scheduleInspection()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        lifecycle?.scheduleInspection()
    }

    override func layout() {
        super.layout()
        lifecycle?.scheduleInspection()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
