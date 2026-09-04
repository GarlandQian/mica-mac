import Foundation
import MicaCore
import Testing
@testable import Mica

struct WorkbenchTimelineAndProxyTests {
    @Test func trafficTimelineUsesOnlyReceivedSamplesAndEnforcesCapacity() {
        var timeline = TrafficTimeline(capacity: 3)

        for index in 0..<4 {
            timeline.append(
                upload: index * 10,
                download: index * 20,
                receivedAt: Date(timeIntervalSince1970: Double(index))
            )
        }

        #expect(timeline.samples.map(\.id) == [1, 2, 3])
        #expect(timeline.samples.map(\.upload) == [10, 20, 30])
        #expect(timeline.samples.map(\.download) == [20, 40, 60])
    }

    @Test func timelinesEnforceFiveMinuteRetentionAndResetIdentity() {
        var traffic = TrafficTimeline()
        traffic.append(upload: 1, download: 2, receivedAt: Date(timeIntervalSince1970: 0))
        traffic.append(upload: 3, download: 4, receivedAt: Date(timeIntervalSince1970: 301))
        #expect(traffic.samples.map(\.upload) == [3])

        traffic.reset()
        traffic.append(upload: -1, download: -2, receivedAt: Date(timeIntervalSince1970: 400))
        #expect(traffic.samples.map(\.id) == [0])
        #expect(traffic.samples.map(\.upload) == [0])
        #expect(traffic.samples.map(\.download) == [0])

        var memory = MemoryTimeline(capacity: 2)
        memory.append(inUseBytes: 1, receivedAt: Date(timeIntervalSince1970: 0))
        memory.append(inUseBytes: 2, receivedAt: Date(timeIntervalSince1970: 300))
        memory.append(inUseBytes: 3, receivedAt: Date(timeIntervalSince1970: 301))
        #expect(memory.samples.map(\.inUseBytes) == [2, 3])

        memory.reset()
        memory.append(inUseBytes: -1, receivedAt: Date(timeIntervalSince1970: 500))
        #expect(memory.samples.map(\.id) == [0])
        #expect(memory.samples.map(\.inUseBytes) == [0])

        var connections = ConnectionCountTimeline(capacity: 2)
        connections.append(activeCount: 1, receivedAt: Date(timeIntervalSince1970: 0))
        connections.append(activeCount: 2, receivedAt: Date(timeIntervalSince1970: 300))
        connections.append(activeCount: 3, receivedAt: Date(timeIntervalSince1970: 301))
        #expect(connections.samples.map(\.activeCount) == [2, 3])

        connections.reset()
        connections.append(activeCount: -1, receivedAt: Date(timeIntervalSince1970: 500))
        #expect(connections.samples.map(\.id) == [0])
        #expect(connections.samples.map(\.activeCount) == [0])
    }

    @Test func overviewZeroByteFormattingIsDeterministic() {
        #expect(OverviewFormat.bytes(0) == "0 B")
        #expect(OverviewFormat.bytes(-1) == "0 B")
        #expect(OverviewFormat.rate(0) == "0 B/s")
        #expect(OverviewFormat.bytes(1_024) != "0 B")
    }

