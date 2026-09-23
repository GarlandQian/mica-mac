import AppKit
import Foundation
import Observation
import SwiftUI
import Testing
import XCTest
@testable import Mica

struct WorkbenchTableScrollDeliveryTests {
    @Test func initialRequestWinsOverRestorationAndUnchangedRequestsDoNotRepeat() {
        let generation = UUID()
        let request = WorkbenchDataScrollRequest(id: "newest")
        let delivery = WorkbenchDataScrollDelivery(generation: generation, request: request, restorationID: "older")
        var state = WorkbenchDataScrollDeliveryState()
        #expect(state.target(for: delivery, isUserScrolling: false) == "newest")
        #expect(state.target(for: delivery, isUserScrolling: true) == nil)
        #expect(state.target(for: delivery, isUserScrolling: false) == nil)

        let repeatedTarget = WorkbenchDataScrollDelivery(generation: generation, request: WorkbenchDataScrollRequest(id: "newest"), restorationID: "older")
        #expect(state.target(for: repeatedTarget, isUserScrolling: false) == "newest")
    }

    @Test func restorationCannotInterruptUserScrollingOrReplayAfterItEnds() {
        let generation = UUID()
        var state = WorkbenchDataScrollDeliveryState()
        let initial = WorkbenchDataScrollDelivery(generation: generation, request: nil, restorationID: "first")
        #expect(state.target(for: initial, isUserScrolling: false) == "first")
        let changed = WorkbenchDataScrollDelivery(generation: generation, request: nil, restorationID: "second")
        #expect(state.target(for: changed, isUserScrolling: true) == nil)
        #expect(state.target(for: changed, isUserScrolling: false) == nil)
    }
}

@MainActor
final class WorkbenchTableScrollTests: XCTestCase {
    func testInitialRequestReachesLastNativeTableRowAndRedrawDoesNotRepeatIt() async throws {
        let driver = TableScrollFixtureDriver(request: WorkbenchDataScrollRequest(id: "row-39"))
        let fixture = makeFixture(driver: driver)
        defer { tearDown(fixture) }
        let table = try await waitForTable(in: fixture.host)
        try await waitForVisibleRow(39, table: table, host: fixture.host, context: "initial request")

        table.scrollRowToVisible(0)
        driver.redraw += 1
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(NSLocationInRange(0, table.rows(in: table.visibleRect)))
        XCTAssertFalse(NSLocationInRange(39, table.rows(in: table.visibleRect)))

        driver.request = WorkbenchDataScrollRequest(id: "row-39")
        try await waitForVisibleRow(39, table: table, host: fixture.host, context: "repeated request")
    }

    func testInitialRestorationScrollsWithoutAnExplicitRequest() async throws {
        let driver = TableScrollFixtureDriver(restorationID: "row-39")
        let fixture = makeFixture(driver: driver)
        defer { tearDown(fixture) }
        let table = try await waitForTable(in: fixture.host)
        try await waitForVisibleRow(39, table: table, host: fixture.host, context: "initial restoration")
    }

    func testAppendingRowsAndRequestingNewLastRowInSameUpdateIsNotDropped() async throws {
        let driver = TableScrollFixtureDriver()
        let fixture = makeFixture(driver: driver)
        defer { tearDown(fixture) }
        let table = try await waitForTable(in: fixture.host)

        driver.rowCount = 80
        driver.request = WorkbenchDataScrollRequest(id: "row-79")
        try await waitForVisibleRow(79, table: table, host: fixture.host, context: "appended row request")
        XCTAssertEqual(table.numberOfRows, 80)
    }

