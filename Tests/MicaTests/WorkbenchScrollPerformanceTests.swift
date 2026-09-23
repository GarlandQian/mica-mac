import AppKit
import Foundation
import MicaCore
import QuartzCore
import SwiftUI
import XCTest
@testable import Mica

/// Opt-in native interaction measurement. This deliberately measures AppKit
/// delivery and main-actor scheduling, not projection-only speed or display FPS.
@MainActor
final class WorkbenchScrollPerformanceTests: XCTestCase {
    func testOfflineProductionPageScrolling() async throws {
        let output = try outputDirectory()
        let environment = ProcessInfo.processInfo.environment
        let requested = environment["MICA_SCROLL_DESTINATIONS"] ?? "all"
        let destinations = requested == "all" ? WorkbenchDestination.sidebarCases
            : requested.split(separator: ",").compactMap { WorkbenchDestination(rawValue: String($0)) }
        XCTAssertFalse(destinations.isEmpty)
        let sampleCount = min(max(Int(environment["MICA_SCROLL_SAMPLES"] ?? "180") ?? 180, 60), 600)
        let previousApplication = NSWorkspace.shared.frontmostApplication
        let previousAppearance = NSApplication.shared.appearance
        let previousLanguage = MicaStrings.resolvedLanguageCode
        defer {
            NSApplication.shared.appearance = previousAppearance
            Bundle.setMicaLocalizationLanguage(previousLanguage)
            previousApplication?.activate()
        }
        NSApplication.shared.finishLaunching()
        let fixtureFrames = ScrollPerformanceFrames()
        var measurements: [ScrollPerformanceCase] = []
        for destination in destinations {
            for mode in ScrollPerformanceMode.allCases {
                measurements += try await measurePage(
                    destination, mode: mode, frames: fixtureFrames, sampleCount: sampleCount
                )
            }
        }
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        let report = ScrollPerformanceReport(
            label: environment["MICA_SCROLL_LABEL"] ?? "current",
            generatedAt: Date(), operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            buildConfiguration: configuration,
            requestedTickHz: 60, refreshHz: 10, samplesPerSurface: sampleCount,
            fixtureCounts: ["connections": 1_000, "groups": 36, "nodesPerGroup": 500,
                            "rules": 3_000, "sources": 500, "logs": 2_000, "controllers": 40],
            limitations: [
                "Own NSWindow with production WorkbenchWorkspaceView, SwiftUI Canvas, Lists and Tables; application session lifecycle and sidebar are not mounted.",
                "Discrete native mouse-wheel events are delivered directly to each fixture-owned NSScrollView with public CGEvent/NSEvent APIs. Gesture phases and trackpad inertia are not simulated: a synthetic began event alone enters AppKit's nested tracking loop. No global input, controller, credentials, or screen capture is used.",
                "Surfaces rejecting wheel input use public NSClipView.scroll(to:) and reflectScrolledClipView; their inputMode is programmatic-viewport, not a user gesture.",
                "Native live-scroll begin/update/end counts are recorded without synthesizing notifications. Unphased wheels can have updates without begin/end; these exercise the production idle-deadline path. Full touchpad gestures remain outside this measurement.",
                "Main-actor tick intervals and requested-deadline lateness are scheduling measurements, not display-link frames. >16.7/33.3 ms counters are long tick intervals, not dropped frames or FPS.",
                "Layout/commit samples force owned-window layout, displayIfNeeded and CATransaction.flush; they measure CPU submission cost, not compositor/display completion.",
                "Refreshing mode publishes prebuilt changing offline catalogs at up to 10 Hz, including hidden-page domains. It is a repeatable stress workload, not a claim about production refresh rates or network decoding.",
                "Test-host scheduling, debug builds, window occlusion and other machine activity affect results. Compare the same configuration, fixture and machine across revisions.",
            ], cases: measurements
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: output.appendingPathComponent("scroll-performance.json"), options: .atomic)
        try report.markdown.write(to: output.appendingPathComponent("scroll-performance.md"), atomically: true, encoding: .utf8)
        print(report.markdown)
    }

