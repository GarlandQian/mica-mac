import Foundation
@testable import Mica
import MicaCore
import Testing

struct WorkbenchPresentationTests {
    @Test func trafficTimelineCapsAtFiveMinutesAndThreeHundredReceivedSamples() {
        var timeline = TrafficTimeline()

        for value in 0...300 {
            timeline.append(upload: value, download: value * 2, receivedAt: Date(timeIntervalSince1970: TimeInterval(value)))
        }

        #expect(timeline.samples.count == TrafficTimeline.maximumSampleCount)
        #expect(timeline.samples.first?.upload == 1)
        #expect(timeline.samples.last?.download == 600)
    }

    @Test func trafficTimelineDropsSamplesOlderThanFiveMinutesWithoutFabricatingGaps() {
        var timeline = TrafficTimeline(capacity: 1_000)
        timeline.append(upload: 1, download: 2, receivedAt: Date(timeIntervalSince1970: 0))
        timeline.append(upload: 3, download: 4, receivedAt: Date(timeIntervalSince1970: 301))

        #expect(timeline.samples.map(\.upload) == [3])
    }

    @Test func trafficTimelineResetRemovesOnlyPresentationHistory() {
        var timeline = TrafficTimeline()
        timeline.append(upload: 12, download: 24)

        timeline.reset()

        #expect(timeline.isEmpty)
    }

    @Test func logBufferEnforcesCountAndUTF8Budgets() {
        var buffer = BoundedLogBuffer()
        for index in 0...BoundedLogBuffer.maximumEntryCount {
            buffer.append(
                ControllerLogEntry(
                    id: "log-\(index)",
                    message: LogMessage(type: "info", payload: "entry-\(index)")
                )
            )
        }

        #expect(buffer.entries.count == BoundedLogBuffer.maximumEntryCount)
        #expect(buffer.entries.first?.id == "log-1")
        #expect(buffer.entries.last?.id == "log-\(BoundedLogBuffer.maximumEntryCount)")

        buffer.append(
            ControllerLogEntry(
                id: "oversized",
                message: LogMessage(type: "info", payload: String(repeating: "界", count: 3_000_000))
            )
        )
        #expect(buffer.utf8ByteCount <= BoundedLogBuffer.maximumUTF8Bytes)
        #expect(!buffer.entries.contains { $0.id == "oversized" })
    }

    @Test func closedConnectionBufferDeduplicatesLatestAndEnforcesCountBudget() {
        var buffer = ClosedConnectionBuffer()
        for index in 0...ClosedConnectionBuffer.maximumEntryCount {
            buffer.record([ConnectionSnapshot(id: "connection-\(index)", upload: index)])
        }

        #expect(buffer.entries.count == ClosedConnectionBuffer.maximumEntryCount)
        #expect(buffer.entries.first?.id == "connection-\(ClosedConnectionBuffer.maximumEntryCount)")
        #expect(buffer.entries.last?.id == "connection-1")

        buffer.record([ConnectionSnapshot(id: "connection-500", upload: 99_999)])
        #expect(buffer.entries.first?.id == "connection-500")
        #expect(buffer.entries.first?.upload == 99_999)
        #expect(buffer.entries.filter { $0.id == "connection-500" }.count == 1)

        buffer.record([
            ConnectionSnapshot(id: "duplicate", upload: 1),
            ConnectionSnapshot(id: "between", upload: 2),
            ConnectionSnapshot(id: "duplicate", upload: 3),
        ])
        #expect(buffer.entries.prefix(2).map(\.id) == ["between", "duplicate"])
        #expect(buffer.entries.first { $0.id == "duplicate" }?.upload == 3)
        #expect(buffer.entries.filter { $0.id == "duplicate" }.count == 1)
    }

    @Test func retryDispositionUsesStructuredFailureCategories() {
        #expect(RouterTrialFailureCategory.timeout.retryDisposition == .transient)
        #expect(RouterTrialFailureCategory.unexpectedHTTP(429).retryDisposition == .transient)
        #expect(RouterTrialFailureCategory.unexpectedHTTP(503).retryDisposition == .transient)
        #expect(RouterTrialFailureCategory.unexpectedHTTP(400).retryDisposition == .terminal)
        #expect(RouterTrialFailureCategory.authFailed.retryDisposition == .terminal)
        #expect(RouterTrialFailureCategory.cancelled.retryDisposition == .cancelled)
        #expect(RouterTrialFailureCategory.localFailure.retryDisposition == .retryOnce)
    }

