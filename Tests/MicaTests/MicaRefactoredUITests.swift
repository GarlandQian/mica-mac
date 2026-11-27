import Foundation
import MicaCore
import Testing
@testable import Mica

struct MicaRefactoredUITests {
    @Test func destinationHasSixFocusedWorkspaces() {
        let all = WorkbenchDestination.allCases
        #expect(all == [.overview, .proxies, .connections, .rules, .logs, .controllers])
        #expect(all.compactMap(\.shortcut).count == 6)
        #expect(WorkbenchDestination.controllers.requiresController == false)
        #expect(WorkbenchDestination.proxies.requiresController == true)
        #expect(WorkbenchDestination.overview.liveSessionVisibleDestination == .overview)
        #expect(WorkbenchDestination.proxies.liveSessionVisibleDestination == .other)
        #expect(WorkbenchDestination.connections.liveSessionVisibleDestination == .connections)
        #expect(WorkbenchDestination.logs.liveSessionVisibleDestination == .logs)
    }

    @MainActor
    @Test func proxiesStoreProjectsFiltersAndSortsWithoutMutatingOrder() {
        let suiteName = "MicaTests.ProxiesStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ProxiesStore(userDefaults: defaults)
        let catalog = PolicyGroupCatalogSnapshot(
            mode: "Rule",
            groups: [
                ProxyGroupViewState(
                    id: "Hidden",
                    type: "Selector",
                    selected: "A",
                    options: ["A"],
                    hidden: true
                ),
                ProxyGroupViewState(
                    id: "Proxy",
                    type: "Selector",
                    selected: "Tokyo",
                    options: ["Tokyo", "Singapore", "Broken", "SlowNode"],
                    optionDetails: [
                        "Tokyo": ProxyNodeViewState(
                            snapshot: ProxySnapshot(name: "Tokyo", type: "Shadowsocks", alive: true, history: [ProxyDelayHistorySnapshot(time: nil, delay: 90)])
                        ),
                        "Singapore": ProxyNodeViewState(
                            snapshot: ProxySnapshot(name: "Singapore", type: "VLESS", alive: true, history: [ProxyDelayHistorySnapshot(time: nil, delay: 45)])
                        ),
                        "Broken": ProxyNodeViewState(
                            snapshot: ProxySnapshot(name: "Broken", type: "Trojan", alive: false, history: [])
                        ),
                        "SlowNode": ProxyNodeViewState(
                            snapshot: ProxySnapshot(name: "SlowNode", type: "VMess", alive: true, history: [ProxyDelayHistorySnapshot(time: nil, delay: 240)])
                        ),
                    ],
                    delays: [
                        "Tokyo": 90,
                        "Singapore": 45,
                        "Broken": 0,
                        "SlowNode": 240,
                    ]
                ),
                ProxyGroupViewState(
                    id: "GLOBAL",
                    type: "Selector",
                    selected: "Proxy",
                    options: ["Proxy", "DIRECT"]
                ),
            ]
        )

        store.sync(catalog: catalog, revision: 1, visibility: .followMode, controllerID: UUID())
        #expect(store.groups.map(\.id) == ["Proxy"])
        #expect(store.visibleNodes.map(\.name) == ["Tokyo", "Singapore", "Broken", "SlowNode"])

        store.sortOrder = .latencyAscending
        #expect(store.visibleNodes.map(\.name) == ["Singapore", "Tokyo", "SlowNode", "Broken"])

        store.filter = .slow
        #expect(store.visibleNodes.map(\.name) == ["SlowNode"])

        store.filter = .unavailable
        #expect(store.visibleNodes.map(\.name) == ["Broken"])

        store.filter = .all
        store.searchQuery = "vless"
        #expect(store.visibleNodes.map(\.name) == ["Singapore"])

        store.searchQuery = ""
        store.sync(catalog: catalog, revision: 2, visibility: .alwaysShow, controllerID: nil)
        #expect(store.groups.map(\.id) == ["Proxy", "GLOBAL"])
    }