    private func outputDirectory() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["MICA_SCROLL_OUTPUT_DIR"], !path.isEmpty else {
            throw XCTSkip("Set MICA_SCROLL_OUTPUT_DIR under tmp/codex to measure offline native scrolling.")
        }
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let scratch = repository.appendingPathComponent("tmp/codex", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let output = URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard output.path.hasPrefix(scratch.path + "/") else { throw ScrollPerformanceFailure.outputOutsideScratch }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        return output
    }

    private func measurePage(
        _ destination: WorkbenchDestination, mode: ScrollPerformanceMode,
        frames: ScrollPerformanceFrames, sampleCount: Int
    ) async throws -> [ScrollPerformanceCase] {
        let suite = "Mica.WorkbenchScrollPerformanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(AppLanguage.english.rawValue, forKey: AppPreferencesStore.languageKey)
        defaults.set(AppAppearance.dark.rawValue, forKey: AppPreferencesStore.appearanceKey)
        let model = frames.makeModel(defaults: defaults)
        let workspace = WorkbenchWorkspaceStore(defaults: defaults)
        let preferences = OverviewPreferencesStore(defaults: defaults)
        let runtime = OverviewWindowRuntime()
        let size = CGSize(width: 960, height: 600)
        let root = ScrollPerformanceRoot(destination: destination)
            .environment(model)
            .environment(workspace)
            .environment(preferences)
            .environment(runtime)
            .environmentObject(AppPreferencesStore(defaults: defaults))
            .environment(\.micaAppLanguage, .english)
            .environment(\.locale, AppLanguage.english.resolvedLocale)
            .environment(\.colorScheme, .dark)
            .environment(\.controlActiveState, .active)
            .frame(width: size.width, height: size.height)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Mica Offline Scroll Measurement — \(destination.rawValue)"
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
            runtime.registry.clear()
        }
        for _ in 0..<40 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
        assertOffline(model)
        let scrollViews = nativeScrollViews(in: host).filter { scroll in
            !scroll.isHidden && scroll.window === window
                && scroll.contentView.bounds.height >= 80
                && scroll.contentView.bounds.width >= 100
                && (scroll.documentView?.bounds.height ?? 0) > scroll.contentView.bounds.height + 12
        }.sorted {
            let first = $0.convert($0.bounds, to: host), second = $1.convert($1.bounds, to: host)
            return first.minX == second.minX ? first.minY < second.minY : first.minX < second.minX
        }
        if scrollViews.isEmpty {
            return [ScrollPerformanceCase.unscrollable(destination: destination.rawValue, mode: mode.rawValue)]
        }
        var result: [ScrollPerformanceCase] = []
        for (index, scroll) in scrollViews.enumerated() {
            let measured = try await measureSurface(
                scroll, surfaceIndex: index, host: host, window: window, model: model,
                destination: destination, mode: mode, frames: frames, sampleCount: sampleCount
            )
            result.append(measured)
            XCTAssertGreaterThan(measured.offsetRange, 1,
                                 "\(destination.rawValue)/\(index): the recorded input mode must move the actual production scroll view.")
            assertOffline(model)
        }
        return result
    }

    private func measureSurface(
        _ scroll: NSScrollView, surfaceIndex: Int, host: NSView, window: NSWindow,
        model: AppModel, destination: WorkbenchDestination, mode: ScrollPerformanceMode,
        frames: ScrollPerformanceFrames, sampleCount: Int
    ) async throws -> ScrollPerformanceCase {
        let initialOrigin = scroll.contentView.bounds.origin
        scroll.scrollWheel(with: try wheelEvent(delta: -24))
        try await Task.sleep(for: .milliseconds(50))
        var acceptsWheel = abs(scroll.contentView.bounds.origin.y - initialOrigin.y) > 0.1
        if !acceptsWheel {
            scroll.scrollWheel(with: try wheelEvent(delta: 24))
            try await Task.sleep(for: .milliseconds(50))
            acceptsWheel = abs(scroll.contentView.bounds.origin.y - initialOrigin.y) > 0.1
        }
        let inputMode = acceptsWheel ? "native-wheel" : "programmatic-viewport"
        scroll.contentView.scroll(to: initialOrigin)
        scroll.reflectScrolledClipView(scroll.contentView)
        let phases = ScrollPerformancePhaseCounters(scroll: scroll)
        defer { phases.stopObserving() }
        let period = 1.0 / 60.0
        var intervals: [Double] = [], lateness: [Double] = [], delivery: [Double] = []
        var commits: [Double] = [], publication: [Double] = [], offsets: [Double] = []
        var changedOffsetCount = 0, refreshCount = 0, missedDeadlines = 0
        let firstTick = CACurrentMediaTime()
        var nextDeadline = firstTick + period
        var lastTick: Double?
        var nextRefresh = firstTick
        var previousOffset = Double(scroll.contentView.bounds.origin.y)
        var direction: Int32 = -1
        for sample in 0..<sampleCount {
            let remaining = nextDeadline - CACurrentMediaTime()
            if remaining > 0 { try await Task.sleep(for: .seconds(remaining)) }
            let arrived = CACurrentMediaTime()
            lateness.append(max(0, arrived - nextDeadline) * 1_000)
            if let lastTick { intervals.append((arrived - lastTick) * 1_000) }
            lastTick = arrived

            if sample > 0, sample.isMultiple(of: 45) { direction *= -1 }
            let event = try wheelEvent(delta: direction * 24)
            let deliveryStart = CACurrentMediaTime()
            if acceptsWheel {
                scroll.scrollWheel(with: event)
            } else {
                let maximum = max((scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height, 0)
                let y = min(max(scroll.contentView.bounds.origin.y - CGFloat(direction) * 24, 0), maximum)
                scroll.contentView.scroll(to: CGPoint(x: scroll.contentView.bounds.origin.x, y: y))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            delivery.append((CACurrentMediaTime() - deliveryStart) * 1_000)

            if mode == .refreshing, arrived >= nextRefresh {
                let started = CACurrentMediaTime()
                frames.publish(frame: refreshCount, to: model)
                publication.append((CACurrentMediaTime() - started) * 1_000)
                refreshCount += 1
                nextRefresh = arrived + 0.1
            }
            let commitStart = CACurrentMediaTime()
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            CATransaction.flush()
            commits.append((CACurrentMediaTime() - commitStart) * 1_000)
            let offset = Double(scroll.contentView.bounds.origin.y)
            offsets.append(offset)
            if abs(offset - previousOffset) > 0.1 { changedOffsetCount += 1 }
            previousOffset = offset

            nextDeadline += period
            let finished = CACurrentMediaTime()
            if nextDeadline < finished {
                let skipped = Int((finished - nextDeadline) / period) + 1
                missedDeadlines += skipped
                nextDeadline += Double(skipped) * period
            }
        }
        scroll.scrollWheel(with: try wheelEvent(delta: 0))
        try await Task.sleep(for: .milliseconds(120))
        return ScrollPerformanceCase(
            destination: destination.rawValue, mode: mode.rawValue, surfaceIndex: surfaceIndex,
            surfaceKind: scroll.documentView.map { String(describing: type(of: $0)) } ?? "unknown",
            status: changedOffsetCount > 0 ? "measured" : "not measured: native input and viewport fallback did not move this surface",
            inputMode: inputMode, sampleCount: sampleCount,
            viewportHeight: Double(scroll.contentView.bounds.height),
            documentHeight: Double(scroll.documentView?.bounds.height ?? 0),
            offsetRange: (offsets.max() ?? 0) - (offsets.min() ?? 0),
            changedOffsetCount: changedOffsetCount, refreshCount: refreshCount,
            liveScrollBegins: phases.begins, liveScrollUpdates: phases.updates, liveScrollEnds: phases.ends,
            missedSchedulingDeadlines: missedDeadlines,
            elapsedMilliseconds: (CACurrentMediaTime() - firstTick) * 1_000,
            tickInterval: ScrollPerformanceDistribution(intervals),
            deadlineLateness: ScrollPerformanceDistribution(lateness),
            wheelDelivery: ScrollPerformanceDistribution(delivery),
            layoutAndCommit: ScrollPerformanceDistribution(commits),
            fixturePublication: ScrollPerformanceDistribution(publication)
        )
    }

    private func wheelEvent(delta: Int32) throws -> NSEvent {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                         wheel1: delta, wheel2: 0, wheel3: 0))
        // An isolated event is a mouse-wheel tick, not the beginning of a
        // trackpad gesture. AppKit's gesture tracking consumes an event queue
        // synchronously; faking only began would block the test's MainActor.
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 0)
        return try XCTUnwrap(NSEvent(cgEvent: event))
    }

    private func nativeScrollViews(in view: NSView) -> [NSScrollView] {
        let current = (view as? NSScrollView).map { [$0] } ?? []
        return current + view.subviews.flatMap { nativeScrollViews(in: $0) }
    }

    private func assertOffline(_ model: AppModel) {
        XCTAssertEqual(model.mainWindowCount, 0)
        XCTAssertFalse(model.didLoadPersistedState)
        XCTAssertTrue(model.liveSessionTasks.activeSlots.isEmpty)
        XCTAssertNil(model.liveSessionRuntime)
        XCTAssertNil(model.sessionMihomoClient)
        XCTAssertNil(model.sessionSurgeClient)
    }
}

