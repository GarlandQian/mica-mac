import Combine
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

    @MainActor
    @Test(arguments: [true, false])
    func repeatedCurrentInsertionRequestsDoNotPublish(isInserted: Bool) async {
        let suiteName = "MicaTests.MenuBarInsertion.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(isInserted, forKey: AppPreferencesStore.showsMenuBarExtraKey)
        let store = AppPreferencesStore(defaults: defaults)
        var publications: [Bool] = []
        let subscription = store.objectWillChange.sink {
            publications.append(store.showsMenuBarExtra)
        }
        defer { subscription.cancel() }

        for _ in 0..<100 {
            store.requestMenuBarExtraInsertion(isInserted)
        }

        #expect(publications.isEmpty)
        await finishEnqueuedMainActorRequests()
        #expect(publications.isEmpty)
        #expect(store.showsMenuBarExtra == isInserted)
        #expect(defaults.object(forKey: AppPreferencesStore.showsMenuBarExtraKey) as? Bool == isInserted)
    }

    @MainActor
    @Test(arguments: [true, false])
    func changedInsertionRequestPublishesOnceAfterReturning(isInserted: Bool) async {
        let suiteName = "MicaTests.MenuBarInsertion.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(!isInserted, forKey: AppPreferencesStore.showsMenuBarExtraKey)
        let store = AppPreferencesStore(defaults: defaults)
        var events = ["request"]
        let subscription = store.objectWillChange.sink {
            events.append("publication")
        }
        defer { subscription.cancel() }

        store.requestMenuBarExtraInsertion(isInserted)
        events.append("returned")

        #expect(events == ["request", "returned"])
        #expect(store.showsMenuBarExtra == !isInserted)
        #expect(defaults.object(forKey: AppPreferencesStore.showsMenuBarExtraKey) as? Bool == !isInserted)

        await finishEnqueuedMainActorRequests()
        events.append("resumed")

        #expect(events == ["request", "returned", "publication", "resumed"])
        #expect(store.showsMenuBarExtra == isInserted)
        #expect(defaults.object(forKey: AppPreferencesStore.showsMenuBarExtraKey) as? Bool == isInserted)
    }

    @MainActor
    @Test func latestInsertionRequestCancelsQueuedRemovalWithoutPublishing() async {
        let suiteName = "MicaTests.MenuBarInsertion.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: AppPreferencesStore.showsMenuBarExtraKey)
        let store = AppPreferencesStore(defaults: defaults)
        var publications: [Bool] = []
        let subscription = store.objectWillChange.sink {
            publications.append(store.showsMenuBarExtra)
        }
        defer { subscription.cancel() }

        store.requestMenuBarExtraInsertion(false)
        store.requestMenuBarExtraInsertion(true)

        #expect(publications.isEmpty)
        #expect(store.showsMenuBarExtra)
        await finishEnqueuedMainActorRequests()
        #expect(publications.isEmpty)
        #expect(store.showsMenuBarExtra)
        #expect(defaults.object(forKey: AppPreferencesStore.showsMenuBarExtraKey) as? Bool == true)
    }

    @MainActor
    @Test func explicitSettingCancelsQueuedInsertionChange() async {
        let suiteName = "MicaTests.MenuBarInsertion.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: AppPreferencesStore.showsMenuBarExtraKey)
        let store = AppPreferencesStore(defaults: defaults)
        var events: [String] = []
        let subscription = store.objectWillChange.sink {
            events.append("publication")
        }
        defer { subscription.cancel() }

        store.requestMenuBarExtraInsertion(false)
        #expect(events.isEmpty)
        events.append("explicit setting")
        store.showsMenuBarExtra = true
        events.append("setting returned")

        #expect(events == ["explicit setting", "publication", "setting returned"])
        await finishEnqueuedMainActorRequests()
        #expect(events == ["explicit setting", "publication", "setting returned"])
        #expect(store.showsMenuBarExtra)
        #expect(defaults.object(forKey: AppPreferencesStore.showsMenuBarExtraKey) as? Bool == true)
    }

    @MainActor
    private func finishEnqueuedMainActorRequests() async {
        // Requests enqueue non-suspending MainActor tasks. A main-queue marker
        // lets those tasks finish without depending on a timed sleep.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}
