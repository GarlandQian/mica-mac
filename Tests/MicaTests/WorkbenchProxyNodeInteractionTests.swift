import AppKit
import SwiftUI
import XCTest
@testable import Mica

@MainActor
final class WorkbenchProxyNodeInteractionTests: XCTestCase {
    func testNodeBodyOnlyInspects() async throws {
        let fixture = makeFixture()
        defer { tearDown(fixture) }
        try await clickInspectionBody(in: fixture)

        XCTAssertEqual(fixture.calls.inspections, 1)
        XCTAssertEqual(fixture.calls.selections, 0)
        XCTAssertEqual(fixture.calls.tests, 0)
    }

    func testExplicitSwitchAndTestHaveIndependentActions() async throws {
        let fixture = makeFixture()
        defer { tearDown(fixture) }
        let controls = try await controls(in: fixture)
        let select = try XCTUnwrap(controls.select)
        let test = controls.test

        XCTAssertTrue(select.isEnabled)
        try await press(select)
        XCTAssertEqual(fixture.calls.selections, 1)
        XCTAssertEqual(fixture.calls.inspections, 0)
        XCTAssertEqual(fixture.calls.tests, 0)

        XCTAssertTrue(test.isEnabled)
        try await press(test)
        XCTAssertEqual(fixture.calls.tests, 1)
        XCTAssertEqual(fixture.calls.selections, 1)
        XCTAssertEqual(fixture.calls.inspections, 0)
    }

    func testCurrentNodeCannotBeSelectedAgainButCanBeInspected() async throws {
        let fixture = makeFixture(isControllerSelected: true)
        defer { tearDown(fixture) }
        let controls = try await controls(in: fixture)
        let select = try XCTUnwrap(controls.select)

        XCTAssertFalse(select.isEnabled)
        select.performClick(nil)
        try await clickInspectionBody(in: fixture)

        XCTAssertEqual(fixture.calls.inspections, 1)
        XCTAssertEqual(fixture.calls.selections, 0)
        XCTAssertEqual(fixture.calls.tests, 0)
    }

    func testNonSelectableMemberOmitsSwitchButKeepsInspectionAndTest() async throws {
        let fixture = makeFixture(canSelect: false)
        defer { tearDown(fixture) }
        let controls = try await controls(in: fixture)

        XCTAssertNil(controls.select)
        try await clickInspectionBody(in: fixture)
        try await press(controls.test)

        XCTAssertEqual(fixture.calls.inspections, 1)
        XCTAssertEqual(fixture.calls.tests, 1)
        XCTAssertEqual(fixture.calls.selections, 0)
    }

    func testPausedCommandsDisableMutationsButNotInspection() async throws {
        let fixture = makeFixture(commandsEnabled: false)
        defer { tearDown(fixture) }
        let controls = try await controls(in: fixture)
        let select = try XCTUnwrap(controls.select)
        let test = controls.test

        XCTAssertFalse(select.isEnabled)
        XCTAssertFalse(test.isEnabled)
        select.performClick(nil)
        test.performClick(nil)
        try await clickInspectionBody(in: fixture)

        XCTAssertEqual(fixture.calls.inspections, 1)
        XCTAssertEqual(fixture.calls.selections, 0)
        XCTAssertEqual(fixture.calls.tests, 0)
    }

    private func makeFixture(
        isControllerSelected: Bool = false,
        commandsEnabled: Bool = true,
        canSelect: Bool = true
    ) -> NodeInteractionFixture {
        _ = NSApplication.shared
        let previousApplication = NSWorkspace.shared.frontmostApplication
        NSApplication.shared.finishLaunching()
        let calls = NodeInteractionCalls()
        let member = ProxyNodeRowProjection(
            id: "offline-member:0",
            name: "Offline node",
            occurrence: 0,
            type: "Shadowsocks",
            providerName: nil,
            transportNames: [],
            delay: 24,
            latencyFraction: nil,
            alive: true,
            health: .healthy,
            usageRank: nil,
            isControllerSelected: isControllerSelected
        )
        let root = ProxyPolicyNodeTile(
            member: member,
            scrollInteractionTracker: ProxyScrollInteractionTracker(),
            isInspected: false,
            isHighlighted: false,
            commandsEnabled: commandsEnabled,
            canSelect: canSelect,
            canTest: true,
            isSwitching: false,
            isMeasuring: false,
            onSelect: { calls.selections += 1 },
            onInspect: { calls.inspections += 1 },
            onTest: { calls.tests += 1 }
        )
        .padding(12)
        .frame(width: 440, height: 120)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 440, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
        host.layoutSubtreeIfNeeded()
        return NodeInteractionFixture(
            host: host,
            window: window,
            canSelect: canSelect,
            previousApplication: previousApplication,
            calls: calls
        )
    }