private struct ScrollPerformanceRoot: View {
    @State var destination: WorkbenchDestination
    var body: some View {
        VStack(spacing: 0) {
            WorkbenchWorkspaceView(destination: $destination, onAddController: {}, onEditController: { _ in })
            WorkbenchBottomChrome()
        }
        .background(MicaTheme.canvas)
    }
}

private enum ScrollPerformanceMode: String, CaseIterable { case stationary, refreshing }
private enum ScrollPerformanceFailure: Error { case outputOutsideScratch, unexpectedRemoteOperation }

@MainActor
private final class ScrollPerformancePhaseCounters {
    private(set) var begins = 0
    private(set) var updates = 0
    private(set) var ends = 0
    private var observations: [NSObjectProtocol] = []

    init(scroll: NSScrollView) {
        observations.append(NotificationCenter.default.addObserver(
            forName: NSScrollView.didLiveScrollNotification, object: scroll, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updates += 1 }
        })
        observations.append(NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification, object: scroll, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.begins += 1 }
        })
        observations.append(NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification, object: scroll, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.ends += 1 }
        })
    }

    func stopObserving() {
        observations.forEach(NotificationCenter.default.removeObserver)
        observations.removeAll()
    }
}

private struct ScrollPerformanceDistribution: Codable {
    let count: Int
    let p50Milliseconds: Double
    let p95Milliseconds: Double
    let maximumMilliseconds: Double
    let above16_7Milliseconds: Int
    let above33_3Milliseconds: Int

