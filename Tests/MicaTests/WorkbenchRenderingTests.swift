import AppKit
import Foundation
import MicaCore
import QuartzCore
import SwiftUI
import XCTest
@testable import Mica

@MainActor
final class WorkbenchRenderingTests: XCTestCase {
    func testOfflineWorkbenchAtSupportedWindowSizes() async throws {
        let output = try renderingOutputDirectory()
        let previousApplication = NSWorkspace.shared.frontmostApplication
        defer { previousApplication?.activate() }
        NSApplication.shared.finishLaunching()

        let environment = ProcessInfo.processInfo.environment
        let surface = environment["MICA_RENDER_SURFACE"] == "topology"
            ? RenderingSurface.topology : .workbench
        let topologyDensity = RenderingTopologyDensity(environment["MICA_RENDER_TOPOLOGY_DENSE"])
        let pinsTopologyPath = environment["MICA_RENDER_TOPOLOGY_FOCUS"] == "pinned"
        let requested = environment["MICA_RENDER_DESTINATIONS"] ?? "overview"
        let destinations = surface == .topology ? [.overview] : requested == "all"
            ? WorkbenchDestination.sidebarCases
            : requested.split(separator: ",").compactMap { WorkbenchDestination(rawValue: String($0)) }
        XCTAssertFalse(destinations.isEmpty)
        for destination in destinations {
            for size in [CGSize(width: 820, height: 580), CGSize(width: 1440, height: 900)] {
                for language in [AppLanguage.english, .simplifiedChinese] {
                    for scheme in [ColorScheme.light, .dark] {
                        try await render(
                            destination: destination, surface: surface,
                            topologyDensity: topologyDensity, pinsTopologyPath: pinsTopologyPath,
                            size: size, language: language, scheme: scheme, output: output
                        )
                    }
                }
            }
        }
    }