    private func tearDown(_ fixture: NodeInteractionFixture) {
        fixture.window.orderOut(nil)
        fixture.window.contentView = nil
        fixture.window.close()
        fixture.previousApplication?.activate()
    }

    private func press(_ button: NSButton) async throws {
        button.performClick(nil)
        try await Task.sleep(for: .milliseconds(40))
    }

    private func controls(in fixture: NodeInteractionFixture) async throws -> NodeNativeControls {
        let expectedCount = fixture.canSelect ? 2 : 1
        for _ in 0..<30 {
            fixture.host.layoutSubtreeIfNeeded()
            fixture.window.displayIfNeeded()
            let buttons = nativeButtons(in: fixture)
            if buttons.count == expectedCount {
                for button in buttons {
                    let frame = button.convert(button.bounds, to: fixture.host)
                    XCTAssertGreaterThan(frame.width, 0)
                    XCTAssertGreaterThan(frame.height, 0)
                    XCTAssertTrue(fixture.host.bounds.contains(frame))
                }
                if buttons.count == 2 {
                    let first = buttons[0].convert(buttons[0].bounds, to: fixture.host)
                    let last = buttons[1].convert(buttons[1].bounds, to: fixture.host)
                    XCTAssertLessThanOrEqual(first.maxX, last.minX)
                }
                return NodeNativeControls(select: fixture.canSelect ? buttons.first : nil,
                                          test: try XCTUnwrap(buttons.last))
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Expected \(expectedCount) native action buttons, found \(nativeButtons(in: fixture).count).")
        throw NodeInteractionError.missingControls
    }

    private func nativeButtons(in fixture: NodeInteractionFixture) -> [NSButton] {
        var pending: [NSView] = [fixture.host]
        var buttons: [NSButton] = []
        while let candidate = pending.popLast() {
            if let button = candidate as? NSButton { buttons.append(button) }
            pending.append(contentsOf: candidate.subviews)
        }
        // The production tile lays out the explicit switch then the test
        // control from left to right. Resolve their actual native frames,
        // not SwiftUI's private backing class names or guessed coordinates.
        return buttons.sorted {
            $0.convert($0.bounds, to: fixture.host).minX
                < $1.convert($1.bounds, to: fixture.host).minX
        }
    }

    private func clickInspectionBody(in fixture: NodeInteractionFixture) async throws {
        let controls = try await controls(in: fixture)
        let firstControl = controls.select ?? controls.test
        let controlFrame = firstControl.convert(firstControl.bounds, to: fixture.host)
        let point = CGPoint(x: controlFrame.minX / 2, y: controlFrame.midY)
        let hit = try XCTUnwrap(fixture.host.hitTest(point))
        XCTAssertFalse(hit is NSButton)
        let location = fixture.host.convert(point, to: nil)
        // Deliver only to this isolated fixture window. This presses the
        // SwiftUI plain button through native mouse dispatch without posting
        // global input or directly invoking its production callback.
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: fixture.window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
            ))
            fixture.window.sendEvent(event)
        }
        try await Task.sleep(for: .milliseconds(40))
    }
}

@MainActor
private struct NodeInteractionFixture {
    let host: NSView
    let window: NSWindow
    let canSelect: Bool
    let previousApplication: NSRunningApplication?
    let calls: NodeInteractionCalls
}

@MainActor
private struct NodeNativeControls {
    let select: NSButton?
    let test: NSButton
}

private enum NodeInteractionError: Error {
    case missingControls
}

@MainActor
private final class NodeInteractionCalls {
    var inspections = 0
    var selections = 0
    var tests = 0
}