    init(_ samples: [Double]) {
        let sorted = samples.sorted()
        count = sorted.count
        p50Milliseconds = sorted.isEmpty ? 0 : sorted[min(Int(Double(sorted.count - 1) * 0.5), sorted.count - 1)]
        p95Milliseconds = sorted.isEmpty ? 0 : sorted[min(Int(ceil(Double(sorted.count) * 0.95)) - 1, sorted.count - 1)]
        maximumMilliseconds = sorted.last ?? 0
        above16_7Milliseconds = sorted.filter { $0 > 16.7 }.count
        above33_3Milliseconds = sorted.filter { $0 > 33.3 }.count
    }
}

private struct ScrollPerformanceCase: Codable {
    let destination: String
    let mode: String
    let surfaceIndex: Int
    let surfaceKind: String
    let status: String
    let inputMode: String
    let sampleCount: Int
    let viewportHeight: Double
    let documentHeight: Double
    let offsetRange: Double
    let changedOffsetCount: Int
    let refreshCount: Int
    let liveScrollBegins: Int
    let liveScrollUpdates: Int
    let liveScrollEnds: Int
    let missedSchedulingDeadlines: Int
    let elapsedMilliseconds: Double
    let tickInterval: ScrollPerformanceDistribution
    let deadlineLateness: ScrollPerformanceDistribution
    let wheelDelivery: ScrollPerformanceDistribution
    let layoutAndCommit: ScrollPerformanceDistribution
    let fixturePublication: ScrollPerformanceDistribution

