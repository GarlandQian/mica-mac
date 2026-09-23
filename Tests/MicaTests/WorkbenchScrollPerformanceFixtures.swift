import Foundation
import MicaCore
import XCTest
@testable import Mica

/// All catalog construction happens before the measured scroll intervals.
/// Repeated frames retain source order and identities while changing real fields.
@MainActor
struct ScrollPerformanceFrames {
    private let dashboards: [DashboardSnapshot]
    private let logs: [[ControllerLogEntry]]
    private let latest = Date(timeIntervalSince1970: 1_780_000_000)

    init() {
        var configuration = DashboardConfigSnapshot()
        configuration.modeOptions = ["rule", "global", "direct"]
        configuration.logLevel = "info"
        configuration.allowLan = true
        configuration.ipv6 = true
        configuration.tcpConcurrent = true
        configuration.tunEnabled = false
        configuration.mixedPort = 7890
        let initial = DashboardSnapshot(
            versionLabel: "Offline scroll fixture", mode: "rule", config: configuration,
            traffic: TrafficSnapshot(upload: 1_000_000, download: 2_000_000),
            groups: MicaPerformanceFixtures.proxyCatalog(groupCount: 36, membersPerGroup: 500).groups,
            connections: MicaPerformanceFixtures.connections(count: 1_000),
            rules: MicaPerformanceFixtures.rules(count: 3_000),
            providers: MicaPerformanceFixtures.sources(count: 500)
        )
        dashboards = (0..<12).map { frame in
            var snapshot = initial
            snapshot.traffic = TrafficSnapshot(upload: 1_000_000 + frame * 1_024, download: 2_000_000 + frame * 8_192)
            for index in snapshot.connections.indices {
                snapshot.connections[index].uploadSpeed = 1_024 + (index + frame) % 8_192
                snapshot.connections[index].downloadSpeed = 8_192 + (index + frame) % 16_384
                snapshot.connections[index].upload = index * 97 + frame * 97
                snapshot.connections[index].download = index * 193 + frame * 193
            }
            for groupIndex in snapshot.groups.indices {
                snapshot.groups[groupIndex].delays = Dictionary(uniqueKeysWithValues:
                    snapshot.groups[groupIndex].options.enumerated().map { ($0.element, 20 + ($0.offset + frame) % 1_200) })
            }
            for index in snapshot.rules.indices { snapshot.rules[index].hitCount = index * 3 + frame }
            for index in snapshot.providers.indices { snapshot.providers[index].itemCount = index * 11 + frame }
            return snapshot
        }
        let initialLogs = MicaPerformanceFixtures.logs(count: 2_000)
        logs = (0..<12).map { frame in
            Array(initialLogs.dropFirst(frame)) + (0..<frame).map { index in
                ControllerLogEntry(id: "live-fixture-\(index)", receivedAt: Date(timeIntervalSince1970: 1_780_000_000 + Double(index)),
                                   message: LogMessage(type: "info", payload: "[TCP] fixture append \(index) via policy-1"))
            }
        }
    }

    func makeModel(defaults: UserDefaults) -> AppModel {
        let profiles = (0..<40).map {
            RouterProfile(displayName: "Offline controller \($0)", host: "controller-\($0).invalid", controllerKind: .mihomoCompatible)
        }
        let profile = profiles[0]
        let model = AppModel(
            routers: profiles, selectedRouterID: profile.id,
            connectionState: .connected(version: "Offline scroll fixture"), dashboard: dashboards[0],
            profileStore: InMemoryRouterProfileStore(), secretStore: InMemorySecretStore(), userDefaults: defaults,
            controllerProbeOperation: { _, _, _ in throw ScrollFixtureError.unexpectedRemoteOperation },
            controllerConnectionTestOperation: { _, _, _ in throw ScrollFixtureError.unexpectedRemoteOperation },
            immediateSessionRefreshLaneOperation: { _, _, _, _ in XCTFail("Offline scroll measurement must never refresh a controller.") },
            liveSessionBaselineLoadOperation: { _, _, _ in throw ScrollFixtureError.unexpectedRemoteOperation }
        )
        model.presentationLanguage = .english
        model.controllerSession.begin(controllerID: profile.id)
        model.controllerSession.commitBaseline(at: latest)
        model.controllerSession.state = .live
        model.activeSessionControllerKind = .mihomoCompatible
        model.liveStreamState = .live
        model.liveStreamUpdatedAt = latest
        model.unifiedSnapshot = UnifiedControllerSnapshot(
            controllerType: .mihomoCompatible, adapterSource: "offline-scroll-test", capabilities: .mihomoCompatible,
            checkedAt: latest, versionLabel: "Offline scroll fixture", modeLabel: "rule",
            rulesCount: 3_000, providersCount: 500, connectionsCount: 1_000
        )
        model.logsCatalog = LogsCatalogSnapshot(entries: logs[0], entriesRevision: 1)
        for index in 0..<60 {
            let receivedAt = latest.addingTimeInterval(Double(index - 59))
            model.trafficTimeline.append(upload: 16_384 + index * 1_024, download: 524_288 + index * 8_192, receivedAt: receivedAt)
            model.connectionCountTimeline.append(activeCount: 1_000, receivedAt: receivedAt)
            model.memoryTimeline.append(inUseBytes: 128 * 1_024 * 1_024, receivedAt: receivedAt)
        }
        return model
    }

    func publish(frame: Int, to model: AppModel) {
        // Start with a changed frame, not a no-op equal to the initial catalog.
        let index = (frame + 1) % dashboards.count
        model.dashboard = dashboards[index]
        model.publishDashboardDomains([.connections, .policyGroups, .rules, .providers])
        model.publishControllerLogs(logs[index])
        let receivedAt = latest.addingTimeInterval(Double(frame + 1) / 10)
        model.trafficTimeline.append(upload: 16_384 + frame * 1_024, download: 524_288 + frame * 8_192, receivedAt: receivedAt)
        model.connectionCountTimeline.append(activeCount: 1_000 + frame % 3, receivedAt: receivedAt)
    }
}

private enum ScrollFixtureError: Error { case unexpectedRemoteOperation }