    private func renderingOutputDirectory() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["MICA_RENDER_OUTPUT_DIR"], !path.isEmpty else {
            throw XCTSkip("Set MICA_RENDER_OUTPUT_DIR under tmp/codex to render offline Workbench screenshots.")
        }
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scratch = repository.appendingPathComponent("tmp/codex", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let output = URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard output.path.hasPrefix(scratch.path + "/") else {
            throw RenderingFailure.outputOutsideScratch
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        return output
    }

    private func render(
        destination: WorkbenchDestination,
        surface: RenderingSurface,
        topologyDensity: RenderingTopologyDensity,
        pinsTopologyPath: Bool,
        size: CGSize,
        language: AppLanguage,
        scheme: ColorScheme,
        output: URL
    ) async throws {
        let suiteName = "Mica.WorkbenchRenderingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let previousAppearance = NSApplication.shared.appearance
        let previousLanguageCode = MicaStrings.resolvedLanguageCode
        defer {
            NSApplication.shared.appearance = previousAppearance
            Bundle.setMicaLocalizationLanguage(previousLanguageCode)
        }
        defaults.set(language.rawValue, forKey: AppPreferencesStore.languageKey)
        defaults.set(scheme == .dark ? AppAppearance.dark.rawValue : AppAppearance.light.rawValue,
                     forKey: AppPreferencesStore.appearanceKey)

        let model = makeFixture(defaults: defaults, language: language, topologyDensity: topologyDensity,
                                destination: destination)
        let workspace = WorkbenchWorkspaceStore(defaults: defaults)
        let showsInspector = ProcessInfo.processInfo.environment["MICA_RENDER_INSPECTOR"] == "1"
        let selectsFirst = ProcessInfo.processInfo.environment["MICA_RENDER_SELECTION"] == "first"
        let requestedNodeFixture = ProcessInfo.processInfo.environment["MICA_RENDER_NODE_DETAILS"] ?? ""
        let nodeDetailsFixture: String? = ["runtime", "ss", "vless"].contains(requestedNodeFixture)
            ? requestedNodeFixture : nil
        let originalSelectedNode = model.policyGroupCatalog.groups.first?.selected
        if selectsFirst, destination == .connections,
           let controllerID = model.selectedRouterID,
           let connection = model.connectionsCatalog.connections.first {
            workspace.stageConnectionNavigation(WorkbenchConnectionNavigationSelection(
                controllerID: controllerID, generation: model.controllerSessionPresentation.generation,
                sourceIndex: 0, reportedConnectionID: connection.id
            ))
        }
        if selectsFirst, destination == .rules,
           let controllerID = model.selectedRouterID,
           let rule = model.rulesCatalog.rules.first {
            workspace.stageRuleNavigation(WorkbenchRuleNavigationSelection(
                controllerID: controllerID, generation: model.controllerSessionPresentation.generation,
                sourceIndex: 0, reportedRuleID: rule.id, type: rule.type, payload: rule.payload
            ))
        }
        if selectsFirst, destination == .sources,
           let row = WorkbenchSourceProjection.rows(from: model.providersCatalog.providers, language: language).first {
            workspace.update(controllerID: model.selectedRouterID, destination: .sources) {
                $0.selectedItemID = row.id
            }
        }
        if selectsFirst, destination == .proxies,
           let controllerID = model.selectedRouterID,
           let group = model.policyGroupCatalog.groups.first,
           let nodeName = group.options.first {
            workspace.stageProxyNavigation(WorkbenchProxyNavigationSelection(
                controllerID: controllerID, generation: model.controllerSessionPresentation.generation,
                groupOccurrenceID: ProxyGroupKey(groupID: group.id, occurrence: 0).rawValue,
                nodeName: nodeName
            ))
        }
        let appPreferences = AppPreferencesStore(defaults: defaults)
        let preferences = OverviewPreferencesStore(defaults: defaults)
        let runtime = OverviewWindowRuntime()
        let root = RenderingRoot(surface: surface, destination: destination, showsInspector: showsInspector)
            .environment(model)
            .environmentObject(appPreferences)
            .environment(workspace)
            .environment(preferences)
            .environment(runtime)
            .environment(\.micaAppLanguage, language)
            .environment(\.locale, language.resolvedLocale)
            .environment(\.colorScheme, scheme)
            .environment(\.controlActiveState, .active)
            .transaction {
                $0.animation = nil
                $0.disablesAnimations = true
            }
            .frame(width: size.width, height: size.height)

        let appearance = try XCTUnwrap(NSAppearance(named: scheme == .dark ? .darkAqua : .aqua))
        NSApplication.shared.appearance = appearance
        let host = NSHostingView(rootView: root)
        host.appearance = appearance
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            // Match SwiftUI's window chrome. A title-only test host gives the
            // native inspector a second toolbar overlay inside its content.
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "Mica"
        window.toolbarStyle = .unifiedCompact
        window.appearance = appearance
        window.contentView = host
        window.setContentSize(size)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
            runtime.registry.clear()
        }

        // The isolated window lets native Lists finish their window-server
        // appearance setup without mounting the production session lifecycle.
        var settledTopologyFrames = 0
        for _ in 0..<(topologyDensity == .stress ? 240 : 80) {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let topologyRuntime = runtime.registry.existingTopologyRuntime(
                controllerID: try XCTUnwrap(model.selectedRouterID),
                generation: model.controllerSession.generation
            )
            if destination != .overview { break }
            if let topologyRuntime, let presentation = topologyRuntime.presentation,
               presentation.request.availableWidth == topologyRuntime.availableWidth {
                settledTopologyFrames += 1
                if settledTopologyFrames >= 4 { break }
            } else {
                settledTopologyFrames = 0
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        if destination == .overview {
            let topologyRuntime = try XCTUnwrap(runtime.registry.existingTopologyRuntime(
                controllerID: try XCTUnwrap(model.selectedRouterID),
                generation: model.controllerSession.generation
            ))
            let presentation = try XCTUnwrap(topologyRuntime.presentation,
                                             "The production topology must finish its offline projection.")
            XCTAssertFalse(presentation.topology.isEmpty)
            XCTAssertGreaterThanOrEqual(settledTopologyFrames, 4,
                                        "Render only the current viewport projection, not a superseded layout.")
            XCTAssertTrue(presentation.layout.size.width.isFinite)
            XCTAssertTrue(presentation.layout.size.height.isFinite)
            if topologyDensity == .stress {
                XCTAssertEqual(presentation.topology.connectionCount, 1_000)
                XCTAssertLessThanOrEqual(presentation.topology.nodes.count, 80,
                                         "The stress fixture must increase crossings, not unbounded node rows.")
                XCTAssertGreaterThanOrEqual(presentation.topology.edges.count, 400)
            }
            if pinsTopologyPath {
                let path = try XCTUnwrap(presentation.topology.paths.first)
                topologyRuntime.interaction.togglePinnedPath(path.id)
                XCTAssertTrue(topologyRuntime.interaction.snapshot.isPinned)
                XCTAssertFalse(topologyRuntime.interaction.snapshot.highlight.nodeIDs.isEmpty)
            }
        }
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(350))
        if surface == .topology, let current = runtime.registry.existingTopologyRuntime(
            controllerID: try XCTUnwrap(model.selectedRouterID), generation: model.controllerSession.generation
        ), let presentation = current.presentation {
            print("Topology viewport \(Int(size.width))x\(Int(size.height)): request=\(presentation.request.availableWidth)/\(presentation.request.minimumFlowHeight), width=\(current.availableWidth), layout=\(presentation.layout.size), bands=\(presentation.layout.renderBands.count)")
        }

        XCTAssertEqual(model.mainWindowCount, 0)
        XCTAssertFalse(model.didLoadPersistedState)
        XCTAssertTrue(model.liveSessionTasks.activeSlots.isEmpty)
        XCTAssertNil(model.liveSessionRuntime)
        XCTAssertNil(model.sessionMihomoClient)
        XCTAssertNil(model.sessionSurgeClient)
        XCTAssertTrue(window.isVisible)
        if selectsFirst, destination == .proxies {
            XCTAssertEqual(model.policyGroupCatalog.groups.first?.selected, originalSelectedNode,
                           "Inspecting an individual node must not switch the active node.")
            let proxyWorkspace = workspace.workspace(controllerID: model.selectedRouterID, destination: .proxies)
            XCTAssertNotNil(proxyWorkspace.inspectedProxyMemberID,
                            "The requested individual node must show its inline details.")
        }
        if selectsFirst, destination == .rules {
            guard case .rule = workspace.inspectorSelection else {
                return XCTFail("The selected rule must be resolved in the inspector.")
            }
        }
        if selectsFirst, destination == .sources {
            guard case .source = workspace.inspectorSelection else {
                return XCTFail("The selected source must be resolved in the inspector.")
            }
        }

        let frameView = try XCTUnwrap(window.contentView?.superview)
        frameView.appearance = appearance
        assertFiniteLayout(frameView, maximumSplitHeight: frameView.bounds.height)
        XCTAssertEqual(host.bounds.width, size.width, accuracy: 1, destination.rawValue)
        XCTAssertEqual(window.contentLayoutRect.width, size.width, accuracy: 1, destination.rawValue)
        XCTAssertEqual(window.contentLayoutRect.height, size.height, accuracy: 1, destination.rawValue)
        XCTAssertEqual(host.bounds.height, frameView.bounds.height, accuracy: 1,
                       "The full-size host includes chrome; the content layout must retain the requested viewport.")
        let tables = nativeTables(in: host)
        var inspectorFrame: CGRect?
        if showsInspector, selectsFirst, [.rules, .sources].contains(destination) {
            func inspectorMarker(in view: NSView) -> NSView? {
                if view is RenderingInspectorMarkerView { return view }
                return view.subviews.lazy.compactMap { inspectorMarker(in: $0) }.first
            }
            let marker = try XCTUnwrap(inspectorMarker(in: host))
            inspectorFrame = marker.convert(marker.bounds, to: nil)
            let rowCount = destination == .rules
                ? model.rulesCatalog.rules.count : model.providersCatalog.providers.count
            XCTAssertTrue(tables.contains { $0.numberOfRows == rowCount },
                          "The selected detail must not replace the main data table.")
        }
        for table in tables {
            // Full-size SwiftUI windows may extend the native drawing bounds
            // beyond the data. Verify every actual visible column instead.
            for (index, column) in table.tableColumns.enumerated() where !column.isHidden {
                let rect = table.rect(ofColumn: index)
                XCTAssertGreaterThanOrEqual(rect.minX, table.visibleRect.minX - 1,
                                           "\(destination.rawValue): a business column starts outside the viewport.")
                XCTAssertLessThanOrEqual(rect.maxX, table.visibleRect.maxX + 1,
                                         "\(destination.rawValue): a business column ends outside the viewport.")
                if let inspectorFrame {
                    XCTAssertLessThanOrEqual(table.convert(rect, to: nil).maxX, inspectorFrame.minX + 1,
                                             "\(destination.rawValue): a business column extends beneath the inspector.")
                }
            }
            if selectsFirst, destination == .connections {
                XCTAssertGreaterThan(table.visibleRect.height, 120,
                                     "A selected route must leave the connection rows usable.")
                XCTAssertNotEqual(table.selectedRow, -1)
            }
            if selectsFirst, destination == .rules || destination == .sources {
                XCTAssertGreaterThan(table.visibleRect.height, 200,
                                     "A selected detail strip must leave the main table usable in a narrow window.")
                XCTAssertNotEqual(table.selectedRow, -1)
            }
        }
        let captureSize = frameView.bounds.size
        let bitmap = try captureOwnedWindow(window)
        bitmap.size = captureSize
        let backingSize = frameView.convertToBacking(frameView.bounds).size
        XCTAssertEqual(bitmap.pixelsWide, Int(backingSize.width.rounded()))
        XCTAssertEqual(bitmap.pixelsHigh, Int(backingSize.height.rounded()))
        assertNonblank(bitmap)
        if surface == .workbench {
            try assertNativeSidebarReadability(frameView: frameView, bitmap: bitmap)
        }
        if destination == .logs {
            let count = model.logsCatalog.entries.count
            let table = try XCTUnwrap(nativeTables(in: host).first { $0.numberOfRows == count })
            XCTAssertTrue(NSLocationInRange(count - 1, table.rows(in: table.visibleRect)),
                          "Follow Newest must show the final fixture log in the actual native Table.")
            let row = table.rect(ofRow: count - 1)
            XCTAssertEqual(row.intersection(table.visibleRect).height, row.height, accuracy: 1,
                           "Follow Newest must reveal the complete last log row.")
            func footerMarker(in view: NSView) -> NSView? {
                if view is RenderingFooterMarkerView { return view }
                return view.subviews.lazy.compactMap { footerMarker(in: $0) }.first
            }
            let footer = try XCTUnwrap(footerMarker(in: host))
            let overlap = table.convert(row, to: nil).intersection(footer.convert(footer.bounds, to: nil))
            XCTAssertTrue(overlap.isNull || overlap.height <= 1,
                          "The bottom status bar must not cover the last log row.")
        }
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 10_000)
        let appearanceName = scheme == .dark ? "dark" : "light"
        let variant = topologyDensity.fileSuffix
            + (pinsTopologyPath && destination == .overview ? "-pinned" : "")
            + (destination == .proxies ? nodeDetailsFixture.map { "-\($0)" } ?? "" : "")
            + (selectsFirst && [.connections, .proxies, .rules, .sources].contains(destination) ? "-selected" : "")
            + (showsInspector && destination.supportsInspector ? "-inspector" : "")
        let prefix = surface == .topology ? "topology" : "workbench-\(destination.rawValue)"
        let fileName = "\(prefix)\(variant)-\(language.rawValue)-\(appearanceName)-\(Int(size.width))x\(Int(size.height)).png"
        try png.write(to: output.appendingPathComponent(fileName), options: .atomic)
        print("Rendered \(fileName)")
    }

