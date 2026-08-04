import Foundation
import MicaCore
import Testing
@testable import Mica

struct ConnectionMutationSafetyTests {
    @MainActor
    @Test func blankConnectionIDNeverReachesTheCloseTransport() async {
        let harness = ConnectionMutationHarness()
        let connection = ConnectionSnapshot(id: "  \n", upload: 10, download: 20)
        let (model, _) = makeConnectionModel(
            connections: [connection],
            harness: harness
        )

        model.closeConnection(connection)

        #expect(model.connectionTask == nil)
        #expect(model.operationState?.kind == .partial)
        #expect(await harness.record.closeIDs.isEmpty)
        #expect(model.dashboard.connections == [connection])
    }

    @MainActor
    @Test func confirmedSingleCloseRemainsPartialWhenAuthoritativeRefreshFails() async throws {
        let harness = ConnectionMutationHarness(snapshotFailure: true)
        let connection = ConnectionSnapshot(id: "connection-1", upload: 10, download: 20)
        let (model, profile) = makeConnectionModel(
            connections: [connection],
            harness: harness
        )

        model.closeConnection(connection)
        let task = try #require(model.connectionTask)
        await task.value

        let record = await harness.record
        #expect(record.closeIDs == ["connection-1"])
        #expect(record.snapshotCount == 1)
        #expect(model.dashboard.connections.isEmpty)
        #expect(model.dashboardSessionControls.closedConnections.map(\.id) == ["connection-1"])
        #expect(model.operationState?.kind == .partial)
        #expect(model.trialSession(for: profile).lastCommandStatus == .partial)
    }

    @MainActor
    @Test func confirmedCloseAllRemainsPartialWhenAuthoritativeRefreshFails() async throws {
        let harness = ConnectionMutationHarness(snapshotFailure: true)
        let connections = [
            ConnectionSnapshot(id: "connection-1", upload: 10, download: 20),
            ConnectionSnapshot(id: "connection-2", upload: 30, download: 40),
        ]
        let (model, profile) = makeConnectionModel(
            connections: connections,
            harness: harness
        )

        model.closeAllConnections()
        let task = try #require(model.connectionTask)
        await task.value

        let record = await harness.record
        #expect(record.closeAllCount == 1)
        #expect(record.snapshotCount == 1)
        #expect(model.dashboard.connections.isEmpty)
        #expect(model.dashboardSessionControls.closedConnections.map(\.id) == connections.map(\.id))
        #expect(model.operationState?.kind == .partial)
        #expect(model.trialSession(for: profile).lastCommandStatus == .partial)
    }

    @MainActor
    @Test func readOnlyPolicyGroupCannotStartASelectionMutation() {
        let group = ProxyGroupViewState(
            id: "Read Only",
            type: "URLTest",
            selected: "Node A",
            options: ["Node A", "Node B"],
            selectable: false
        )
        let (model, _) = makeConnectionModel(groups: [group])

        model.selectNode("Node B", in: group.id)

        #expect(model.switchTask == nil)
        #expect(model.dashboard.groups.first?.selected == "Node A")
        #expect(model.operationState?.kind == .partial)
    }

    @MainActor
    @Test func stalePolicyMemberCannotStartASelectionMutation() {
        let group = ProxyGroupViewState(
            id: "Selector",
            type: "Selector",
            selected: "Node A",
            options: ["Node A"]
        )
        let (model, _) = makeConnectionModel(groups: [group])

        model.selectNode("Removed Node", in: group.id)

        #expect(model.switchTask == nil)
        #expect(model.dashboard.groups.first?.selected == "Node A")
        #expect(model.operationState?.kind == .error)
    }
}

private actor ConnectionMutationHarness {
    struct Record: Equatable, Sendable {
        var closeIDs: [String]
        var closeAllCount: Int
        var snapshotCount: Int
    }

    struct SnapshotFailure: Error, Sendable {}

    private let snapshotFailure: Bool
    private var closeIDs: [String] = []
    private var closeAllCount = 0
    private var snapshotCount = 0

    init(snapshotFailure: Bool = false) {
        self.snapshotFailure = snapshotFailure
    }

    var record: Record {
        Record(
            closeIDs: closeIDs,
            closeAllCount: closeAllCount,
            snapshotCount: snapshotCount
        )
    }

    func closeConnection(id: String) {
        closeIDs.append(id)
    }

    func closeAllConnections() {
        closeAllCount += 1
    }

    func connectionsSnapshot() throws -> ConnectionsResponse {
        snapshotCount += 1
        if snapshotFailure {
            throw SnapshotFailure()
        }
        return ConnectionsResponse(connections: [])
    }
}

@MainActor
private func makeConnectionModel(
    connections: [ConnectionSnapshot] = [],
    groups: [ProxyGroupViewState] = [],
    harness: ConnectionMutationHarness = ConnectionMutationHarness()
) -> (AppModel, RouterProfile) {
    let profile = RouterProfile(
        displayName: "Offline Controller",
        host: "offline.invalid",
        port: 12_345,
        controllerKind: .mihomoCompatible
    )
    let dashboard = DashboardSnapshot(
        versionLabel: "offline-test",
        mode: "Rule",
        traffic: TrafficSnapshot(upload: 0, download: 0),
        groups: groups,
        connections: connections
    )
    let model = AppModel(
        routers: [profile],
        selectedRouterID: profile.id,
        connectionState: .connected(version: "offline-test"),
        dashboard: dashboard,
        profileStore: InMemoryRouterProfileStore(),
        secretStore: InMemorySecretStore(),
        mihomoConnectionCloseOperation: { _, _, connectionID in
            await harness.closeConnection(id: connectionID)
        },
        mihomoCloseAllConnectionsOperation: { _, _ in
            await harness.closeAllConnections()
        },
        mihomoConnectionsSnapshotOperation: { _, _ in
            try await harness.connectionsSnapshot()
        }
    )
    model.controllerSession.begin(controllerID: profile.id)
    model.controllerSession.commitBaseline(at: Date(timeIntervalSince1970: 1))
    model.controllerSession.state = .live
    model.activeSessionControllerKind = .mihomoCompatible
    return (model, profile)
}