    @Test func singBoxGRPCFailuresUseStructuredRetryCategories() {
        #expect(
            RouterTrialFailureCategory(error: SingBoxGRPCError.rpc(code: 1, message: "cancelled"))
                == .cancelled
        )
        #expect(
            RouterTrialFailureCategory(error: SingBoxGRPCError.rpc(code: 4, message: "deadline"))
                == .timeout
        )
        #expect(
            RouterTrialFailureCategory(error: SingBoxGRPCError.rpc(code: 16, message: "unauthorized"))
                == .authFailed
        )
        #expect(
            RouterTrialFailureCategory(error: SingBoxGRPCError.rpc(code: 14, message: "unavailable"))
                == .networkUnavailable
        )
        #expect(
            RouterTrialFailureCategory(error: SingBoxGRPCError.rpc(code: 13, message: "internal"))
                == .networkFailed
        )
        #expect(
            RouterTrialFailureCategory(error: SingBoxGRPCError.transport("offline"))
                == .networkFailed
        )
        #expect(
            RouterTrialFailureCategory(error: SingBoxGRPCError.invalidIntervalMilliseconds(0))
                == .localFailure
        )
    }

    @Test func policyFilteringRetainsControllerOrder() {
        let groups = [
            group(id: "First", type: "Selector", selected: "A", options: ["A"]),
            group(id: "Second", type: "URLTest", selected: "B", options: ["B"]),
            group(id: "Third", type: "Selector", selected: "C", options: ["C"]),
        ]

        let filtered = PolicyGroupPresentation.filteredGroups(groups, matching: "selector")

        #expect(filtered.map(\.id) == ["First", "Third"])
    }

    @Test func policyOptionFilteringReturnsEmptyQueryInputUnchanged() {
        let options = ["Third", "First", "First", "Second"]

        #expect(PolicyGroupPresentation.filteredOptions(options, matching: "  ") == options)
    }

    @Test func policyOptionFilteringIsCaseInsensitiveAndPreservesRelativeOrder() {
        let options = ["Beta", "alpha-east", "ALPHA-west", "alpha-east", "Gamma"]

        let filtered = PolicyGroupPresentation.filteredOptions(options, matching: "AlPhA")

        #expect(filtered == ["alpha-east", "ALPHA-west", "alpha-east"])
    }

    @Test func policyOptionFilteringFindsMatchesBeyondInitialMemberWindow() {
        let options = (0..<60).map { "node-\($0)" }
        let filtered = PolicyGroupPresentation.filteredOptions(options, matching: "node-59")
        let interactionState = PolicyGroupControllerInteractionState()

        #expect(filtered == ["node-59"])
        #expect(interactionState.visibleOptions(filtered, groupID: "Proxy") == ["node-59"])
    }

    @Test func policyOptionFilteringMatchesCompleteNodeMetadataWithoutChangingOrder() {
        let first = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "Node First",
                type: "Shadowsocks",
                providerName: "Remote Provider",
                interfaceName: "utun9",
                udp: true,
                tfo: true,
                metadata: ["region": .string("Tokyo")]
            )
        )
        let second = ProxyNodeViewState(
            snapshot: ProxySnapshot(name: "Node Second", type: "WireGuard")
        )
        let group = ProxyGroupViewState(
            id: "Proxy",
            type: "Selector",
            selected: "Node First",
            options: ["Node Second", "Node First", "Node First"],
            optionDetails: [
                "Node First": first,
                "Node Second": second,
            ]
        )

        #expect(PolicyGroupPresentation.filteredOptions(in: group, matching: "remote provider") == ["Node First", "Node First"])
        #expect(PolicyGroupPresentation.filteredOptions(in: group, matching: "utun9") == ["Node First", "Node First"])
        #expect(PolicyGroupPresentation.filteredOptions(in: group, matching: "Tokyo") == ["Node First", "Node First"])
        #expect(PolicyGroupPresentation.filteredOptions(in: group, matching: "WireGuard") == ["Node Second"])
    }

    @Test func dashboardProjectsCompleteProxyDetailsAndHistoryDelay() throws {
        let proxyData = Data(#"""
        {
          "proxies": {
            "Proxy": {
              "type": "Selector",
              "now": "Node A",
              "all": ["Node A"],
              "fixed": "Node A",
              "testUrl": "https://www.gstatic.com/generate_204"
            },
            "Node A": {
              "type": "VLESS",
              "alive": true,
              "provider-name": "Remote Nodes",
              "udp": true,
              "xudp": true,
              "history": [{ "time": "2026-07-18T10:00:00Z", "delay": 64 }]
            }
          }
        }
        """#.utf8)
        let proxies = try ProxiesResponse.decodePreservingProxyOrder(from: proxyData)
        let version = try JSONDecoder().decode(VersionResponse.self, from: Data(#"{"version":"1.0"}"#.utf8))
        let config = try JSONDecoder().decode(ConfigResponse.self, from: Data(#"{"mode":"rule"}"#.utf8))
        let connections = try JSONDecoder().decode(ConnectionsResponse.self, from: Data(#"{"connections":[]}"#.utf8))

        let dashboard = DashboardSnapshot(
            version: version,
            config: config,
            proxies: proxies,
            connections: connections
        )
        let group = try #require(dashboard.groups.first)
        let node = try #require(group.detail(for: "Node A"))

        #expect(group.details?.fixed == "Node A")
        #expect(group.details?.testURL == "https://www.gstatic.com/generate_204")
        #expect(node.type == "VLESS")
        #expect(node.alive == true)
        #expect(node.providerName == "Remote Nodes")
        #expect(node.transportNames == ["UDP", "XUDP"])
        #expect(node.latestHistoryDelay == 64)
        #expect(node.latestHistoryTime == "2026-07-18T10:00:00Z")
    }

    @Test func singleNodeDelayUpdatePreservesGroupAndPeerDelayOrder() {
        var dashboard = DashboardSnapshot.empty
        dashboard.groups = [
            ProxyGroupViewState(
                id: "First",
                type: "Selector",
                selected: "Node A",
                options: ["Node A", "Node B"],
                delays: ["Node A": 40, "Node B": 80]
            ),
            group(id: "Second", type: "Selector", selected: "Node C", options: ["Node C"]),
        ]

        dashboard.replaceDelay(55, for: "Node A", in: "First")

        #expect(dashboard.groups.map(\.id) == ["First", "Second"])
        #expect(dashboard.groups[0].options == ["Node A", "Node B"])
        #expect(dashboard.groups[0].delays == ["Node A": 55, "Node B": 80])
    }

    @MainActor
    @Test func actionDashboardMutationStaysPendingWhilePresentationIsPaused() {
        let profile = RouterProfile(displayName: "Controller", host: "127.0.0.1")
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.dashboard.groups = [
            group(id: "Proxy", type: "Selector", selected: "Node A", options: ["Node A"]),
        ]
        model.dashboard.connections = [ConnectionSnapshot(id: "closed-while-paused")]
        var controls = model.dashboardSessionControls
        controls.setPresentationPaused(true)
        model.dashboardSessionControls = controls

        model.mutateSessionDashboard { dashboard in
            dashboard.replaceDelay(72, for: "Node A", in: "Proxy")
        }
        let closed = ConnectionSnapshot(id: "closed-while-paused")
        model.recordClosedSessionConnections([closed])
        model.removeSessionConnections([closed])

        #expect(model.dashboard.groups[0].delays.isEmpty)
        #expect(model.dashboard.connections.map(\.id) == ["closed-while-paused"])
        #expect(model.dashboardSessionControls.closedConnections.isEmpty)
        #expect(model.controllerSession.pendingPresentation.dashboard?.groups[0].delays == ["Node A": 72])
        #expect(model.controllerSession.pendingPresentation.dashboard?.connections.isEmpty == true)
        #expect(model.controllerSession.pendingPresentation.closedConnections.entries.map(\.id) == ["closed-while-paused"])
    }

    @MainActor
    @Test func surgeSnapshotApplyStaysPendingWhilePresentationIsPaused() {
        let profile = RouterProfile(
            displayName: "Surge",
            host: "127.0.0.1",
            controllerKind: .surgeCompatible
        )
        let model = AppModel(
            routers: [profile],
            selectedRouterID: profile.id,
            profileStore: InMemoryRouterProfileStore(),
            secretStore: InMemorySecretStore()
        )
        model.dashboard.versionLabel = "visible-before-pause"
        var controls = model.dashboardSessionControls
        controls.setPresentationPaused(true)
        model.dashboardSessionControls = controls
        let snapshot = SurgeControlSnapshot(
            outbound: SurgeOutboundResponse(mode: "global"),
            traffic: SurgeTrafficResponse(upload: 12, download: 34)
        )

        model.applySurgeSnapshot(snapshot, router: profile)

        #expect(model.dashboard.versionLabel == "visible-before-pause")
        #expect(model.surgeSnapshot == .empty)
        #expect(model.controllerSession.pendingPresentation.surgeSnapshot == snapshot)
        #expect(model.controllerSession.pendingPresentation.dashboard?.traffic == TrafficSnapshot(upload: 12, download: 34))
        #expect(model.controllerSession.pendingPresentation.unifiedSnapshot != nil)
    }

    @Test func controllerConfigMutationsMapToTypedPatchesAndOptimisticSnapshotFields() throws {
        var snapshot = DashboardConfigSnapshot()
        let mutations: [ControllerConfigMutation] = [
            .logLevel("warning"),
            .allowLAN(true),
            .ipv6(false),
            .tcpConcurrent(true),
            .tun(true),
            .port(.http, 7890),
            .port(.socks, 7891),
            .port(.redir, 7892),
            .port(.mixed, 7893),
        ]

        for mutation in mutations {
            mutation.apply(to: &snapshot)
        }

        #expect(snapshot.logLevel == "warning")
        #expect(snapshot.allowLan == true)
        #expect(snapshot.ipv6 == false)
        #expect(snapshot.tcpConcurrent == true)
        #expect(snapshot.tunEnabled == true)
        #expect(snapshot.port == 7890)
        #expect(snapshot.socksPort == 7891)
        #expect(snapshot.redirPort == 7892)
        #expect(snapshot.mixedPort == 7893)

        let encoded = try JSONEncoder().encode(ControllerConfigMutation.port(.mixed, 7893).patch)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Int])
        #expect(object == ["mixed-port": 7893])
    }

    @Test func policySelectionUsesGroupIdentityAcrossFilteringAndRefresh() {
        var presentation = PolicyGroupPresentation()
        let original = [
            group(id: "alpha", type: "Selector", selected: "A", options: ["A"]),
            group(id: "omega", type: "Selector", selected: "Long node", options: ["Long node"]),
        ]
        presentation.select("omega")

        let filtered = PolicyGroupPresentation.filteredGroups(original, matching: "alpha")
        #expect(filtered.map(\.id) == ["alpha"])
        presentation.reconcile(with: original)
        #expect(presentation.selectedPolicyGroupID == "omega")

        presentation.reconcile(with: [original[0]])
        #expect(presentation.selectedPolicyGroupID == "alpha")
    }

    @Test func longPolicyAndMemberTextRemainUnmodified() {
        let longGroup = "a-controller-reported-policy-group-name-that-must-not-be-truncated"
        let longMember = "a-controller-reported-node-name-that-must-remain-fully-visible"
        let groups = [group(id: longGroup, type: "Selector", selected: longMember, options: [longMember])]

        let filtered = PolicyGroupPresentation.filteredGroups(groups, matching: longMember)

        #expect(filtered.first?.id == longGroup)
        #expect(filtered.first?.options.first == longMember)
    }

    @Test func connectionProjectionPreservesSelectionAndFullControllerText() {
        let longPayload = "https://订阅.example/规则/非常长的路径?target=[2001:db8:85a3::8a2e:370:7334]"
        let selected = ConnectionSnapshot(
            id: "connection-二号-2001:db8::42",
            upload: 17,
            download: 31,
            uploadSpeed: 5,
            downloadSpeed: 9,
            start: "2026-07-11T10:00:00Z",
            chains: ["策略-北京", "Proxy-🇯🇵-完整节点名称"],
            providerChains: ["远程来源-A"],
            rule: "DOMAIN-SUFFIX",
            rulePayload: longPayload,
            metadata: ConnectionMetadataSnapshot(
                host: "长中文主机.example",
                network: "tcp",
                type: "HTTP",
                sourceIP: "2001:db8::1",
                destinationIP: "2001:db8::42",
                sourcePort: "65535",
                destinationPort: "443",
                process: "代理客户端",
                processPath: "/Applications/非常长的应用程序名称.app/Contents/MacOS/客户端",
                inboundIP: "::1",
                inboundPort: "7890",
                inboundName: "mixed-in",
                dnsMode: "redir-host",
                sniffHost: "完整嗅探主机.example",
                specialProxy: "特殊代理-完整名称",
                specialRules: "特殊规则-完整内容",
                remoteDestination: "remote.example:443",
                connectionLogs: ["连接建立", "控制器日志正文"],
                uid: 501,
                fields: ["controller-metadata": .string("完整元数据")]
            ),
            fields: ["controller-field": .string("完整顶层字段")]
        )
        let other = ConnectionSnapshot(id: "connection-one")

        let filtered = ConnectionWorkbenchPresentation.filtered([other, selected], matching: "2001:db8::42")

        #expect(filtered.map { $0.id } == [selected.id])
        #expect(filtered.first?.rulePayload == longPayload)
        #expect(filtered.first?.metadata?.processPath == "/Applications/非常长的应用程序名称.app/Contents/MacOS/客户端")
        #expect(ConnectionWorkbenchPresentation.filtered([other, selected], matching: "远程来源-A").map(\.id) == [selected.id])
        #expect(ConnectionWorkbenchPresentation.filtered([other, selected], matching: "控制器日志正文").map(\.id) == [selected.id])
        #expect(ConnectionWorkbenchPresentation.filtered([other, selected], matching: "完整元数据").map(\.id) == [selected.id])
        #expect(ConnectionWorkbenchPresentation.filtered([other, selected], matching: "完整顶层字段").map(\.id) == [selected.id])
        #expect(ConnectionWorkbenchPresentation.reconciledSelection(selected.id, in: [other, selected]) == selected.id)
        #expect(ConnectionWorkbenchPresentation.reconciledSelection(selected.id, in: [other]) == nil)
    }

    @Test func connectionOwnerGroupingUsesProcessThenSourceAndPreservesFirstSeenOrder() {
        let connections = [
            ConnectionSnapshot(
                id: "source-first",
                upload: 10,
                download: 20,
                uploadSpeed: 1,
                downloadSpeed: 2,
                metadata: ConnectionMetadataSnapshot(sourceIP: "192.0.2.10")
            ),
            ConnectionSnapshot(
                id: "process-a",
                upload: 30,
                download: 40,
                uploadSpeed: 3,
                downloadSpeed: 4,
                metadata: ConnectionMetadataSnapshot(
                    sourceIP: "192.0.2.11",
                    process: "Safari",
                    processPath: "/Applications/Safari.app/Contents/MacOS/Safari"
                )
            ),
            ConnectionSnapshot(
                id: "process-b",
                upload: 50,
                download: 60,
                uploadSpeed: 5,
                downloadSpeed: 6,
                metadata: ConnectionMetadataSnapshot(sourceIP: "192.0.2.12", process: "Safari")
            ),
            ConnectionSnapshot(
                id: "inner",
                metadata: ConnectionMetadataSnapshot(type: "Inner")
            ),
            ConnectionSnapshot(id: "unreported"),
        ]

        let groups = ConnectionWorkbenchPresentation.ownerGroups(connections)

        #expect(groups.map(\.owner) == [
            .source("192.0.2.10"),
            .process("Safari"),
            .inner,
            .unreported,
        ])
        #expect(groups[1].connections.map(\.id) == ["process-a", "process-b"])
        #expect(groups[1].upload == 80)
        #expect(groups[1].download == 100)
        #expect(groups[1].uploadSpeed == 8)
        #expect(groups[1].downloadSpeed == 10)
        #expect(groups[1].processPath == "/Applications/Safari.app/Contents/MacOS/Safari")
    }

    @Test func surgeActiveRequestsProjectCompleteConnectionFields() throws {
        let request = SurgeActiveRequest(
            id: "request-visible-id",
            method: "HTTPS",
            url: "example.com:443 (sni.example)",
            rule: "DOMAIN-SUFFIX example.com",
            ruleType: "DOMAIN-SUFFIX",
            rulePayload: "example.com",
            policy: "Node A",
            originalPolicy: "Proxy",
            upload: 1024,
            download: 2048,
            uploadSpeed: 128,
            downloadSpeed: 256,
            sourceAddress: "192.0.2.10",
            sourcePort: "54321",
            destinationAddress: "203.0.113.10",
            destinationPort: "443",
            localAddress: "127.0.0.1",
            interfaceName: "en0",
            process: "Safari",
            processPath: "/Applications/Safari.app/Contents/MacOS/Safari",
            uid: 501,
            notes: ["opened", "controller log"],
            status: "active",
            start: "2026-07-18T12:00:00Z",
            fields: ["controllerField": .string("full value")]
        )
        let snapshot = SurgeControlSnapshot(
            activeRequests: SurgeActiveRequestsResponse(requests: [request]),
            checkedAt: Date(timeIntervalSince1970: 10)
        )

        let dashboard = DashboardSnapshot(surge: snapshot, language: .english)
        let connection = try #require(dashboard.connections.first)

        #expect(connection.id == "request-visible-id")
        #expect(connection.chains == ["Node A", "Proxy"])
        #expect(connection.rule == "DOMAIN-SUFFIX")
        #expect(connection.rulePayload == "example.com")
        #expect(connection.uploadSpeed == 128)
        #expect(connection.downloadSpeed == 256)
        #expect(connection.start == "2026-07-18T12:00:00Z")
        #expect(connection.metadata?.sourceIP == "192.0.2.10")
        #expect(connection.metadata?.destinationIP == "203.0.113.10")
        #expect(connection.metadata?.process == "Safari")
        #expect(connection.metadata?.specialProxy == "Node A")
        #expect(connection.metadata?.specialRules == "active")
        #expect(connection.metadata?.connectionLogs == ["opened", "controller log"])
        #expect(connection.additionalFields["controllerField"] == .string("full value"))
    }

    @Test func dataSurfaceDistinguishesUnavailableEmptyAndFilteredEmpty() {
        #expect(WorkbenchDataSurfaceState.resolve(isUnavailable: true, sourceCount: 0, visibleCount: 0) == .unavailable)
        #expect(WorkbenchDataSurfaceState.resolve(isUnavailable: true, sourceCount: 2, visibleCount: 2) == .content)
        #expect(WorkbenchDataSurfaceState.resolve(isUnavailable: true, sourceCount: 2, visibleCount: 0) == .filteredEmpty)
        #expect(WorkbenchDataSurfaceState.resolve(isUnavailable: false, sourceCount: 0, visibleCount: 0) == .empty)
        #expect(WorkbenchDataSurfaceState.resolve(isUnavailable: false, sourceCount: 2, visibleCount: 0) == .filteredEmpty)
        #expect(WorkbenchDataSurfaceState.resolve(isUnavailable: false, sourceCount: 2, visibleCount: 1) == .content)
    }

    @Test func unavailableEnhancedDataReportsStaleWhenLastRowsRemain() {
        let state = EnhancedSnapshotState.unavailable("offline")

        #expect(
            state.summaryValue(count: 3, language: .english)
                == MicaStrings.localized("data.stale_count 3", language: .english)
        )
        #expect(
            state.summaryValue(count: 0, language: .simplifiedChinese)
                == MicaStrings.localized("snapshot.unavailable", language: .simplifiedChinese)
        )
    }

    @Test func rulesKeepPayloadFirstSourceOrderAndDistinctDuplicateRows() {
        let rules = [
            RuleViewState(id: "duplicate", type: "DOMAIN", payload: "第一条-长 CJK 规则载荷", proxy: "DIRECT", size: 1),
            RuleViewState(id: "duplicate", type: "DOMAIN", payload: "https://example.com/very/long/rule/payload", proxy: "Proxy-A", size: 2),
            RuleViewState(
                id: "third",
                index: 7,
                type: "IP-CIDR",
                payload: "2001:db8::/32",
                proxy: "Proxy-B",
                disabled: true,
                hitCount: 8,
                hitAt: "2026-07-18T10:00:00Z",
                missCount: 2,
                missAt: "2026-07-18T09:00:00Z",
                hasMutableExtra: true,
                extraMetadata: ["custom": .string("extra-value")],
                metadata: ["provider": .string("remote-rules")]
            ),
        ]

        let rows = RulesWorkbenchPresentation.rows(from: rules)
        let filtered = RulesWorkbenchPresentation.filtered(rows, matching: "2001:db8")

        #expect(rows.map { $0.id } == ["duplicate#0", "duplicate#1", "third#0"])
        #expect(rows.map { $0.rule.payload } == rules.map { $0.payload })
        #expect(filtered.map { $0.rule.payload } == ["2001:db8::/32"])
        #expect(RulesWorkbenchPresentation.filtered(rows, matching: "2026-07-18T10:00:00Z").map { $0.rule.id } == ["third"])
        #expect(RulesWorkbenchPresentation.filtered(rows, matching: "extra-value").map { $0.rule.id } == ["third"])
        #expect(RulesWorkbenchPresentation.filtered(rows, matching: "remote-rules").map { $0.rule.id } == ["third"])
        #expect(rules[2].hitRate == 0.8)
        #expect(RulesWorkbenchPresentation.reconciledSelection("duplicate#1", in: rows) == "duplicate#1")
    }

    @Test func dashboardProjectsCompleteRuleState() throws {
        let data = Data(#"""
        {
          "rules": [
            {
              "index": 4,
              "type": "DOMAIN",
              "payload": "full.example",
              "proxy": "Proxy",
              "extra": {
                "disabled": false,
                "hitCount": 5,
                "hitAt": "2026-07-18T10:00:00Z",
                "missCount": 1,
                "missAt": "2026-07-18T09:00:00Z",
                "note": "controller-extra"
              },
              "source": "controller-rule-set"
            }
          ]
        }
        """#.utf8)
        let response = try JSONDecoder().decode(RulesResponse.self, from: data)
        var dashboard = DashboardSnapshot.empty

        dashboard.replaceRules(with: response)

        let rule = try #require(dashboard.rules.first)
        #expect(rule.index == 4)
        #expect(rule.disabled == false)
        #expect(rule.hitCount == 5)
        #expect(rule.hitAt == "2026-07-18T10:00:00Z")
        #expect(rule.missCount == 1)
        #expect(rule.missAt == "2026-07-18T09:00:00Z")
        #expect(rule.hasMutableExtra)
        #expect(rule.additionalExtraText == #"{"note":"controller-extra"}"#)
        #expect(rule.additionalMetadataText == #"{"source":"controller-rule-set"}"#)
    }

    @Test func sourcesFilterByCategoryWithoutSortingAndExposeUpdateStates() {
        let sources = [
            ProxyProviderViewState(kind: .rule, name: "规则来源-第二", type: "http", behavior: "domain", format: "mrs", vehicleType: "HTTP", updatedAt: "2026-07-11", updatable: true, healthCheck: .object(["enable": .bool(true)]), itemCount: 3),
            ProxyProviderViewState(kind: .proxy, name: "代理来源-第一", type: "file", behavior: nil, vehicleType: "File", updatedAt: "2026-07-10", itemCount: 2),
            ProxyProviderViewState(kind: .rule, name: "规则来源-第三", type: "http", behavior: "ipcidr", vehicleType: "HTTP", updatedAt: "2026-07-09", itemCount: 4),
        ]

        let all = SourcesWorkbenchPresentation.filtered(sources, kind: .all, matching: "")
        let rules = SourcesWorkbenchPresentation.filtered(sources, kind: .rule, matching: "")

        #expect(all.map { $0.name } == sources.map { $0.name })
        #expect(rules.map { $0.name } == ["规则来源-第二", "规则来源-第三"])
        #expect(SourcesWorkbenchPresentation.filtered(sources, kind: .all, matching: "mrs").map(\.name) == ["规则来源-第二"])
        #expect(SourcesWorkbenchPresentation.filtered(sources, kind: .all, matching: "enable").map(\.name) == ["规则来源-第二"])
        #expect(sources[0].updatable)
        #expect(!sources[1].updatable)
        #expect(SourcesWorkbenchPresentation.updateState(sourceID: sources[0].id, updatingSourceID: sources[0].id, failures: [:]) == .updating)
        #expect(SourcesWorkbenchPresentation.updateState(sourceID: sources[1].id, updatingSourceID: nil, failures: [sources[1].id: "remote failed"]) == .failed("remote failed"))
        #expect(SourcesWorkbenchPresentation.updateState(sourceID: sources[2].id, updatingSourceID: nil, failures: [:]) == .ready)
    }

    @Test func logsKeepOriginalOrderFilterRawPayloadAndClearLocally() {
        let entries = [
            ControllerLogEntry(
                id: "older",
                receivedAt: Date(timeIntervalSince1970: 1),
                message: LogMessage(type: "info", payload: "第一条原始日志")
            ),
            ControllerLogEntry(
                id: "latest",
                receivedAt: Date(timeIntervalSince1970: 2),
                message: LogMessage(
                    type: "warning",
                    payload: "https://日志.example/完整?ipv6=2001:db8::7",
                    time: "2026-07-18T08:00:00Z",
                    level: "warning",
                    message: "https://日志.example/完整?ipv6=2001:db8::7",
                    fields: .object(["source": .string("controller")])
                )
            ),
        ]

        let visible = LogsWorkbenchPresentation.visible(entries, level: .all, matching: "")
        let filtered = LogsWorkbenchPresentation.visible(entries, level: .warning, matching: "2001:db8")

        #expect(visible.map { $0.id } == ["older", "latest"])
        #expect(visible.last?.id == "latest")
        #expect(filtered.first?.message.payload == "https://日志.example/完整?ipv6=2001:db8::7")
        #expect(LogsWorkbenchPresentation.visible(entries, level: .all, matching: "controller").map(\.id) == ["latest"])
        #expect(entries.last?.message.time == "2026-07-18T08:00:00Z")
        #expect(entries.last?.structuredFieldsText == #"{"source":"controller"}"#)
        #expect(LogsWorkbenchPresentation.clearedEntries().isEmpty)
    }

    @Test func logEmptyStatesKeepTitlesAndDescriptionsDistinct() {
        let empty = LogsWorkbenchPresentation.emptyState(isFiltering: false)
        let filtered = LogsWorkbenchPresentation.emptyState(isFiltering: true)

        #expect(empty.titleKey == "dashboard.no_logs_yet")
        #expect(empty.messageKey == "dashboard.no_logs_yet_message")
        #expect(filtered.titleKey == "dashboard.no_matching_logs")
        #expect(filtered.messageKey == "traffic.empty_filtered")
        #expect(empty.titleKey != empty.messageKey)
        #expect(filtered.titleKey != filtered.messageKey)

        for language in [AppLanguage.english, .simplifiedChinese] {
            #expect(
                MicaStrings.localizedKey(empty.titleKey, language: language)
                    != MicaStrings.localizedKey(empty.messageKey, language: language)
            )
            #expect(
                MicaStrings.localizedKey(filtered.titleKey, language: language)
                    != MicaStrings.localizedKey(filtered.messageKey, language: language)
            )
        }
    }

    @Test func controllerTargetsAvoidPlaceholderEndpointsAndFormatIPv6() {
        var draft = RouterDraft(
            displayName: "IPv6 Controller",
            scheme: .https,
            host: "",
            portText: "8443"
        )

        #expect(
            draft.visibleControllerTargetLabel(language: .english)
                == MicaStrings.localized("editor.target_not_configured", language: .english)
        )

        draft.host = "2001:db8::42"
        #expect(draft.controllerURLLabel == "https://[2001:db8::42]:8443")
        #expect(draft.visibleControllerTargetLabel(language: .english).contains("https://[2001:db8::42]:8443"))

        let profile = RouterProfile(
            displayName: "IPv6 Controller",
            scheme: .https,
            host: "2001:db8::42",
            port: 8443
        )
        #expect(profile.endpointURL == "https://[2001:db8::42]:8443")
    }

    @Test func legacyNavigationMigratesEveryAreaAndSectionCombination() {
        // overview / proxies map directly.
        #expect(WorkbenchDestination.migrated(fromArea: "overview", activitySection: nil, resourcesSection: nil, systemSection: nil) == .overview)
        #expect(WorkbenchDestination.migrated(fromArea: "proxies", activitySection: nil, resourcesSection: nil, systemSection: nil) == .proxies)

        // activity splits into connections / logs.
        #expect(WorkbenchDestination.migrated(fromArea: "activity", activitySection: "connections", resourcesSection: nil, systemSection: nil) == .connections)
        #expect(WorkbenchDestination.migrated(fromArea: "activity", activitySection: "logs", resourcesSection: nil, systemSection: nil) == .logs)
        #expect(WorkbenchDestination.migrated(fromArea: "activity", activitySection: nil, resourcesSection: nil, systemSection: nil) == .connections)

        // resources splits into rules / sources.
        #expect(WorkbenchDestination.migrated(fromArea: "resources", activitySection: nil, resourcesSection: "rules", systemSection: nil) == .rules)
        #expect(WorkbenchDestination.migrated(fromArea: "resources", activitySection: nil, resourcesSection: "sources", systemSection: nil) == .sources)
        #expect(WorkbenchDestination.migrated(fromArea: "resources", activitySection: nil, resourcesSection: nil, systemSection: nil) == .rules)

        // system splits into configuration / actions / diagnostics / settings.
        #expect(WorkbenchDestination.migrated(fromArea: "system", activitySection: nil, resourcesSection: nil, systemSection: "configuration") == .configuration)
        #expect(WorkbenchDestination.migrated(fromArea: "system", activitySection: nil, resourcesSection: nil, systemSection: "actions") == .actions)
        #expect(WorkbenchDestination.migrated(fromArea: "system", activitySection: nil, resourcesSection: nil, systemSection: "diagnostics") == .diagnostics)
        #expect(WorkbenchDestination.migrated(fromArea: "system", activitySection: nil, resourcesSection: nil, systemSection: "settings") == .settings)
        #expect(WorkbenchDestination.migrated(fromArea: "system", activitySection: nil, resourcesSection: nil, systemSection: nil) == .configuration)
    }

    @Test func legacyNavigationMigrationFallsBackToOverview() {
        #expect(WorkbenchDestination.migrated(fromArea: nil, activitySection: nil, resourcesSection: nil, systemSection: nil) == .overview)
        #expect(WorkbenchDestination.migrated(fromArea: "unknown-area", activitySection: nil, resourcesSection: nil, systemSection: nil) == .overview)
    }

    @Test func legacyNavigationMigrationHonorsOlderDestinationStrings() {
        // The pre-five-area single string key falls through the area switch's default.
        #expect(WorkbenchDestination.migrated(fromArea: "policyGroups", activitySection: nil, resourcesSection: nil, systemSection: nil) == .proxies)
        #expect(WorkbenchDestination.migrated(fromArea: "coreConfig", activitySection: nil, resourcesSection: nil, systemSection: nil) == .configuration)
        #expect(WorkbenchDestination.migrated(fromArea: "coreActions", activitySection: nil, resourcesSection: nil, systemSection: nil) == .actions)
        #expect(WorkbenchDestination.migrated(fromArea: "tailscale", activitySection: nil, resourcesSection: nil, systemSection: nil) == .diagnostics)
        #expect(WorkbenchDestination.migrated(fromArea: "settings", activitySection: nil, resourcesSection: nil, systemSection: nil) == .settings)
    }

    @Test func workbenchTabCasesCoverSixShortcutDestinationsInOrder() {
        #expect(WorkbenchDestination.workbenchTabCases == [.overview, .proxies, .connections, .logs, .rules, .sources])
        #expect(WorkbenchDestination.workbenchTabCases.allSatisfy { $0.shortcut != nil })
        #expect(WorkbenchDestination.workbenchTabCases.allSatisfy { $0.group == .workbench })
        // Non-workbench destinations do not bind number keys.
        for destination in [WorkbenchDestination.configuration, .actions, .diagnostics, .settings] {
            #expect(destination.shortcut == nil)
        }
    }

    @Test func connectionSortingReturnsReorderedCopyWithoutMutatingSource() {
        let source = [
            ConnectionSnapshot(id: "a", upload: 10, download: 0, start: "2026-07-11T10:00:00Z"),
            ConnectionSnapshot(id: "b", upload: 90, download: 0, start: "2026-07-11T09:00:00Z"),
            ConnectionSnapshot(id: "c", upload: 50, download: 0, start: "2026-07-11T11:00:00Z"),
        ]
        let originalOrder = source.map(\.id)

        let byUpload = ConnectionWorkbenchPresentation.ordered(
            source,
            using: [KeyPathComparator(\ConnectionSnapshot.sortableUpload, order: .reverse)]
        )

        #expect(byUpload.map(\.id) == ["b", "c", "a"])
        // Source collection identity/order is unchanged.
        #expect(source.map(\.id) == originalOrder)
    }

    @Test func connectionSortingWithNoComparatorsKeepsSourceOrder() {
        let source = [
            ConnectionSnapshot(id: "a"),
            ConnectionSnapshot(id: "b"),
            ConnectionSnapshot(id: "c"),
        ]

        let sorted = ConnectionWorkbenchPresentation.ordered(source, using: [])

        #expect(sorted.map(\.id) == ["a", "b", "c"])
    }

    @Test func connectionSortComparatorStableOnNilFields() {
        let source = [
            ConnectionSnapshot(id: "a", upload: nil, download: nil),
            ConnectionSnapshot(id: "b", upload: 5, download: nil),
        ]

        // Nil upload maps to 0 and does not crash or lose rows.
        let sorted = ConnectionWorkbenchPresentation.ordered(
            source,
            using: [KeyPathComparator(\ConnectionSnapshot.sortableUpload, order: .forward)]
        )

        #expect(Set(sorted.map(\.id)) == ["a", "b"])
        #expect(sorted.first?.id == "a")
    }

    @Test func ruleSortingReturnsReorderedCopyWithoutMutatingSource() {
        let rows = RulesWorkbenchPresentation.rows(from: [
            RuleViewState(id: "1", type: "DOMAIN", payload: "gamma", proxy: "P", size: 3),
            RuleViewState(id: "2", type: "DOMAIN", payload: "alpha", proxy: "P", size: 1),
            RuleViewState(id: "3", type: "DOMAIN", payload: "beta", proxy: "P", size: 2),
        ])
        let originalOrder = rows.map(\.id)

        let sorted = RulesWorkbenchPresentation.ordered(
            rows,
            using: [KeyPathComparator(\WorkbenchRuleRow.sortablePayload, order: .forward)]
        )

        #expect(sorted.map(\.rule.payload) == ["alpha", "beta", "gamma"])
        #expect(rows.map(\.id) == originalOrder)
    }

    @Test func sourceSortingReturnsReorderedCopyWithoutMutatingSource() {
        let sources = [
            ProxyProviderViewState(kind: .rule, name: "gamma", type: "http", updatedAt: nil, itemCount: 3),
            ProxyProviderViewState(kind: .proxy, name: "alpha", type: "file", updatedAt: nil, itemCount: 1),
            ProxyProviderViewState(kind: .rule, name: "beta", type: "http", updatedAt: nil, itemCount: 2),
        ]
        let originalOrder = sources.map(\.name)

        let sorted = SourcesWorkbenchPresentation.ordered(
            sources,
            using: [KeyPathComparator(\ProxyProviderViewState.sortableItemCount, order: .reverse)]
        )

        #expect(sorted.map(\.name) == ["gamma", "beta", "alpha"])
        #expect(sources.map(\.name) == originalOrder)
    }

    @Test func insightEmptyStatePredicatesReflectSnapshotData() {
        let empty = InsightSummarySnapshot.empty
        #expect(empty.hasLatencySamples == false)
        #expect(empty.hasConnectionDistribution == false)
        #expect(empty.topConnections.isEmpty)

        let populated = InsightSummarySnapshot(
            connectionDistribution: [InsightSlice(label: "DOMAIN", value: 3)],
            routeHealth: [LatencyHealthBucket(grade: .fast, count: 2)],
            topConnections: [ConnectionSnapshot(id: "top", upload: 10, download: 5)],
            latencySampleCount: 2
        )
        #expect(populated.hasLatencySamples)
        #expect(populated.hasConnectionDistribution)
        #expect(populated.topConnections.isEmpty == false)
    }

    @Test func refreshLoadedStatusResolvesLocalizedSummaryWithCounts() {
        let english = MicaStrings.localized("operation.refresh_loaded \(63) \(101) \(99)", language: .english)
        #expect(english.contains("63"))
        #expect(english.contains("groups"))

        let chinese = MicaStrings.localized("operation.refresh_loaded \(63) \(101) \(99)", language: .simplifiedChinese)
        #expect(chinese.contains("已加载"))
    }

    @Test func sourceUpdatedAtClassifiesGoZeroTimeAsNeverUpdated() {
        #expect(SourcesWorkbenchPresentation.classifyUpdatedAt("0001-01-01T00:00:00Z") == .neverUpdated)
    }

    @Test func sourceUpdatedAtClassifiesValidTimestampAsUpdated() {
        let classified = SourcesWorkbenchPresentation.classifyUpdatedAt("2026-07-11T09:26:56.933842246+08:00")
        guard case let .updated(date) = classified else {
            Issue.record("Expected .updated, got \(classified)")
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        #expect(calendar.component(.year, from: date) == 2026)
    }

    @Test func sourceUpdatedAtClassifiesMissingValuesAsNotReported() {
        #expect(SourcesWorkbenchPresentation.classifyUpdatedAt(nil) == .notReported)
        #expect(SourcesWorkbenchPresentation.classifyUpdatedAt("  ") == .notReported)
    }

    @Test func sourceUpdatedAtSurfacesUnparseableTextVerbatim() {
        #expect(SourcesWorkbenchPresentation.classifyUpdatedAt("recently") == .reported("recently"))
    }

    @Test func byteCountFormatterProducesNumericZeroNotWordZero() {
        let formatter = ByteCountFormatter()
        formatter.allowsNonnumericFormatting = false
        formatter.countStyle = .binary
        let result = formatter.string(fromByteCount: 0)
        #expect(!result.lowercased().contains("zero"))
        #expect(result.starts(with: "0 "))
    }

    @Test func arrangedGroupsPlacesGlobalLastInGlobalModeAndKeepsOtherOrder() {
        let groups = [
            group(id: "Proxy", type: "Selector", selected: "A", options: ["A"]),
            group(id: "GLOBAL", type: "Selector", selected: "Auto", options: ["Auto"]),
            group(id: "Streaming", type: "URLTest", selected: "B", options: ["B"]),
        ]

        let arranged = PolicyGroupPresentation.arrangedGroups(groups, mode: "Global", visibility: .followMode)

        #expect(arranged.map(\.id) == ["Proxy", "Streaming", "GLOBAL"])
    }

    @Test func arrangedGroupsRemovesGlobalInNonGlobalModeAndKeepsOtherOrder() {
        let groups = [
            group(id: "Proxy", type: "Selector", selected: "A", options: ["A"]),
            group(id: "GLOBAL", type: "Selector", selected: "Auto", options: ["Auto"]),
            group(id: "Streaming", type: "URLTest", selected: "B", options: ["B"]),
        ]

        #expect(PolicyGroupPresentation.arrangedGroups(groups, mode: "Rule", visibility: .followMode).map(\.id) == ["Proxy", "Streaming"])
        #expect(PolicyGroupPresentation.arrangedGroups(groups, mode: "Direct", visibility: .followMode).map(\.id) == ["Proxy", "Streaming"])
    }

    @Test func arrangedGroupsAlwaysShowPlacesGlobalLastRegardlessOfMode() {
        let groups = [
            group(id: "Proxy", type: "Selector", selected: "A", options: ["A"]),
            group(id: "GLOBAL", type: "Selector", selected: "Auto", options: ["Auto"]),
        ]

        #expect(PolicyGroupPresentation.arrangedGroups(groups, mode: "Rule", visibility: .alwaysShow).map(\.id) == ["Proxy", "GLOBAL"])
        #expect(PolicyGroupPresentation.arrangedGroups(groups, mode: "Global", visibility: .alwaysShow).map(\.id) == ["Proxy", "GLOBAL"])
    }

    @Test func arrangedGroupsWithoutGlobalReturnsInputOrderUnchanged() {
        let groups = [
            group(id: "Proxy", type: "Selector", selected: "A", options: ["A"]),
            group(id: "Streaming", type: "URLTest", selected: "B", options: ["B"]),
        ]

        #expect(PolicyGroupPresentation.arrangedGroups(groups, mode: "Global", visibility: .followMode).map(\.id) == ["Proxy", "Streaming"])
        #expect(PolicyGroupPresentation.arrangedGroups(groups, mode: "Rule", visibility: .alwaysShow).map(\.id) == ["Proxy", "Streaming"])
    }

    @Test func arrangedGroupsPreservesNonGlobalRelativeOrderIdentity() {
        let groups = [
            group(id: "Third", type: "Selector", selected: "C", options: ["C"]),
            group(id: "First", type: "Selector", selected: "A", options: ["A"]),
            group(id: "GLOBAL", type: "Selector", selected: "Auto", options: ["Auto"]),
            group(id: "Second", type: "URLTest", selected: "B", options: ["B"]),
        ]

        // Non-GLOBAL groups keep their exact incoming order (which is not alphabetical),
        // proving the arrangement never sorts; it only partitions GLOBAL to the end.
        let arranged = PolicyGroupPresentation.arrangedGroups(groups, mode: "Global", visibility: .followMode)
        #expect(arranged.map(\.id) == ["Third", "First", "Second", "GLOBAL"])
    }

    private func group(id: String, type: String, selected: String, options: [String]) -> ProxyGroupViewState {
        ProxyGroupViewState(id: id, type: type, selected: selected, options: options)
    }
}