    private func captureOwnedWindow(_ window: NSWindow) throws -> NSBitmapImageRep {
        // Draw this fixture's own AppKit hierarchy, including native Lists and
        // SwiftUI Canvas. No desktop enumeration or screen-capture permission
        // is needed, and backing-scale pixels retain readable native text.
        let frameView = try XCTUnwrap(window.contentView?.superview)
        let bitmap = try XCTUnwrap(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
        frameView.effectiveAppearance.performAsCurrentDrawingAppearance {
            frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
        }
        return bitmap
    }

    private func assertFiniteLayout(_ view: NSView, maximumSplitHeight: CGFloat) {
        XCTAssertTrue(view.frame.origin.x.isFinite)
        XCTAssertTrue(view.frame.origin.y.isFinite)
        XCTAssertTrue(view.bounds.width.isFinite)
        XCTAssertTrue(view.bounds.height.isFinite)
        XCTAssertGreaterThanOrEqual(view.bounds.width, 0)
        XCTAssertGreaterThanOrEqual(view.bounds.height, 0)
        if view is NSSplitView {
            XCTAssertLessThanOrEqual(view.bounds.height, maximumSplitHeight + 1,
                                     "A split pane must not overflow the fixed content viewport.")
        }
        for child in view.subviews { assertFiniteLayout(child, maximumSplitHeight: maximumSplitHeight) }
    }

    private func assertNonblank(_ bitmap: NSBitmapImageRep) {
        var colors: Set<UInt32> = []
        var darkest = CGFloat(1)
        var lightest = CGFloat(0)
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: max(bitmap.pixelsHigh / 80, 1)) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: max(bitmap.pixelsWide / 100, 1)) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.9 else { continue }
                let red = UInt32((color.redComponent * 255).rounded())
                let green = UInt32((color.greenComponent * 255).rounded())
                let blue = UInt32((color.blueComponent * 255).rounded())
                colors.insert((red << 16) | (green << 8) | blue)
                let luminance = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                darkest = min(darkest, luminance)
                lightest = max(lightest, luminance)
            }
        }
        XCTAssertGreaterThan(colors.count, 24, "The Workbench should contain text and chart content.")
        XCTAssertGreaterThan(lightest - darkest, 0.25, "The screenshot must not be a blank surface.")
    }

    private func assertNativeSidebarReadability(frameView: NSView, bitmap: NSBitmapImageRep) throws {
        let scaleX = CGFloat(bitmap.pixelsWide) / frameView.bounds.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / frameView.bounds.height
        let table = try XCTUnwrap(nativeTables(in: frameView).first { $0.selectedRow >= 0 },
                                  "Expected the native sidebar table.")
        let neighbor = (0..<table.numberOfRows).first {
            $0 != table.selectedRow && table.rowView(atRow: $0, makeIfNecessary: false)?.isGroupRowStyle == false
        }
        for row in [table.selectedRow, neighbor].compactMap({ $0 }) {
            let rowBounds = table.rect(ofRow: row).insetBy(dx: 20, dy: 6)
            let rect = table.convert(rowBounds, to: frameView).intersection(frameView.bounds)
            let top = frameView.isFlipped ? rect.minY : frameView.bounds.maxY - rect.maxY
            var darkest = CGFloat(1)
            var lightest = CGFloat(0)
            for y in max(Int(top * scaleY), 0)..<min(Int((top + rect.height) * scaleY), bitmap.pixelsHigh) {
                for x in max(Int(rect.minX * scaleX), 0)..<min(Int(rect.maxX * scaleX), bitmap.pixelsWide) {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    let luminance = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                    darkest = min(darkest, luminance)
                    lightest = max(lightest, luminance)
                }
            }
            XCTAssertGreaterThan(
                lightest - darkest,
                0.25,
                "Native sidebar row \(row) has no readable foreground; the capture cannot verify its appearance."
            )
        }
    }

    private func nativeTables(in view: NSView) -> [NSTableView] {
        if let table = view as? NSTableView { return [table] }
        return view.subviews.flatMap { self.nativeTables(in: $0) }
    }

    private func makeFixture(defaults: UserDefaults, language: AppLanguage, topologyDensity: RenderingTopologyDensity,
                             destination: WorkbenchDestination) -> AppModel {
        let profile = RouterProfile(
            displayName: "Offline Preview",
            host: "controller.invalid",
            controllerKind: .mihomoCompatible
        )
        let topologyFixture: RenderingTopologyFixture
        switch topologyDensity {
        case .sparse: topologyFixture = .sparse
        case .dense: topologyFixture = .dense
        case .stress: topologyFixture = .stress
        }
        var groups = topologyFixture.groups
        if destination == .proxies,
           let protocolName = ProcessInfo.processInfo.environment["MICA_RENDER_NODE_DETAILS"],
           ["runtime", "ss", "vless"].contains(protocolName) {
            let usesVLESS = protocolName == "vless"
            // Standard Mihomo exposes runtime facts, not the original node
            // configuration. The other variants test optional reported fields.
            let metadata: [String: MihomoJSONValue] = protocolName == "runtime" ? [
                "id": .string("00000000-0000-0000-0000-000000000001"),
                "routing-mark": .number(0),
                "dialer-proxy": .string(""),
                "extra": .object([
                    "https://test.example.invalid/generate_204": .object([
                        "alive": .bool(true),
                        "history": .array([.object([
                            "time": .string("2026-05-29T04:26:40Z"), "delay": .number(42),
                        ])]),
                    ]),
                ]),
            ] : usesVLESS ? [
                "server": .string("vless-gateway.example.invalid"),
                "port": .number(443),
                "uuid": .string("00000000-0000-0000-0000-000000000001"),
                "flow": .string("xtls-rprx-vision"),
                "tls": .bool(true),
                "servername": .string("edge.example.invalid"),
                "client-fingerprint": .string("chrome"),
                "reality-opts": .object([
                    "public-key": .string("offline-fixture-public-key"),
                    "short-id": .string("01234567"),
                ]),
            ] : [
                "server": .string("ss-gateway.example.invalid"),
                "port": .number(8443),
                "cipher": .string("aes-128-gcm"),
                "password": .string("offline-fixture-secret"),
                "plugin": .string("v2ray-plugin"),
                "plugin-opts": .object(["mode": .string("websocket"), "host": .string("edge.example.invalid"), "tls": .bool(true)]),
            ]
            let node = ProxyNodeViewState(snapshot: ProxySnapshot(
                name: usesVLESS ? "Tokyo · VLESS Reality" : "Tokyo · Shadowsocks",
                type: usesVLESS ? "VLESS" : "Shadowsocks", alive: true,
                history: [.init(time: "2026-05-29T04:26:40Z", delay: 42)],
                providerName: "Primary", udp: true, tfo: false,
                metadata: metadata
            ))
            groups = [ProxyGroupViewState(
                id: "Proxy", type: "Selector", selected: "Singapore 02",
                options: [node.name, "Singapore 02"], optionDetails: [node.name: node],
                delays: [node.name: 42, "Singapore 02": 68]
            )]
        }
        let paths = topologyFixture.paths
        var seenRules = Set<String>()
        let rulePaths = paths.filter { seenRules.insert("\($0.2)\u{1F}\($0.3)").inserted }
        let connections = (0..<topologyFixture.connectionCount).map { index in
            let route = paths[index % paths.count]
            return ConnectionSnapshot(
                id: "render-fixture-\(index)",
                upload: 128_000 * (index + 1),
                download: 2_048_000 * (index + 1),
                uploadSpeed: 16_000,
                downloadSpeed: 256_000,
                chains: route.1,
                rule: route.2,
                rulePayload: route.3,
                metadata: ConnectionMetadataSnapshot(host: "service\(index).example", network: "tcp", sourceIP: route.0)
            )
        }
        var configuration = DashboardConfigSnapshot()
        configuration.modeOptions = ["rule", "global", "direct"]
        configuration.logLevel = "info"
        configuration.allowLan = true
        configuration.ipv6 = true
        configuration.tcpConcurrent = true
        configuration.tunEnabled = false
        configuration.mixedPort = 7890
        let dashboard = DashboardSnapshot(
            versionLabel: "Fixture 1.0",
            mode: "rule",
            config: configuration,
            traffic: TrafficSnapshot(upload: 34_078_720, download: 289_406_976),
            groups: groups,
            connections: connections,
            rules: rulePaths.enumerated().map { index, route in
                RuleViewState(id: "rule-\(index)", index: index, type: route.2,
                              payload: route.3, proxy: route.1.last ?? "DIRECT",
                              hitCount: 48 + index * 12, missCount: 3)
            },
            providers: [
                ProxyProviderViewState(name: "Primary", type: "Proxy", vehicleType: "HTTP", updatable: true, itemCount: 24),
                ProxyProviderViewState(kind: .rule, name: "Workspace", type: "Rule", behavior: "classical", format: "yaml", vehicleType: "HTTP", updatable: true, itemCount: 186),
            ]
        )
        let profiles = destination == .controllers ? [
            profile,
            RouterProfile(displayName: "Nikki · Home Router", host: "192.0.2.1", controllerKind: .nikkiMihomoCompatible),
            RouterProfile(displayName: "Surge · IPv6 Gateway", host: "2001:db8:1234:5678:90ab:cdef:1234:5678",
                          port: 6171, controllerKind: .surgeCompatible),
            RouterProfile(displayName: "Development and Collaboration · Long Controller Name",
                          scheme: .https, host: "development-and-collaboration.controller.example.invalid",
                          port: 443, controllerKind: .singBoxCompatible),
        ] : [profile]
        let model = AppModel(
            routers: profiles,
            selectedRouterID: profile.id,
            connectionState: .connected(version: "Fixture 1.0"),
            dashboard: dashboard,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore(),
            userDefaults: defaults,
            controllerProbeOperation: { _, _, _ in throw RenderingFailure.unexpectedRemoteOperation },
            controllerConnectionTestOperation: { _, _, _ in throw RenderingFailure.unexpectedRemoteOperation },
            immediateSessionRefreshLaneOperation: { _, _, _, _ in
                XCTFail("Rendering must not request a refresh")
            },
            liveSessionBaselineLoadOperation: { _, _, _ in throw RenderingFailure.unexpectedRemoteOperation }
        )
        let latest = Date(timeIntervalSince1970: 1_780_000_000)
        model.presentationLanguage = language
        model.controllerSession.begin(controllerID: profile.id)
        model.controllerSession.commitBaseline(at: latest)
        model.controllerSession.state = .live
        model.activeSessionControllerKind = .mihomoCompatible
        model.liveStreamState = .live
        model.liveStreamUpdatedAt = latest
        model.unifiedSnapshot = UnifiedControllerSnapshot(
            controllerType: .mihomoCompatible, adapterSource: "offline-test",
            capabilities: .mihomoCompatible, checkedAt: latest,
            versionLabel: "Fixture 1.0", modeLabel: "rule",
            rulesCount: dashboard.rules.count, providersCount: dashboard.providers.count,
            connectionsCount: connections.count
        )
        model.logsCatalog = LogsCatalogSnapshot(entries: (0..<18).map { index in
            ControllerLogEntry(
                id: "log-\(index)", receivedAt: latest.addingTimeInterval(Double(index - 17)),
                message: LogMessage(type: index % 7 == 0 ? "warning" : "info",
                                    payload: "[TCP] 192.0.2.10 --> service\(index).example:443 match Proxy using Tokyo 01")
            )
        }, entriesRevision: 1)

        let downloads = [2_200_000, 2_750_000, 1_840_000, 3_520_000, 4_080_000, 3_740_000, 2_900_000, 4_320_000]
        for index in 0..<48 {
            let receivedAt = latest.addingTimeInterval(TimeInterval((index - 47) * 6))
            let download = downloads[index % downloads.count]
            model.trafficTimeline.append(upload: download / 12, download: download, receivedAt: receivedAt)
            model.connectionCountTimeline.append(activeCount: 9 + index % 6, receivedAt: receivedAt)
            model.memoryTimeline.append(inUseBytes: 83_886_080 + index * 131_072, receivedAt: receivedAt)
        }
        return model
    }
}

