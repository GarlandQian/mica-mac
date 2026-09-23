import MicaCore
import Testing
@testable import Mica

struct SurgeNodeDetailsProjectionTests {
    @Test func reportedMemberTypesReachNodeDetailsWithoutGroupTypesOrInventedConfiguration() throws {
        let dashboard = project(
            policies: [
                SurgePolicy(name: "SS node", type: "ss"),
                SurgePolicy(name: "VMess node", type: "vmess"),
                SurgePolicy(name: "Trojan node", type: "trojan"),
            ],
            groups: [SurgePolicyGroup(
                name: "Automatic", type: "url-test", selected: "SS node",
                policies: ["Trojan node", "SS node", "VMess node"]
            )]
        )

        let group = try #require(dashboard.groups.first)
        #expect(group.type == "url-test")
        #expect(group.detail(for: "SS node")?.type == "ss")
        #expect(group.detail(for: "VMess node")?.type == "vmess")
        #expect(group.detail(for: "Trojan node")?.type == "trojan")
        for name in group.options {
            let detail = try #require(group.detail(for: name))
            #expect(detail.name == name)
            #expect(detail.metadata.isEmpty)
            #expect(detail.history.isEmpty)
            #expect(detail.transportCapabilities.isEmpty)
            #expect(detail.alive == nil)
        }
    }

    @Test func missingTypesAndUnmatchedNamesNeverBorrowParentOrSimilarMemberTypes() throws {
        let dashboard = project(
            policies: [
                SurgePolicy(name: "Missing"),
                SurgePolicy(name: "Empty", type: ""),
                SurgePolicy(name: "Node", type: "ss"),
                SurgePolicy(name: "Padded ", type: "trojan"),
            ],
            groups: [SurgePolicyGroup(
                name: "Manual", type: "select", selected: "Missing",
                policies: ["Missing", "Empty", "node", "Padded", "Unreported"]
            )]
        )

        let group = try #require(dashboard.groups.first)
        #expect(group.detail(for: "Missing")?.type == "")
        #expect(group.detail(for: "Empty")?.type == "")
        #expect(group.detail(for: "node") == nil)
        #expect(group.detail(for: "Padded") == nil)
        #expect(group.detail(for: "Unreported") == nil)
        #expect(group.optionDetails.count == 2)
    }

    @Test func ambiguousPolicyNamesDoNotPickOneOfTheReports() throws {
        let dashboard = project(
            policies: [
                SurgePolicy(name: "Conflict", type: "ss"),
                SurgePolicy(name: "Conflict", type: "vmess"),
                SurgePolicy(name: "Repeated", type: "trojan"),
                SurgePolicy(name: "Repeated", type: "trojan"),
                SurgePolicy(name: "Unique", type: "http"),
            ],
            groups: [SurgePolicyGroup(
                name: "Manual", policies: ["Conflict", "Repeated", "Unique", "Unique"]
            )]
        )

        let group = try #require(dashboard.groups.first)
        #expect(group.detail(for: "Conflict") == nil)
        #expect(group.detail(for: "Repeated") == nil)
        #expect(group.detail(for: "Unique")?.type == "http")
        #expect(group.optionDetails.count == 1)
        #expect(group.options == ["Conflict", "Repeated", "Unique", "Unique"])
    }

    @Test func reportedGroupOrderMemberOrderAndLocalLatenciesArePreserved() throws {
        let dashboard = project(
            policies: [SurgePolicy(name: "A", type: "ss"), SurgePolicy(name: "B", type: "trojan")],
            groups: [
                SurgePolicyGroup(
                    name: "Second", type: "url-test", selected: "B",
                    policies: ["B", "A", "B"], latency: ["A": 0, "B": 19]
                ),
                SurgePolicyGroup(
                    name: "First", type: "select", selected: "A",
                    policies: ["A", "B"], latency: ["A": 61, "B": 88]
                ),
            ]
        )

        #expect(dashboard.groups.map(\.id) == ["Second", "First"])
        let first = try #require(dashboard.groups.first)
        let second = try #require(dashboard.groups.last)
        #expect(first.options == ["B", "A", "B"])
        #expect(second.options == ["A", "B"])
        #expect(first.selected == "B")
        #expect(second.selected == "A")
        #expect(first.delays == ["A": 0, "B": 19])
        #expect(second.delays == ["A": 61, "B": 88])
        #expect(first.detail(for: "B") == second.detail(for: "B"))
        #expect(first.detail(for: "B")?.history.isEmpty == true)
    }

    @Test func independentControllerSnapshotsNeverReuseAnotherControllersReportedType() throws {
        let groups = [SurgePolicyGroup(name: "Manual", policies: ["Shared name"])]
        let first = project(
            policies: [SurgePolicy(name: "Shared name", type: "ss")],
            groups: groups,
            platform: .remoteMac
        )
        let second = project(
            policies: [SurgePolicy(name: "Shared name", type: "trojan")],
            groups: groups,
            platform: .iosReachable
        )
        let unreported = project(policies: [], groups: groups, platform: .macLocal)

        #expect(try #require(first.groups.first).detail(for: "Shared name")?.type == "ss")
        #expect(try #require(second.groups.first).detail(for: "Shared name")?.type == "trojan")
        #expect(try #require(unreported.groups.first).detail(for: "Shared name") == nil)
    }

    private func project(
        policies: [SurgePolicy],
        groups: [SurgePolicyGroup],
        platform: SurgeControllerPlatform = .remoteMac
    ) -> DashboardSnapshot {
        DashboardSnapshot(
            surge: SurgeControlSnapshot(
                platform: platform,
                policies: SurgePoliciesResponse(policies: policies),
                policyGroups: SurgePolicyGroupsResponse(groups: groups)
            ),
            language: .english
        )
    }
}