    static func unscrollable(destination: String, mode: String) -> Self {
        Self(destination: destination, mode: mode, surfaceIndex: 0, surfaceKind: "none",
             status: "no overflowing native vertical scroll surface in this fixture", inputMode: "none", sampleCount: 0,
             viewportHeight: 0, documentHeight: 0, offsetRange: 0, changedOffsetCount: 0,
             refreshCount: 0, liveScrollBegins: 0, liveScrollUpdates: 0, liveScrollEnds: 0,
             missedSchedulingDeadlines: 0, elapsedMilliseconds: 0,
             tickInterval: .init([]), deadlineLateness: .init([]), wheelDelivery: .init([]),
             layoutAndCommit: .init([]), fixturePublication: .init([]))
    }
}

private struct ScrollPerformanceReport: Encodable {
    let schemaVersion = 1
    let label: String
    let generatedAt: Date
    let operatingSystem: String
    let buildConfiguration: String
    let requestedTickHz: Int
    let refreshHz: Int
    let samplesPerSurface: Int
    let fixtureCounts: [String: Int]
    let limitations: [String]
    let cases: [ScrollPerformanceCase]

    var markdown: String {
        var lines = ["# Native Workbench scroll measurement", "",
                     "Label: \(label); build: \(buildConfiguration); OS: \(operatingSystem).",
                     "Tick interval is main-actor scheduling, not display FPS. All durations below are milliseconds.", "",
                     "| Page / surface | Mode / input | Moved ticks | Tick p50 / p95 / max | Tick >16.7 / >33.3 | Deadline p95 | Delivery p95 | Layout/commit p95 | Publications | Live begin / update / end |",
                     "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
        func decimal(_ value: Double) -> String { String(format: "%.2f", value) }
        for entry in cases {
            guard entry.status == "measured" else {
                lines.append("| \(entry.destination) / \(entry.surfaceIndex) | \(entry.mode) / \(entry.inputMode) | — | \(entry.status) | — | — | — | — | — | \(entry.liveScrollBegins) / \(entry.liveScrollUpdates) / \(entry.liveScrollEnds) |")
                continue
            }
            let tick = entry.tickInterval
            lines.append("| \(entry.destination) / \(entry.surfaceIndex) | \(entry.mode) / \(entry.inputMode) | \(entry.changedOffsetCount) / \(entry.sampleCount) | \(decimal(tick.p50Milliseconds)) / \(decimal(tick.p95Milliseconds)) / \(decimal(tick.maximumMilliseconds)) | \(tick.above16_7Milliseconds) / \(tick.above33_3Milliseconds) | \(decimal(entry.deadlineLateness.p95Milliseconds)) | \(decimal(entry.wheelDelivery.p95Milliseconds)) | \(decimal(entry.layoutAndCommit.p95Milliseconds)) | \(entry.refreshCount) | \(entry.liveScrollBegins) / \(entry.liveScrollUpdates) / \(entry.liveScrollEnds) |")
        }
        lines += ["", "Limitations:", ""] + limitations.map { "- " + $0 }
        return lines.joined(separator: "\n") + "\n"
    }
}