private enum RenderingSurface {
    case workbench
    case topology
}

private enum RenderingTopologyDensity {
    case sparse
    case dense
    case stress

    init(_ value: String?) {
        switch value {
        case "1": self = .dense
        case "stress": self = .stress
        default: self = .sparse
        }
    }

    var fileSuffix: String {
        switch self {
        case .sparse: ""
        case .dense: "-dense"
        case .stress: "-stress"
        }
    }
}

private struct RenderingRoot: View {
    @Environment(AppModel.self) private var appModel
    @Environment(OverviewWindowRuntime.self) private var overviewRuntime

    let surface: RenderingSurface
    @State var destination: WorkbenchDestination
    var showsInspector = false

    var body: some View {
        switch surface {
        case .workbench:
            RenderingWorkbench(destination: destination, showsInspector: showsInspector)
        case .topology:
            GeometryReader { geometry in
                if let controllerID = appModel.selectedRouterID {
                    let runtime = overviewRuntime.registry.topologyRuntime(
                        controllerID: controllerID,
                        generation: appModel.controllerSession.generation
                    )
                    ScrollView {
                        OverviewTopologySection(
                            runtime: runtime,
                            minimumFlowHeight: max(geometry.size.height - 160, 240),
                            destination: $destination
                        )
                        .padding(MicaTheme.Metrics.pagePadding(for: geometry.size.width))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .background(MicaTheme.canvas)
                }
            }
        }
    }
}

// Fixed inputs exercise long labels, IPv6 sources, shared policy groups, and
// different route depths without reading the user's profiles or opening a client.
@MainActor
private struct RenderingTopologyFixture {
    let groups: [ProxyGroupViewState]
    let paths: [(String, [String], String, String)]
    let connectionCount: Int