    func testTableScopeDoesNotScrollAnAdjacentNativeTable() async throws {
        let driver = TableScrollFixtureDriver(request: WorkbenchDataScrollRequest(id: "row-39"))
        let fixture = makeFixture(driver: driver, includesSibling: true)
        defer { tearDown(fixture) }
        _ = try await waitForTable(in: fixture.host)
        let tables = nativeTables(in: fixture.host)
        XCTAssertEqual(tables.count, 2)
        let sibling = try XCTUnwrap(tables.first)
        let target = try XCTUnwrap(tables.last)
        try await waitForVisibleRow(39, table: target, host: fixture.host, context: "scoped table")
        XCTAssertTrue(NSLocationInRange(0, sibling.rows(in: sibling.visibleRect)))
        XCTAssertFalse(NSLocationInRange(39, sibling.rows(in: sibling.visibleRect)))
        let siblingScroll = try XCTUnwrap(sibling.enclosingScrollView)
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: siblingScroll)
        XCTAssertEqual(driver.scrollBegins, 0)
    }

    func testNativeLiveScrollNotificationsReachExistingCallbacksOnce() async throws {
        let driver = TableScrollFixtureDriver(request: WorkbenchDataScrollRequest(id: "row-39"))
        let fixture = makeFixture(driver: driver)
        defer { tearDown(fixture) }
        let table = try await waitForTable(in: fixture.host)
        try await waitForVisibleRow(39, table: table, host: fixture.host, context: "native interaction setup")
        let scrollView = try XCTUnwrap(table.enclosingScrollView)
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        XCTAssertEqual(driver.scrollBegins, 1)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        XCTAssertEqual(driver.scrollEnds, 1)
    }

    func testNativeUserScrollCommitsTheActuallyVisibleAnchor() async throws {
        let driver = TableScrollFixtureDriver(request: WorkbenchDataScrollRequest(id: "row-39"))
        let fixture = makeFixture(driver: driver)
        defer { tearDown(fixture) }
        let table = try await waitForTable(in: fixture.host)
        try await waitForVisibleRow(39, table: table, host: fixture.host, context: "anchor setup")
        let scrollView = try XCTUnwrap(table.enclosingScrollView)
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        table.scrollRowToVisible(0)
        try await waitForVisibleRow(0, table: table, host: fixture.host, context: "user scroll")
        await Task.yield()
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        let lastVisible = min(NSMaxRange(table.rows(in: table.visibleRect)) - 1, table.numberOfRows - 1)
        XCTAssertEqual(driver.lastCommittedAnchor, "row-\(lastVisible)")
    }

    private func makeFixture(driver: TableScrollFixtureDriver, includesSibling: Bool = false) -> (host: NSView, window: NSWindow) {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: TableScrollFixture(driver: driver, includesSibling: includesSibling))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: includesSibling ? 640 : 440, height: 260),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        return (host, window)
    }

    private func tearDown(_ fixture: (host: NSView, window: NSWindow)) {
        fixture.window.orderOut(nil)
        fixture.window.contentView = nil
        fixture.window.close()
    }

    private func waitForTable(in host: NSView) async throws -> NSTableView {
        for _ in 0..<30 {
            host.layoutSubtreeIfNeeded()
            if let table = nativeTable(in: host), table.numberOfRows == 40 {
                return table
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return try XCTUnwrap(nativeTable(in: host), "The offline SwiftUI Table did not attach.")
    }

    private func waitForVisibleRow(_ row: Int, table: NSTableView, host: NSView, context: String) async throws {
        for _ in 0..<30 {
            host.layoutSubtreeIfNeeded()
            if NSLocationInRange(row, table.rows(in: table.visibleRect)) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(NSLocationInRange(row, table.rows(in: table.visibleRect)), "\(context): expected row \(row); visible=\(table.rows(in: table.visibleRect)) rect=\(table.visibleRect) document=\(table.frame) target=\(table.rect(ofRow: row)).")
    }

    private func nativeTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { self.nativeTable(in: $0) }.first
    }

    private func nativeTables(in view: NSView) -> [NSTableView] {
        if let table = view as? NSTableView { return [table] }
        return view.subviews.flatMap { nativeTables(in: $0) }
    }

}

@MainActor
@Observable
private final class TableScrollFixtureDriver {
    var request: WorkbenchDataScrollRequest?
    var restorationID: String?
    var redraw = 0
    var rowCount = 40
    var scrollBegins = 0
    var scrollEnds = 0
    var lastCommittedAnchor: String?

    init(request: WorkbenchDataScrollRequest? = nil, restorationID: String? = nil) {
        self.request = request
        self.restorationID = restorationID
    }
}

private struct TableScrollFixture: View {
    let driver: TableScrollFixtureDriver
    var includesSibling = false
    private var rows: [TableScrollFixtureRow] {
        (0..<driver.rowCount).map { TableScrollFixtureRow(id: "row-\($0)") }
    }
    @State private var generation = UUID()
    @State private var interaction = WorkbenchDataInteractionCoordinator()

    var body: some View {
        HStack(spacing: 0) {
            if includesSibling {
                Table(rows) {
                    TableColumn("Sidebar") { row in Text(verbatim: row.id) }
                }
                .frame(width: 200)
            }
            scrollingTable
        }
        .frame(width: includesSibling ? 640 : 440, height: 260)
    }

    private var scrollingTable: some View {
        WorkbenchDataTableViewport(
            generation: generation,
            restorationID: driver.restorationID,
            request: driver.request,
            anchor: .bottom,
            interaction: interaction,
            rowIndex: { id in rows.firstIndex { $0.id == id } },
            rowID: { index in rows.indices.contains(index) ? rows[index].id : nil },
            onInteractionBegan: { driver.scrollBegins += 1 },
            onInteractionEnded: { driver.scrollEnds += 1 },
            onAnchorCommit: { driver.lastCommittedAnchor = $0 }
        ) {
            Table(rows) {
                TableColumn("Event") { row in
                    Text(verbatim: row.id).frame(height: 36)
                }
            }
            .accessibilityValue(String(driver.redraw))
        }
        .frame(width: 440, height: 260)
    }
}

private struct TableScrollFixtureRow: Identifiable {
    let id: String
}