    @Test func overviewTimestampFormattingRejectsUnixEpochSentinels() {
        let firstMeaningfulDate = Date(timeIntervalSince1970: 31_536_000)

        #expect(OverviewFormat.displayableTimestamp(nil) == nil)
        #expect(
            OverviewFormat.displayableTimestamp(Date(timeIntervalSince1970: 0)) == nil
        )
        #expect(
            OverviewFormat.displayableTimestamp(Date(timeIntervalSince1970: 31_535_999)) == nil
        )
        #expect(
            OverviewFormat.displayableTimestamp(firstMeaningfulDate) == firstMeaningfulDate
        )
    }

    @Test func overviewTimelineWindowsFilterOnlyReceivedSamplesFromLatestTimestamp() {
        let traffic = [0, 60, 120, 240, 300].enumerated().map { index, second in
            TrafficTimeline.Sample(
                id: index,
                receivedAt: Date(timeIntervalSince1970: TimeInterval(second)),
                upload: index,
                download: index * 2
            )
        }
        let memory = traffic.map {
            MemoryTimeline.Sample(
                id: $0.id,
                receivedAt: $0.receivedAt,
                inUseBytes: $0.download,
                source: .memoryEndpoint
            )
        }
        let connections = traffic.map {
            ConnectionCountTimeline.Sample(
                id: $0.id,
                receivedAt: $0.receivedAt,
                activeCount: $0.download
            )
        }

        #expect(
            OverviewTimelineProjection.trafficSamples(traffic, window: .oneMinute)
                .map(\.id) == [3, 4]
        )
        #expect(
            OverviewTimelineProjection.trafficSamples(traffic, window: .threeMinutes)
                .map(\.id) == [2, 3, 4]
        )
        #expect(
            OverviewTimelineProjection.memorySamples(memory, window: .fiveMinutes)
                .map(\.id) == [0, 1, 2, 3, 4]
        )
        #expect(
            OverviewTimelineProjection.connectionSamples(
                connections,
                window: .oneMinute
            ).map(\.id) == [3, 4]
        )
    }

    @Test func overviewTimelineSelectionSnapsToNearestReceivedSample() {
        let traffic = [
            TrafficTimeline.Sample(
                id: 0,
                receivedAt: Date(timeIntervalSince1970: 10),
                upload: 1,
                download: 2
            ),
            TrafficTimeline.Sample(
                id: 1,
                receivedAt: Date(timeIntervalSince1970: 20),
                upload: 3,
                download: 4
            ),
        ]
        let memory = traffic.map {
            MemoryTimeline.Sample(
                id: $0.id,
                receivedAt: $0.receivedAt,
                inUseBytes: $0.download,
                source: .memoryEndpoint
            )
        }
        let connections = traffic.map {
            ConnectionCountTimeline.Sample(
                id: $0.id,
                receivedAt: $0.receivedAt,
                activeCount: $0.download
            )
        }

        #expect(
            OverviewTimelineProjection.nearestTrafficSample(
                to: Date(timeIntervalSince1970: 18),
                in: traffic
            )?.id == 1
        )
        #expect(
            OverviewTimelineProjection.nearestMemorySample(
                to: Date(timeIntervalSince1970: 11),
                in: memory
            )?.id == 0
        )
        #expect(
            OverviewTimelineProjection.nearestConnectionSample(
                to: Date(timeIntervalSince1970: 18),
                in: connections
            )?.id == 1
        )

        let dates = traffic.map(\.receivedAt)
        #expect(
            OverviewTimelineProjection.nearestDateIndex(
                to: Date(timeIntervalSince1970: 18),
                in: dates
            ) == 1
        )
        #expect(
            OverviewTimelineProjection.nearestDateIndex(
                to: Date(timeIntervalSince1970: 15),
                in: dates
            ) == 0
        )
        #expect(
            OverviewTimelineProjection.nearestDateIndex(
                to: Date(timeIntervalSince1970: 30),
                in: dates
            ) == 1
        )
        #expect(
            OverviewTimelineProjection.nearestDateIndex(
                to: Date(timeIntervalSince1970: 30),
                in: []
            ) == nil
        )

        let interleavedMemory = [
            MemoryTimeline.Sample(
                id: 2,
                receivedAt: Date(timeIntervalSince1970: 15),
                inUseBytes: 5,
                source: .memoryEndpoint
            ),
            MemoryTimeline.Sample(
                id: 3,
                receivedAt: Date(timeIntervalSince1970: 20),
                inUseBytes: 6,
                source: .memoryEndpoint
            ),
        ]
        #expect(
            OverviewTimelineProjection.mergedDates(
                traffic: traffic,
                memory: interleavedMemory,
                connections: [
                    ConnectionCountTimeline.Sample(
                        id: 4,
                        receivedAt: Date(timeIntervalSince1970: 12),
                        activeCount: 1
                    ),
                ]
            ) == [
                Date(timeIntervalSince1970: 10),
                Date(timeIntervalSince1970: 12),
                Date(timeIntervalSince1970: 15),
                Date(timeIntervalSince1970: 20),
            ]
        )
    }

    @Test func proxyGroupsPreserveControllerOrderAndAppendVisibleGlobalLast() {
        let groups = [
            Self.group(id: "A", selected: "A-1"),
            Self.group(id: "GLOBAL", selected: "B", options: ["B", "A", "B"]),
            Self.group(id: "B", selected: "B-1"),
            Self.group(id: "A", selected: "A-2"),
            Self.group(id: "C", selected: "C-1"),
        ]

        let arranged = ProxyProjection.arrangedGroups(
            groups,
            mode: "Global",
            visibility: .followMode
        )

        #expect(arranged.map { $0.group.id } == ["A", "B", "A", "C", "GLOBAL"])
        #expect(arranged.map { $0.group.selected } == ["A-1", "B-1", "A-2", "C-1", "B"])
        #expect(arranged.map(\.key.occurrence) == [0, 0, 1, 0, 0])
        #expect(groups.map(\.id) == ["A", "GLOBAL", "B", "A", "C"])
    }

    @Test func policyRefreshUsesLatestMihomoConfigurationAndMemberOrder() {
        var dashboard = DashboardSnapshot(
            versionLabel: "test",
            mode: "Rule",
            traffic: TrafficSnapshot(upload: 0, download: 0),
            groups: [
                Self.group(
                    id: "Beta",
                    selected: "Beta 2",
                    options: ["Beta 2", "Removed", "Beta 1"]
                ),
                Self.group(
                    id: "GLOBAL",
                    selected: "Beta",
                    options: ["Beta", "Alpha"]
                ),
                Self.group(
                    id: "Alpha",
                    selected: "Alpha 1"
                ),
            ],
            connections: []
        )
        let refreshed = ProxiesResponse(
            proxies: [
                "Alpha": ProxySnapshot(
                    name: "Alpha",
                    type: "Selector",
                    now: "Alpha 1",
                    all: ["Alpha 1"]
                ),
                "Beta": ProxySnapshot(
                    name: "Beta",
                    type: "Selector",
                    now: "Beta 1",
                    all: ["Beta 1", "Beta 3", "Beta 2"]
                ),
                "Gamma": ProxySnapshot(
                    name: "Gamma",
                    type: "Selector",
                    now: "Gamma 1",
                    all: ["Gamma 1"]
                ),
                "Delta": ProxySnapshot(
                    name: "Delta",
                    type: "Selector",
                    now: "Delta 1",
                    all: ["Delta 1"]
                ),
                "Zeta": ProxySnapshot(
                    name: "Zeta",
                    type: "Selector",
                    now: "Zeta 1",
                    all: ["Zeta 1"]
                ),
                "GLOBAL": ProxySnapshot(
                    name: "GLOBAL",
                    type: "Selector",
                    now: "Alpha",
                    all: ["Gamma", "Alpha", "Beta"]
                ),
            ],
            proxyOrder: ["Alpha", "GLOBAL", "Zeta", "Beta", "Delta", "Gamma"]
        )

        dashboard.replaceGroups(with: refreshed)

        #expect(
            refreshed.policyGroups.map(\.name)
                == ["Alpha", "GLOBAL", "Zeta", "Beta", "Delta", "Gamma"]
        )
        #expect(
            dashboard.groups.map(\.id)
                == ["Gamma", "Alpha", "Beta", "Zeta", "Delta", "GLOBAL"]
        )
        #expect(dashboard.groups[2].options == ["Beta 1", "Beta 3", "Beta 2"])
        #expect(dashboard.groups[2].selected == "Beta 1")
        #expect(
            ProxyProjection.arrangedGroups(
                dashboard.groups,
                mode: dashboard.mode,
                visibility: .alwaysShow
            ).map { $0.group.id }
                == ["Gamma", "Alpha", "Beta", "Zeta", "Delta", "GLOBAL"]
        )
    }

    @Test func globalVisibilityAndFilteringChangeOnlyPresentation() {
        let groups = [
            Self.group(id: "Alpha", selected: "Node A"),
            Self.group(id: "GLOBAL", selected: "Alpha", options: ["Alpha"]),
            Self.group(id: "Beta", selected: "Node B"),
        ]

        let hiddenGlobal = ProxyProjection.arrangedGroups(
            groups,
            mode: "Rule",
            visibility: .followMode
        )
        #expect(hiddenGlobal.map { $0.group.id } == ["Alpha", "Beta"])

        let visibleGlobal = ProxyProjection.arrangedGroups(
            groups,
            mode: "Rule",
            visibility: .alwaysShow
        )
        #expect(visibleGlobal.map { $0.group.id } == ["Alpha", "Beta", "GLOBAL"])
        #expect(
            ProxyProjection.filteredGroups(visibleGlobal, query: "node b")
                .map { $0.group.id } == ["Beta"]
        )
        #expect(groups.map(\.id) == ["Alpha", "GLOBAL", "Beta"])
    }

    @Test func globalGroupSearchMatchesMembersAndMetadataWithoutReordering() {
        let firstDetail = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "Tokyo Edge",
                type: "VLESS",
                providerName: "Shared Provider",
                interfaceName: "utun7"
            )
        )
        let thirdDetail = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "Singapore Edge",
                type: "VLESS",
                providerName: "Shared Provider",
                interfaceName: "utun7"
            )
        )
        let groups = [
            ProxyGroupViewState(
                id: "First",
                type: "Selector",
                selected: "Tokyo Edge",
                options: ["Tokyo Edge"],
                optionDetails: ["Tokyo Edge": firstDetail]
            ),
            Self.group(
                id: "Second",
                selected: "Berlin Core",
                options: ["Berlin Core", "Fallback"]
            ),
            ProxyGroupViewState(
                id: "Third",
                type: "Selector",
                selected: "Singapore Edge",
                options: ["Singapore Edge"],
                optionDetails: ["Singapore Edge": thirdDetail]
            ),
        ]
        let arranged = ProxyProjection.arrangedGroups(
            groups,
            mode: "Rule",
            visibility: .alwaysShow
        )

        #expect(
            ProxyProjection.filteredGroups(arranged, query: "Fallback")
                .map { $0.group.id } == ["Second"]
        )
        #expect(
            ProxyProjection.filteredGroups(arranged, query: "Shared Provider")
                .map { $0.group.id } == ["First", "Third"]
        )
        #expect(
            ProxyProjection.filteredGroups(arranged, query: "utun7")
                .map { $0.group.id } == ["First", "Third"]
        )
        #expect(arranged.map { $0.group.id } == ["First", "Second", "Third"])
        #expect(groups.map(\.id) == ["First", "Second", "Third"])
    }

    @Test func proxyCatalogProjectionCachesOrderedGroupsForCurrentQuery() {
        let detail = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "M\u{00FC}nchen Edge",
                type: "VLESS",
                metadata: ["region": .string("S\u{00E3}o Paulo")]
            )
        )
        let catalog = PolicyGroupCatalogSnapshot(
            mode: "Rule",
            groups: [
                ProxyGroupViewState(
                    id: "First",
                    type: "Selector",
                    selected: "M\u{00FC}nchen Edge",
                    options: ["M\u{00FC}nchen Edge"],
                    optionDetails: ["M\u{00FC}nchen Edge": detail]
                ),
                Self.group(id: "GLOBAL", selected: "Second", options: ["Second"]),
                Self.group(id: "Second", selected: "Berlin Core"),
            ]
        )

        let projection = ProxyGroupCatalogProjection(
            catalog: catalog,
            visibility: .alwaysShow,
            query: "sao paulo"
        )

        #expect(projection.arrangedGroups.map { $0.group.id } == ["First", "Second", "GLOBAL"])
        #expect(projection.visibleGroups.map { $0.group.id } == ["First"])
        #expect(catalog.groups.map(\.id) == ["First", "GLOBAL", "Second"])
    }

    @Test func proxyOpenPathsStayInControllerOrderAndOnlyActiveMembersProject() throws {
        let arranged = ProxyProjection.arrangedGroups(
            [
                Self.group(id: "A", selected: "A-1", options: ["A-1", "A-2"]),
                Self.group(id: "GLOBAL", selected: "A", options: ["A", "B"]),
                Self.group(id: "B", selected: "B-1", options: ["B-1", "B-2"]),
                Self.group(id: "C", selected: "C-1", options: ["C-1", "C-2"]),
            ],
            mode: "Global",
            visibility: .followMode
        )
        let groupA = try #require(arranged.first { $0.group.id == "A" })
        let groupB = try #require(arranged.first { $0.group.id == "B" })
        let groupC = try #require(arranged.first { $0.group.id == "C" })
        let global = try #require(arranged.first { $0.group.id == "GLOBAL" })

        var workspace = WorkbenchDestinationWorkspace()
        for group in [groupC, groupA, global, groupB] {
            workspace = ProxyWorkspaceProjection.opening(
                group.id,
                in: workspace,
                groups: arranged,
                preferredMemberID: ProxyProjection.preferredMemberID(in: group.group)
            )
        }

        #expect(
            workspace.openGroupIDs
                == [groupA.id, groupB.id, groupC.id, global.id]
        )
        #expect(workspace.activeGroupID == groupB.id)

        workspace.groupFilters[groupB.id] = "B-2"
        let active = ProxyProjection.activeGroup(
            in: arranged,
            groupID: workspace.activeGroupID,
            query: workspace.groupFilters[groupB.id] ?? ""
        )

        #expect(active.occurrence?.group.id == "B")
        #expect(active.members.map(\.name) == ["B-2"])
        #expect(!active.members.contains { $0.name.hasPrefix("A-") })
        #expect(!active.members.contains { $0.name.hasPrefix("C-") })
    }

    @Test func closingActiveProxyTabPrefersNextThenPrevious() {
        let arranged = ProxyProjection.arrangedGroups(
            [
                Self.group(id: "A", selected: "A-1"),
                Self.group(id: "B", selected: "B-1"),
                Self.group(id: "C", selected: "C-1"),
            ],
            mode: "Rule",
            visibility: .followMode
        )
        var workspace = WorkbenchDestinationWorkspace()
        for group in arranged {
            workspace = ProxyWorkspaceProjection.opening(
                group.id,
                in: workspace,
                groups: arranged,
                preferredMemberID: ProxyProjection.preferredMemberID(in: group.group)
            )
        }
        workspace.activeGroupID = arranged[1].id

        workspace = ProxyWorkspaceProjection.closing(
            arranged[1].id,
            in: workspace,
            groups: arranged
        )
        #expect(workspace.activeGroupID == arranged[2].id)

        workspace = ProxyWorkspaceProjection.closing(
            arranged[2].id,
            in: workspace,
            groups: arranged
        )
        #expect(workspace.activeGroupID == arranged[0].id)
    }

    @Test func proxyNodeSearchTextIsPrecomputedAndNormalized() {
        var detail = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "M\u{00FC}nchen Edge",
                type: "VLESS",
                providerName: "Shared Provider",
                metadata: ["region": .string("S\u{00E3}o Paulo")]
            )
        )

        #expect(detail.additionalMetadataText?.contains("region") == true)
        #expect(detail.searchableText.contains(ProxySearchText.normalize("munchen edge")))
        #expect(detail.searchableText.contains(ProxySearchText.normalize("sao paulo")))
        #expect(detail.searchableText.contains(ProxySearchText.normalize("shared provider")))

        detail.fixed = "Pinned Node"
        #expect(detail.searchableText.contains(ProxySearchText.normalize("pinned node")))
        detail.fixed = nil
        #expect(!detail.searchableText.contains(ProxySearchText.normalize("pinned node")))
    }

    @Test func proxyNodeFieldsSeparateKnownValuesFromAdditionalRows() {
        let detail = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "Node A",
                type: "VLESS",
                udp: true,
                uot: false,
                tfo: true,
                hidden: false,
                metadata: [
                    "type": .string("VLESS"),
                    "udp": .bool(true),
                    "uot": .bool(false),
                    "history": .array([]),
                    "all": .array([.string("Node A"), .string("Node B")]),
                    "empty": .string(""),
                    "nested": .object([
                        "b": .number(2),
                        "a": .bool(true),
                    ]),
                    "now": .string("Node A"),
                    "priority": .number(3),
                    "region": .string("Tokyo"),
                ]
            )
        )

        #expect(detail.hidden == false)
        #expect(detail.transportCapabilities.map(\.name) == ["UDP", "UOT", "TFO"])
        #expect(detail.transportCapabilities.map(\.isEnabled) == [true, false, true])
        #expect(detail.transportNames == ["UDP", "TFO"])
        let projection = ProxyMemberDetailProjection(detail: detail)
        #expect(
            projection.reportedFields.map(\.key)
                == ["empty", "nested", "priority", "region"]
        )

        let fields = Dictionary(
            uniqueKeysWithValues: projection.reportedFields.map {
                ($0.key, $0.value)
            }
        )
        #expect(fields["empty"] == #""""#)
        #expect(fields["nested"] == #"{"a":true,"b":2}"#)
        #expect(fields["priority"] == "3")
        #expect(fields["region"] == "Tokyo")
        #expect(detail.metadata["all"] == .array([.string("Node A"), .string("Node B")]))
        #expect(detail.metadata["now"] == .string("Node A"))
        #expect(detail.metadata["history"] == .array([]))
        #expect(detail.metadata["type"] == .string("VLESS"))
        #expect(detail.metadata["udp"] == .bool(true))
        #expect(detail.metadata["uot"] == .bool(false))
        #expect(detail.additionalMetadataText?.contains(#""region":"Tokyo""#) == true)
        #expect(detail.additionalMetadataText?.contains(#""all":"#) == false)
        #expect(detail.additionalMetadataText?.contains(#""now":"#) == false)
        #expect(detail.searchableText.contains(ProxySearchText.normalize("Tokyo")))
    }

    @Test func nonSelectableSingBoxGroupKeepsMembersAndTestsAvailable() throws {
        var dashboard = DashboardSnapshot.empty
        dashboard.replaceSingBoxGroups(
            with: SingBoxPolicyCatalog(
                groups: [
                    SingBoxPolicyGroup(
                        tag: "Read Only",
                        type: "URLTest",
                        selectable: false,
                        selected: "Node A",
                        isExpandedByController: true,
                        items: [
                            SingBoxPolicyNode(
                                tag: "Node A",
                                type: "VLESS",
                                urlTestTimestamp: 1,
                                urlTestDelayMilliseconds: 42
                            ),
                        ]
                    ),
                ]
            )
        )

        let group = try #require(dashboard.groups.first)
        let interactions = ProxyProjection.memberInteractions(
            in: group,
            selectionActionAvailable: true,
            testActionAvailable: true
        )

        #expect(group.selectable == false)
        #expect(interactions.canSelect == false)
        #expect(interactions.canTest == true)
        #expect(ProxyProjection.members(in: group, query: "").map(\.name) == ["Node A"])
        #expect(group.detail(for: "Node A")?.latestHistoryDelay == 42)
    }

    @Test func proxyMembersPreserveDuplicatesAndFilterBeforeReveal() {
        let detail = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "Provider Node",
                type: "Shadowsocks",
                providerName: "Provider East"
            )
        )
        let group = ProxyGroupViewState(
            id: "Proxy",
            type: "Selector",
            selected: "Node",
            options: ["Node", "Node", "Provider Node", "Other"],
            optionDetails: ["Provider Node": detail]
        )

        let all = ProxyProjection.members(in: group, query: "")
        #expect(all.map(\.name) == ["Node", "Node", "Provider Node", "Other"])
        #expect(all.map(\.occurrence) == [0, 1, 0, 0])
        #expect(Set(all.map(\.id)).count == 4)

        let filtered = ProxyProjection.members(in: group, query: "Provider East")
        #expect(filtered.map(\.name) == ["Provider Node"])
    }

    @Test func proxyMemberDetailsPreserveReportedStatusFixedAndHistory() {
        let history = [
            ProxyDelayHistorySnapshot(
                time: "2026-07-28T10:00:00Z",
                delay: 64,
                meanDelay: 70
            ),
            ProxyDelayHistorySnapshot(
                time: "2026-07-28T10:05:00Z",
                delay: nil,
                meanDelay: 72
            ),
        ]
        let detail = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "Node A",
                type: "VLESS",
                alive: true,
                history: history,
                fixed: "Node B"
            )
        )

        let projection = ProxyMemberDetailProjection(detail: detail)

        #expect(projection.alive == true)
        #expect(projection.fixed == "Node B")
        #expect(projection.history == history)
        #expect(projection.latestHistoryDelay == 64)
        #expect(projection.latestHistoryTime == "2026-07-28T10:05:00Z")
        #expect(projection.availabilityText(language: .english) == "Available")
        #expect(
            projection.historySummaryText(language: .english)
                == "2 samples \u{00B7} 64 ms \u{00B7} 2026-07-28T10:05:00Z"
        )
    }

    @Test func proxyMemberDetailsLocalizeMissingValuesWithoutFabrication() {
        let missing = ProxyMemberDetailProjection(detail: nil)
        let empty = ProxyMemberDetailProjection(
            detail: ProxyNodeViewState(
                snapshot: ProxySnapshot(name: "Node A", type: "VLESS")
            )
        )

        #expect(missing.alive == nil)
        #expect(missing.fixed == nil)
        #expect(missing.history == nil)
        #expect(missing.latestHistoryDelay == nil)
        #expect(missing.latestHistoryTime == nil)
        #expect(missing.availabilityText(language: .english) == "Unavailable")
        #expect(
            missing.fixedSelectionText(language: .simplifiedChinese)
                == "\u{4E0D}\u{53EF}\u{7528}"
        )
        #expect(missing.historySummaryText(language: .english) == "Unavailable")

        #expect(empty.history == [])
        #expect(empty.latestHistoryDelay == nil)
        #expect(empty.latestHistoryTime == nil)
        #expect(
            empty.historySummaryText(language: .simplifiedChinese)
                == "\u{4E0D}\u{53EF}\u{7528}"
        )
    }

    @Test func proxyWorkspaceReconcilesDuplicateOccurrencesAndStaleMembers() throws {
        let arranged = ProxyProjection.arrangedGroups(
            [
                Self.group(id: "Proxy", selected: "Node A", options: ["Node A"]),
                Self.group(id: "Proxy", selected: "Node B", options: ["Node B"]),
            ],
            mode: "Rule",
            visibility: .followMode
        )
        let first = try #require(arranged.first)
        let duplicate = try #require(arranged.last)
        let firstMember = try #require(
            ProxyProjection.preferredMemberID(in: first.group)
        )

        var workspace = WorkbenchDestinationWorkspace()
        workspace.openGroupIDs = ["stale-group", duplicate.id, first.id]
        workspace.activeGroupID = "stale-group"
        workspace.groupFilters = [
            first.id: "asia",
            duplicate.id: "europe",
            "stale-group": "stale",
        ]
        workspace.selectedGroupMemberIDs = [
            first.id: firstMember,
            duplicate.id: "stale-member",
            "stale-group": "stale-member",
        ]

        let reconciled = ProxyWorkspaceProjection.reconciled(
            workspace,
            groups: arranged
        )

        #expect(reconciled.openGroupIDs == [first.id, duplicate.id])
        #expect(reconciled.activeGroupID == first.id)
        #expect(reconciled.groupFilters[first.id] == "asia")
        #expect(reconciled.groupFilters[duplicate.id] == "europe")
        #expect(reconciled.groupFilters["stale-group"] == nil)
        #expect(reconciled.selectedGroupMemberIDs[first.id] == firstMember)
        #expect(reconciled.selectedGroupMemberIDs[duplicate.id] == nil)
    }

    @Test func proxyMemberMutationRejectsStaleAndNonSelectableTargets() throws {
        let arranged = ProxyProjection.arrangedGroups(
            [
                ProxyGroupViewState(
                    id: "Read Only",
                    type: "URLTest",
                    selected: "Node A",
                    options: ["Node A"],
                    selectable: false
                ),
            ],
            mode: "Rule",
            visibility: .followMode
        )
        let group = try #require(arranged.first)
        let memberID = try #require(
            ProxyProjection.preferredMemberID(in: group.group)
        )

        #expect(
            ProxyProjection.memberMutationTarget(
                groupID: group.id,
                memberID: memberID,
                groups: arranged,
                actionAvailable: true,
                requiresSelectableGroup: true
            ) == nil
        )
        #expect(
            ProxyProjection.memberMutationTarget(
                groupID: group.id,
                memberID: "stale-member",
                groups: arranged,
                actionAvailable: true,
                requiresSelectableGroup: false
            ) == nil
        )
        #expect(
            ProxyProjection.memberMutationTarget(
                groupID: group.id,
                memberID: memberID,
                groups: arranged,
                actionAvailable: true,
                requiresSelectableGroup: false
            ) == ProxyMemberMutationTarget(
                groupID: "Read Only",
                memberName: "Node A"
            )
        )
    }

    @Test func smartUsageLabelsComeOnlyFromControllerReportedRanks() {
        let reported = ProxyGroupViewState(
            id: "Smart",
            type: "Smart",
            selected: "Node A",
            options: ["Node A", "Node B", "Node C"],
            optionUsageRanks: [
                "Node A": .mostUsed,
                "Node B": .rarelyUsed,
                "Node C": .mostUsed,
            ]
        )
        let unreported = ProxyGroupViewState(
            id: "Looks Smart",
            type: "Smart",
            selected: "Most Used Node",
            options: ["Most Used Node", "Rarely Used Node"]
        )

        #expect(
            ProxyProjection.reportedUsageRanks(in: reported)
                == [.mostUsed, .rarelyUsed]
        )
        #expect(ProxyProjection.reportedUsageRanks(in: unreported).isEmpty)
    }

    @Test func overviewSummaryProjectionsUseOnlyRealReportedValues() {
        var fast = Self.group(id: "Fast", selected: "Node A")
        fast.delays["Node A"] = 80
        var slow = Self.group(id: "Slow", selected: "Node B")
        slow.delays["Node B"] = 260
        var timeout = Self.group(id: "Slow", selected: "Node C")
        timeout.optionDetails["Node C"] = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "Node C",
                type: "Proxy",
                history: [ProxyDelayHistorySnapshot(time: "reported", delay: 1_200)]
            )
        )
        let groups = [fast, slow, timeout]

        let anomalies = OverviewProjection.latencyAnomalies(
            from: groups,
            maximumCount: 2
        )

        #expect(anomalies.map(\.delay) == [1_200, 260])
        #expect(anomalies.map(\.nodeName) == ["Node C", "Node B"])
        #expect(anomalies.map(\.groupOccurrenceID) == [
            ProxyGroupKey(groupID: "Slow", occurrence: 1).rawValue,
            ProxyGroupKey(groupID: "Slow", occurrence: 0).rawValue,
        ])
        #expect(anomalies.map(\.id) == anomalies.map(\.groupOccurrenceID))
        #expect(groups.map(\.id) == ["Fast", "Slow", "Slow"])

        let rules = [
            RuleViewState(
                id: "a",
                type: "DOMAIN",
                payload: "a.example",
                proxy: "Proxy A",
                hitCount: 2,
                missCount: 8
            ),
            RuleViewState(
                id: "b",
                type: "DOMAIN",
                payload: "b.example",
                proxy: "Proxy B",
                hitCount: 9,
                missCount: 3
            ),
            RuleViewState(
                id: "c",
                type: "MATCH",
                payload: "",
                proxy: "DIRECT",
                hitCount: nil,
                missCount: nil
            ),
            RuleViewState(
                id: "d",
                type: "DOMAIN",
                payload: "d.example",
                proxy: "Proxy D",
                hitCount: 4,
                missCount: nil
            ),
        ]
        let summaries = OverviewProjection.ruleHitSummary(from: rules, maximumCount: 5)
        #expect(summaries.map(\.label) == ["b.example", "a.example", "d.example"])
        #expect(summaries.map(\.hits) == [9, 2, 4] as [Int?])
        #expect(summaries.map(\.misses) == [3, 8, nil])
        #expect(summaries.map(\.sourceIndex) == [1, 0, 3])
        #expect(summaries.map(\.reportedRuleID) == ["b", "a", "d"])
        #expect(summaries.map(\.type) == ["DOMAIN", "DOMAIN", "DOMAIN"])
        #expect(summaries.map(\.payload) == [
            "b.example", "a.example", "d.example",
        ])
        #expect(rules.map(\.id) == ["a", "b", "c", "d"])
    }

    @Test func overviewTopActiveConnectionsKeepOccurrenceIdentityAndMissingCountersUnavailable() {
        let active = [
            ConnectionSnapshot(
                id: "same",
                upload: 10,
                download: 20,
                metadata: ConnectionMetadataSnapshot(host: "first.example")
            ),
            ConnectionSnapshot(
                id: "same",
                upload: 30,
                metadata: ConnectionMetadataSnapshot(host: "second.example")
            ),
            ConnectionSnapshot(
                id: "",
                metadata: ConnectionMetadataSnapshot(host: "unreported.example")
            ),
            ConnectionSnapshot(id: "zero", upload: 0, download: 0),
        ]

        let rows = OverviewProjection.topActiveConnections(from: active, maximumCount: 10)

        #expect(rows.map(\.label) == ["first.example", "second.example", "zero", "unreported.example"])
        #expect(rows.map(\.totalTraffic) == [30, 30, 0, nil])
        #expect(Set(rows.map(\.id)).count == active.count)
        #expect(rows.map(\.connectionID) == ["same", "same", "zero", ""])
        #expect(active.map(\.id) == ["same", "same", "", "zero"])
    }

    @Test func overviewNetworkFactsKeepCompleteReportedValuesAndOmitMissingFields() {
        var config = DashboardConfigSnapshot()
        config.modeOptions = ["Rule", "Global"]
        config.logLevel = "debug"
        config.allowLan = true
        config.ipv6 = false
        config.mixedPort = 7_890
        let router = RouterProfile(
            displayName: "Controller",
            scheme: .https,
            host: "controller.example",
            port: 9_090
        )
        let metadata = ControllerMetadataSnapshot(
            versionLabel: "1.19.7",
            mode: "Rule",
            config: config
        )

        let facts = OverviewProjection.networkFacts(
            router: router,
            metadata: metadata,
            language: .english
        )
        let values = Dictionary(uniqueKeysWithValues: facts.map { ($0.id, $0.value) })

        #expect(values["controller"] == "Controller")
        #expect(values["endpoint"] == "https://controller.example:9090")
        #expect(values["host"] == "controller.example")
        #expect(values["version"] == "1.19.7")
        #expect(values["mode"] == "Rule")
        #expect(values["mode-options"] == "Rule\nGlobal")
        #expect(values["log-level"] == "debug")
        #expect(values["allow-lan"] == "Enabled")
        #expect(values["ipv6"] == "Disabled")
        #expect(values["mixed-port"] == "7,890")
        #expect(values["http-port"] == nil)
        #expect(values["socks-port"] == nil)
    }

    @Test func overviewDownsamplingRetainsOnlyReceivedSamplesAndEndpoints() {
        let samples = Array(0..<300)
        let rendered = OverviewTimelineProjection.downsample(samples, maximumCount: 80)

        #expect(rendered.count == 80)
        #expect(rendered.first == 0)
        #expect(rendered.last == 299)
        #expect(Set(rendered).isSubset(of: Set(samples)))
    }

    @Test func proxyNodePresentationEqualityKeepsReportedMetadataAndFallbackSemantics() {
        let metadata: [String: MihomoJSONValue] = [
            "controller-meta": .object([
                "nested": .object([
                    "enabled": .bool(true),
                    "values": .array([.string("alpha"), .number(42), .null]),
                ]),
            ]),
        ]
        let first = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "Node",
                type: "VLESS",
                alive: true,
                history: [ProxyDelayHistorySnapshot(time: "one", delay: 20)],
                fixed: "Node",
                udp: true,
                metadata: metadata
            )
        )
        let equal = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "Node",
                type: "VLESS",
                alive: true,
                history: [ProxyDelayHistorySnapshot(time: "one", delay: 20)],
                fixed: "Node",
                udp: true,
                metadata: metadata
            )
        )
        let changedMetadata = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "Node",
                type: "VLESS",
                alive: true,
                history: [ProxyDelayHistorySnapshot(time: "one", delay: 20)],
                fixed: "Node",
                udp: true,
                metadata: [
                    "controller-meta": .object([
                        "nested": .object([
                            "enabled": .bool(false),
                            "values": .array([.string("alpha"), .number(42), .null]),
                        ]),
                    ]),
                ]
            )
        )
        let changedKnownField = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "Node",
                type: "VLESS",
                alive: nil,
                history: [ProxyDelayHistorySnapshot(time: "one", delay: 20)],
                fixed: "Node",
                udp: true,
                metadata: metadata
            )
        )
        let changedHistory = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "Node",
                type: "VLESS",
                alive: true,
                history: [ProxyDelayHistorySnapshot(time: "two", delay: 21)],
                fixed: "Node",
                udp: true,
                metadata: metadata
            )
        )
        let changedTransport = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "Node",
                type: "VLESS",
                alive: true,
                history: [ProxyDelayHistorySnapshot(time: "one", delay: 20)],
                fixed: "Node",
                udp: false,
                metadata: metadata
            )
        )

        #expect(first == equal)
        #expect(first != changedMetadata)
        #expect(first != changedKnownField)
        #expect(first != changedHistory)
        #expect(first != changedTransport)

        let positiveZero = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "Zero",
                type: "Direct",
                metadata: ["value": .number(0)]
            )
        )
        let negativeZero = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "Zero",
                type: "Direct",
                metadata: ["value": .number(-0.0)]
            )
        )
        let nonFinite = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "NaN",
                type: "Direct",
                metadata: ["value": .number(.nan)]
            )
        )
        let sameNonFinite = ProxyNodeViewState(
            snapshot: ProxySnapshot(
                name: "NaN",
                type: "Direct",
                metadata: ["value": .number(.nan)]
            )
        )

        #expect(positiveZero == negativeZero)
        #expect(nonFinite != sameNonFinite)
    }

    @Test func overviewTopologyHitIndexUsesPointerSizedTargets() async throws {
        let topology = ConnectionTopologyBuilder.build(from: [
            ConnectionSnapshot(
                id: "connection",
                chains: ["DIRECT"],
                metadata: ConnectionMetadataSnapshot(sourceIP: "10.0.0.1")
            ),
        ])
        let layout = try await OverviewTopologyLayoutBuilder.buildCancellable(
            topology: topology,
            availableWidth: 520
        )
        let source = try #require(
            layout.nodes.first { $0.node.columnID == .source }
        )
        let edge = try #require(layout.edges.first)

        #expect(source.rect.width == 20)
        #expect(source.rect.height > 0)
        #expect(source.hitRect.height >= 28)
        #expect(edge.hitTolerance >= 10)
        #expect(edge.hitRect.height >= max(20, edge.width + 4))
        #expect(
            layout.hitTest(
                at: CGPoint(x: source.rect.midX, y: source.rect.minY + 1)
            ) == .node(source.node.id)
        )
        #expect(
            layout.hitTest(
                at: CGPoint(x: edge.hitRect.midX, y: edge.hitRect.midY)
            ) == .edge(edge.edge.id)
        )
    }

    private static func group(
        id: String,
        selected: String,
        options: [String]? = nil
    ) -> ProxyGroupViewState {
        ProxyGroupViewState(
            id: id,
            type: "Selector",
            selected: selected,
            options: options ?? [selected]
        )
    }

}