    static let sparse = RenderingTopologyFixture(
        groups: [
            ProxyGroupViewState(id: "Proxy", type: "Selector", selected: "Automatic", options: ["Automatic", "Tokyo 01", "Singapore 02"]),
            ProxyGroupViewState(id: "Automatic", type: "URLTest", selected: "Tokyo 01", options: ["Tokyo 01", "Singapore 02"], delays: ["Tokyo 01": 42, "Singapore 02": 68]),
            ProxyGroupViewState(id: "Direct", type: "Selector", selected: "DIRECT", options: ["DIRECT"]),
        ],
        paths: [
            ("192.0.2.10", ["Tokyo 01", "Automatic", "Proxy"], "DomainSuffix", "example.com"),
            ("192.0.2.11", ["Singapore 02", "Proxy"], "RuleSet", "Workspace"),
            ("192.0.2.10", ["DIRECT", "Direct"], "GeoIP", "LAN"),
            ("192.0.2.12", ["Tokyo 01", "Automatic", "Proxy"], "Match", ""),
        ],
        connectionCount: 12
    )

    static let dense = RenderingTopologyFixture(
        groups: [
            ProxyGroupViewState(id: "🚀 手动选择", type: "Selector", selected: "♻️ 自动选择", options: ["♻️ 自动选择", "🇯🇵 东京 01", "🇸🇬 新加坡 02"]),
            ProxyGroupViewState(id: "♻️ 自动选择", type: "URLTest", selected: "🇯🇵 东京 01", options: ["🇯🇵 东京 01", "🇸🇬 新加坡 02"], delays: ["🇯🇵 东京 01": 42, "🇸🇬 新加坡 02": 68]),
            ProxyGroupViewState(id: "🤖 AI 服务", type: "Selector", selected: "🇺🇸 美国手动", options: ["🇺🇸 美国手动", "🇸🇬 新加坡 02"]),
            ProxyGroupViewState(id: "🇺🇸 美国手动", type: "Selector", selected: "美国自动", options: ["美国自动", "🇺🇸 美国 家宽 Garland Primary"]),
            ProxyGroupViewState(id: "美国自动", type: "URLTest", selected: "🇺🇸 美国 家宽 Garland Primary", options: ["🇺🇸 美国 家宽 Garland Primary", "🇺🇸 美国 Backup 02"], delays: ["🇺🇸 美国 家宽 Garland Primary": 156, "🇺🇸 美国 Backup 02": 184]),
            ProxyGroupViewState(id: "🎬 流媒体", type: "Selector", selected: "香港自动", options: ["香港自动", "🇸🇬 新加坡 02"]),
            ProxyGroupViewState(id: "香港自动", type: "URLTest", selected: "🇭🇰 香港 03", options: ["🇭🇰 香港 03", "🇭🇰 香港 Backup 04"], delays: ["🇭🇰 香港 03": 23, "🇭🇰 香港 Backup 04": 36]),
            ProxyGroupViewState(id: "☁️ Workspace & Development", type: "Selector", selected: "♻️ 自动选择", options: ["♻️ 自动选择", "🇺🇸 美国手动", "DIRECT"]),
            ProxyGroupViewState(id: "🍎 Apple 服务", type: "Selector", selected: "DIRECT", options: ["DIRECT", "♻️ 自动选择"]),
            ProxyGroupViewState(id: "🎯 全球直连", type: "Selector", selected: "DIRECT", options: ["DIRECT"]),
            ProxyGroupViewState(id: "🐟 漏网之鱼", type: "Selector", selected: "🚀 手动选择", options: ["🚀 手动选择", "DIRECT"]),
        ],
        paths: [
            ("192.0.2.10", ["🇺🇸 美国 家宽 Garland Primary", "美国自动", "🇺🇸 美国手动", "🤖 AI 服务"], "GeoSite", "openai"),
            ("192.0.2.10", ["🇯🇵 东京 01", "♻️ 自动选择", "🚀 手动选择"], "GeoSite", "google"),
            ("192.0.2.11", ["🇭🇰 香港 03", "香港自动", "🎬 流媒体"], "GeoSite", "youtube"),
            ("192.0.2.11", ["DIRECT", "🍎 Apple 服务"], "RuleSet", "Apple_International_Services"),
            ("192.0.2.12", ["🇸🇬 新加坡 02", "♻️ 自动选择", "☁️ Workspace & Development"], "RuleSet", "Development_and_Collaboration"),
            ("192.0.2.12", ["🇺🇸 美国 Backup 02", "美国自动", "🇺🇸 美国手动", "🤖 AI 服务"], "GeoSite", "openai"),
            ("192.0.2.13", ["🇭🇰 香港 Backup 04", "香港自动", "🎬 流媒体"], "GeoSite", "netflix"),
            ("192.0.2.13", ["DIRECT", "🎯 全球直连"], "GeoIP", "LAN"),
            ("192.0.2.14", ["🇯🇵 东京 01", "♻️ 自动选择", "☁️ Workspace & Development"], "RuleSet", "Development_and_Collaboration"),
            ("192.0.2.14", ["🇸🇬 新加坡 02", "🚀 手动选择"], "DomainSuffix", "downloads.example.com"),
            ("192.0.2.15", ["🇯🇵 东京 01", "♻️ 自动选择", "🚀 手动选择", "🐟 漏网之鱼"], "Match", ""),
            ("192.0.2.15", ["DIRECT", "🍎 Apple 服务"], "RuleSet", "Apple_International_Services"),
            ("2001:db8:8:3::37", ["🇺🇸 美国 家宽 Garland Primary", "美国自动", "🇺🇸 美国手动", "🤖 AI 服务"], "GeoSite", "anthropic"),
            ("2001:db8:8:3::37", ["🇭🇰 香港 03", "香港自动", "🎬 流媒体"], "GeoSite", "youtube"),
            ("2001:db8:8:4::24", ["🇸🇬 新加坡 02", "♻️ 自动选择", "🚀 手动选择"], "RuleSet", "Telegram_and_Messaging"),
            ("2001:db8:8:4::24", ["DIRECT", "🎯 全球直连"], "GeoIP", "LAN"),
        ],
        connectionCount: 48
    )