    @MainActor
    @Test func connectionsRulesAndLogsStoresFilterProperly() {
        let connectionsStore = ConnectionsStore()
        let activeConn = ConnectionSnapshot(
            id: "c1",
            upload: 1200,
            download: 8400,
            uploadSpeed: 100,
            downloadSpeed: 900,
            start: nil,
            chains: ["DIRECT", "Match"],
            rule: "DOMAIN-SUFFIX",
            rulePayload: "example.com",
            metadata: ConnectionMetadataSnapshot(host: "api.example.com", network: "tcp", process: "curl")
        )
        let closedConn = ConnectionSnapshot(
            id: "c2",
            upload: 100,
            download: 200,
            metadata: ConnectionMetadataSnapshot(host: "closed.example.org", network: "udp", process: "dns")
        )
        connectionsStore.sync(
            activeCatalog: ConnectionsCatalogSnapshot(
                connections: [activeConn],
                traffic: TrafficSnapshot(upload: 1200, download: 8400),
                structureRevision: 1,
                metricsRevision: 1,
                trafficRevision: 1
            ),
            closedRecords: [ClosedConnectionRecord(snapshot: closedConn, closedAt: Date())],
            closedRevision: 1
        )
        #expect(connectionsStore.rows.count == 1)
        #expect(connectionsStore.rows[0].host == "api.example.com")

        connectionsStore.scope = .closed
        #expect(connectionsStore.rows.count == 1)
        #expect(connectionsStore.rows[0].host == "closed.example.org")

        let rulesStore = RulesStore()
        rulesStore.sync(rules: [
            RuleViewState(id: "r1", index: 0, type: "DOMAIN-SUFFIX", payload: "apple.com", proxy: "DIRECT"),
            RuleViewState(id: "r2", index: 1, type: "GEOIP", payload: "CN", proxy: "DIRECT"),
        ])
        #expect(rulesStore.rows.count == 2)
        rulesStore.selectedType = "GEOIP"
        #expect(rulesStore.rows.map(\.id) == ["r2"])

        let logsStore = LogsStore()
        logsStore.sync(catalog: LogsCatalogSnapshot(entries: [
            ControllerLogEntry(id: "l1", receivedAt: Date(), message: LogMessage(type: "info", payload: "started")),
            ControllerLogEntry(id: "l2", receivedAt: Date(), message: LogMessage(type: "error", payload: "dial failed")),
        ], entriesRevision: 1))
        #expect(logsStore.errorCount == 1)
        #expect(logsStore.rows.count == 2)
        logsStore.levelFilter = .error
        #expect(logsStore.rows.map(\.id) == ["l2"])
    }

    @Test func formattersProduceReadableCompactOutput() {
        #expect(MicaFormatters.formatBytes(512) == "512 B")
        #expect(MicaFormatters.formatBytes(1_500) == "1.50 KB")
        #expect(MicaFormatters.formatRate(2_048) == "2.05 KB/s")
        #expect(MicaFormatters.compactRate(4_300_000) == "4.3 M")
        #expect(MicaFormatters.formatLatency(42, language: .english) == "42 ms")
    }

    @MainActor
    @Test func workspaceUIStateTogglesInspectorAndClearsAcrossDestinations() {
        let state = WorkspaceUIState()
        #expect(state.isInspectorPresented == false)

        state.isInspectorPresented = true
        #expect(state.isInspectorPresented == true)

        state.selectInspector(.connection(id: "conn-1"))
        #expect(state.inspectorSelection == .connection(id: "conn-1"))
        #expect(state.isInspectorPresented == true)

        state.clearInspectorIfNotOwned(by: .proxies)
        #expect(state.inspectorSelection == .none)
        #expect(state.isInspectorPresented == true)

        state.clearInspectorIfNotOwned(by: .overview)
        #expect(state.isInspectorPresented == false)
    }
}
