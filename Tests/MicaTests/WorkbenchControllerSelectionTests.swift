import Foundation
import MicaCore
import Testing
@testable import Mica

struct WorkbenchControllerSelectionTests {
    @Test func restoredSearchNeverRestoresAnInvisibleController() {
        let active = profile(name: "Primary", host: "primary.example")
        let firstMatch = profile(name: "Lab A", host: "lab-a.example")
        let secondMatch = profile(name: "Lab B", host: "lab-b.example")
        let profiles = [active, secondMatch, firstMatch]

        let selection = WorkbenchControllerListProjection.reconciledSelection(
            storedID: active.id,
            activeID: active.id,
            profiles: profiles,
            query: "Lab",
            controllerTypeLabel: { _ in "Mihomo" }
        )

        #expect(selection == secondMatch.id)
        #expect(profiles.map(\.id) == [active.id, secondMatch.id, firstMatch.id])
    }

    @Test func profileRefreshCannotReopenDetailWhenSearchHasNoMatches() {
        var active = profile(name: "Primary", host: "primary.example")
        let selected = profile(name: "Lab", host: "lab.example")
        active.lastConnectedAt = Date(timeIntervalSince1970: 42)
        var renamed = selected
        renamed.displayName = "Remote"
        renamed.host = "remote.example"

        let selection = WorkbenchControllerListProjection.reconciledSelection(
            storedID: selected.id,
            activeID: active.id,
            profiles: [active, renamed],
            query: "Lab",
            controllerTypeLabel: { _ in "Mihomo" }
        )

        #expect(selection == nil)
    }

    @Test func profileRefreshPreservesMatchingManagementSelectionAndSourceOrder() {
        var active = profile(name: "Primary", host: "primary.example")
        let first = profile(name: "Lab A", host: "lab-a.example")
        let selected = profile(name: "Lab B", host: "lab-b.example")
        active.lastConnectedAt = Date(timeIntervalSince1970: 42)
        let profiles = [first, active, selected]

        let selection = WorkbenchControllerListProjection.reconciledSelection(
            storedID: selected.id,
            activeID: active.id,
            profiles: profiles,
            query: "Lab",
            controllerTypeLabel: { _ in "Mihomo" }
        )

        #expect(selection == selected.id)
        #expect(WorkbenchControllerListProjection.filtered(
            profiles,
            query: "Lab",
            controllerTypeLabel: { _ in "Mihomo" }
        ).map(\.id) == [first.id, selected.id])
    }

    @Test func selectionUsesTheSameLocalizedTypeFilterAsTheList() {
        let active = profile(name: "Primary", host: "primary.example")
        let other = profile(name: "Remote", host: "remote.example")

        let selection = WorkbenchControllerListProjection.reconciledSelection(
            storedID: active.id,
            activeID: active.id,
            profiles: [active, other],
            query: "测试类型",
            controllerTypeLabel: { $0.id == other.id ? "测试类型" : "Mihomo" }
        )

        #expect(selection == other.id)
    }

    private func profile(name: String, host: String) -> RouterProfile {
        RouterProfile(displayName: name, host: host, port: 9090)
    }
}
