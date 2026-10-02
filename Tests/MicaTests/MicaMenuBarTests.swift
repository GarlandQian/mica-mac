import Foundation
import Testing
@testable import Mica

struct MicaMenuBarTests {
    @Test func compactRatesStayShortAndRollOverAtUnitBoundaries() {
        #expect(MicaMenuBarRateFormat.compact(-5) == "0 B")
        #expect(MicaMenuBarRateFormat.compact(0) == "0 B")
        #expect(MicaMenuBarRateFormat.compact(999) == "999 B")
        #expect(MicaMenuBarRateFormat.compact(1_000) == "1.0 K")
        #expect(MicaMenuBarRateFormat.compact(9_960) == "10 K")
        #expect(MicaMenuBarRateFormat.compact(360_000) == "360 K")
        #expect(MicaMenuBarRateFormat.compact(999_960) == "1.0 M")
        #expect(MicaMenuBarRateFormat.compact(4_300_000) == "4.3 M")
        #expect(MicaMenuBarRateFormat.compact(12_000_000_000) == "12 G")
    }

    @Test func policyMenuListsOnlySwitchableGroupsInWorkbenchOrder() {
        let catalog = PolicyGroupCatalogSnapshot(
            mode: "Rule",
            groups: [
                ProxyGroupViewState(id: "Auto", type: "URLTest", selected: "A", options: ["A", "B"], selectable: false),
                ProxyGroupViewState(id: "Proxy", type: "Selector", selected: "Auto", options: ["Auto", "DIRECT"]),
                ProxyGroupViewState(id: "Empty", type: "Selector", selected: "", options: []),
                ProxyGroupViewState(id: "Media", type: "Selector", selected: "Proxy", options: ["Proxy", "DIRECT"]),
                ProxyGroupViewState(id: "GLOBAL", type: "Selector", selected: "DIRECT", options: ["DIRECT", "Proxy"]),
            ]
        )

        let followMode = MicaMenuBarPolicyProjection.groups(catalog, visibility: .followMode)
        #expect(followMode.map(\.group.id) == ["Proxy", "Media"])

        let always = MicaMenuBarPolicyProjection.groups(catalog, visibility: .alwaysShow)
        #expect(always.map(\.group.id) == ["Proxy", "Media", "GLOBAL"])
    }
}