    static let stress: RenderingTopologyFixture = {
        let entries = [
            "🚀 手动选择", "🤖 AI 服务", "🎬 流媒体", "☁️ Workspace & Development",
            "🍎 Apple 服务", "🎮 游戏服务", "💬 即时通信", "🐟 漏网之鱼",
        ]
        let regions = ["香港策略", "东京策略", "新加坡策略", "美国策略", "欧洲策略", "全球策略"]
        let automatic = ["♻️ 最低延迟", "♻️ 高速线路", "♻️ 稳定优先", "♻️ 故障转移"]
        let exits = [
            "🇭🇰 香港 01", "🇭🇰 香港 02", "🇯🇵 东京 01", "🇯🇵 东京 02",
            "🇸🇬 新加坡 01", "🇸🇬 新加坡 02", "🇺🇸 美国 Residential Primary", "🇺🇸 美国 Backup 02",
            "🇩🇪 德国 01", "🇩🇪 德国 02", "🇬🇧 伦敦 01", "🇬🇧 伦敦 02",
        ]
        let ruleNames = [
            "openai", "anthropic", "google", "youtube", "netflix", "disney",
            "apple", "microsoft", "github", "steam", "telegram", "discord",
            "spotify", "amazon", "reddit", "wikipedia", "cloudflare",
            "Development_and_Collaboration", "Downloads_and_Updates", "International_Services",
        ]
        var groups = entries.enumerated().map { index, name in
            ProxyGroupViewState(id: name, type: "Selector", selected: regions[index % regions.count], options: regions)
        }
        groups += regions.enumerated().map { index, name in
            ProxyGroupViewState(id: name, type: "Selector", selected: automatic[index % automatic.count], options: automatic)
        }
        groups += automatic.enumerated().map { index, name in
            ProxyGroupViewState(
                id: name, type: index == 3 ? "Fallback" : "URLTest",
                selected: exits[index * 3], options: exits,
                delays: Dictionary(uniqueKeysWithValues: exits.enumerated().map { ($0.element, 24 + $0.offset * 13) })
            )
        }

        // Every source reaches every rule over the first 320 connections. The
        // subsequent passes vary shared policy choices, producing hundreds of
        // crossing edges while holding the graph to just 66 nodes.
        let paths: [(String, [String], String, String)] = (0..<1_000).map { index in
            let source = index % 16
            let rule = (index / 16) % ruleNames.count
            let pass = index / 320
            let entry = (source * 3 + rule + pass) % entries.count
            let region = (source + rule * 5 + pass * 2) % regions.count
            let selection = (source / 2 + rule + pass) % automatic.count
            let exit = (source * 5 + rule * 7 + pass * 3) % exits.count
            let sourceIP = source < 12 ? "192.0.2.\(source + 10)" : "2001:db8:8:\(source)::24"
            return (
                sourceIP,
                [exits[exit], automatic[selection], regions[region], entries[entry]],
                rule < 17 ? "GeoSite" : "RuleSet",
                ruleNames[rule]
            )
        }
        return RenderingTopologyFixture(groups: groups, paths: paths, connectionCount: 1_000)
    }()
}

// Compose the production views directly; the app/window lifecycle that loads
// saved profiles and opens live controllers is deliberately not part of this fixture.
private struct RenderingWorkbench: View {
    @Environment(\.micaAppLanguage) private var language
    @Environment(WorkbenchWorkspaceStore.self) private var workspaceStore
    @State var destination: WorkbenchDestination
    var showsInspector = false

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            WorkbenchSidebarView(
                destination: $destination,
                isControllerSwitchingEnabled: true,
                onSelectController: { _ in },
                onAddController: {}
            )
            .navigationSplitViewColumnWidth(
                min: MicaTheme.Metrics.sidebarMin,
                ideal: MicaTheme.Metrics.sidebarIdeal,
                max: MicaTheme.Metrics.sidebarMax
            )
        } detail: {
            VStack(spacing: 0) {
                WorkbenchWorkspaceView(destination: $destination, onAddController: {}, onEditController: { _ in })
                    .inspector(isPresented: Binding(
                        get: { showsInspector && destination.supportsInspector && workspaceStore.isInspectorPresented },
                        set: { workspaceStore.isInspectorPresented = $0 }
                    )) {
                        WorkbenchInspectorContainer(destination: $destination, onEditController: { _ in })
                            .background(RenderingInspectorMarker())
                            .inspectorColumnWidth(min: MicaTheme.Metrics.inspectorMin,
                                                  ideal: MicaTheme.Metrics.inspectorIdeal,
                                                  max: MicaTheme.Metrics.inspectorMax)
                    }
                WorkbenchBottomChrome()
                    .background(RenderingFooterMarker())
            }
            .navigationTitle(MicaStrings.localizedKey(destination.titleKey, language: language))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if destination == .overview {
                        OverviewPreferencesToolbarControl()
                    }
                    if destination.requiresController {
                        WorkbenchSessionControlButton(kind: .refresh)
                        WorkbenchSessionControlButton(kind: .pause)
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(MicaTheme.canvas)
        .containerBackground(MicaTheme.canvas, for: .window)
        .toolbarBackground(MicaTheme.canvas, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
    }
}

private struct RenderingFooterMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> RenderingFooterMarkerView {
        let view = RenderingFooterMarkerView()
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: RenderingFooterMarkerView, context: Context) {}
}

private final class RenderingFooterMarkerView: NSView {}

private struct RenderingInspectorMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> RenderingInspectorMarkerView {
        let view = RenderingInspectorMarkerView()
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: RenderingInspectorMarkerView, context: Context) {}
}

private final class RenderingInspectorMarkerView: NSView {}

private enum RenderingFailure: Error {
    case outputOutsideScratch
    case unexpectedRemoteOperation
}
