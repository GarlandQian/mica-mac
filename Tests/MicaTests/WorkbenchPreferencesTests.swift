import Foundation
import SwiftUI
import Testing
@testable import Mica

@Suite(.serialized)
struct WorkbenchPreferencesTests {
    @Test func storedPreferencesUseStableDefaultsAndLegacyLanguageAliases() {
        #expect(AppLanguage.stored(nil) == .system)
        #expect(AppLanguage.stored("english") == .english)
        #expect(AppLanguage.stored("simplifiedChinese") == .simplifiedChinese)
        #expect(AppLanguage.stored("unknown") == .system)

        #expect(AppAppearance.stored(nil) == .system)
        #expect(AppAppearance.stored("light") == .light)
        #expect(AppAppearance.stored("dark") == .dark)
        #expect(AppAppearance.stored("unknown") == .system)

        #expect(AppFontScale.stored(nil) == .comfortable)
        #expect(AppFontScale.stored("standard") == .standard)
        #expect(AppFontScale.stored("large") == .large)
        #expect(AppFontScale.stored("extraLarge") == .extraLarge)

        #expect(GlobalGroupVisibility.stored(nil) == .followMode)
        #expect(GlobalGroupVisibility.stored("alwaysShow") == .alwaysShow)
        #expect(GlobalGroupVisibility.stored("unknown") == .followMode)
    }

    @Test func fontScaleUsesFourDistinctVisibleTextStepsWithoutOwningControlGeometry() {
        #expect(AppFontScale.allCases.map(\.rawValue) == [
            "standard", "comfortable", "large", "extraLarge",
        ])
        #expect(AppFontScale.allCases.map(\.dynamicTypeSize) == [
            DynamicTypeSize.small,
            .large,
            .xxLarge,
            .xxxLarge,
        ])
        #expect(AppFontScale.allCases.map(\.multiplier) == [
            0.92,
            1,
            1.16,
            1.32,
        ])
        #expect(AppFontScale.allCases.map { $0.pointSize(for: 12) } == [
            11,
            12,
            14,
            16,
        ])
    }

    @Test func appearanceAndLanguageExposeCompleteSettingsChoices() {
        #expect(AppAppearance.allCases.map(\.rawValue) == ["system", "light", "dark"])
        #expect(AppAppearance.system.colorScheme == nil)
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
        #expect(AppLanguage.english.resolvedLocale.identifier.lowercased().hasPrefix("en"))
        #expect(AppLanguage.simplifiedChinese.resolvedLocale.identifier.lowercased().hasPrefix("zh"))

        for language in [AppLanguage.english, .simplifiedChinese] {
            for key in AppAppearance.allCases.map(\.titleKey)
                + AppFontScale.allCases.map(\.titleKey)
                + AppLanguage.allCases.map(\.titleKey)
                + GlobalGroupVisibility.allCases.map(\.titleKey) {
                let value = MicaStrings.localizedKey(key, language: language)
                #expect(!value.isEmpty)
                #expect(value != key)
            }
        }
    }

    @MainActor
    @Test func preferenceStoreLoadsAndPersistsTheSingleSettingsAuthority() {
        let suiteName = "MicaTests.WorkbenchPreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            AppAppearance.system.applyToApplication()
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(AppLanguage.english.rawValue, forKey: AppPreferencesStore.languageKey)
        defaults.set(AppAppearance.system.rawValue, forKey: AppPreferencesStore.appearanceKey)
        defaults.set(AppFontScale.large.rawValue, forKey: AppPreferencesStore.fontScaleKey)
        defaults.set(
            GlobalGroupVisibility.alwaysShow.rawValue,
            forKey: AppPreferencesStore.globalGroupVisibilityKey
        )

        let store = AppPreferencesStore(defaults: defaults)
        #expect(store.language == .english)
        #expect(store.appearance == .system)
        #expect(store.fontScale == .large)
        #expect(store.globalGroupVisibility == .alwaysShow)

        store.language = .simplifiedChinese
        store.fontScale = .extraLarge
        store.globalGroupVisibility = .followMode

        #expect(defaults.string(forKey: AppPreferencesStore.languageKey) == "zh-Hans")
        #expect(defaults.string(forKey: AppPreferencesStore.fontScaleKey) == "extraLarge")
        #expect(defaults.string(forKey: AppPreferencesStore.globalGroupVisibilityKey) == "followMode")
    }

    @MainActor
    @Test func workspacePersistenceCoalescesOffMainAndExcludesSessionState() async {
        let suiteName = "MicaTests.WorkbenchWorkspace.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let persistenceKey = "workspace"
        defer { defaults.removePersistentDomain(forName: suiteName) }

        MicaPerformanceObservation.resetCounters()
        let store = WorkbenchWorkspaceStore(
            defaults: defaults,
            persistenceKey: persistenceKey,
            persistenceDelay: .seconds(60)
        )
        let controllerID = UUID()

        for index in 0..<100 {
            store.update(controllerID: controllerID, destination: .connections) {
                $0.selectedItemID = "connection-\(index)"
                $0.scrollAnchorID = "connection-\(index)"
            }
        }

        #expect(!store.hasPendingPersistence)
        #expect(defaults.data(forKey: persistenceKey) == nil)

        let search = store.searchBinding(
            controllerID: controllerID,
            destination: .connections
        )
        for index in 0..<100 {
            search.wrappedValue = "query-\(index)"
        }
        store.update(controllerID: controllerID, destination: .connections) {
            $0.filters = ["scope": "active"]
            $0.sort = [WorkbenchWorkspaceSort(field: "upload", ascending: false)]
            $0.activeTab = "closed"
            $0.groupFilters = ["group-a": "edge"]
            $0.openGroupIDs = ["session-group"]
            $0.activeGroupID = "session-group"
            $0.selectedGroupMemberIDs = ["session-group": "node-a"]
        }

        #expect(store.hasPendingPersistence)
        #expect(defaults.data(forKey: persistenceKey) == nil)
        #expect(
            MicaPerformanceObservation.counterSnapshot()[.workspacePersistence].eventCount
                == 0
        )

        store.flushPendingPersistence()
        await store.waitForPendingPersistence()

        #expect(!store.hasPendingPersistence)
        #expect(defaults.data(forKey: persistenceKey) != nil)
        #expect(
            MicaPerformanceObservation.counterSnapshot()[.workspacePersistence].eventCount
                == 1
        )
        #expect(
            MicaPerformanceObservation.counterSnapshot()[.workspaceEncoding].eventCount
                == 1
        )

        let restoredStore = WorkbenchWorkspaceStore(
            defaults: defaults,
            persistenceKey: persistenceKey,
            persistenceDelay: .seconds(60)
        )
        let restored = restoredStore.workspace(
            controllerID: controllerID,
            destination: .connections
        )

        #expect(restored.searchText == "query-99")
        #expect(restored.filters == ["scope": "active"])
        #expect(
            restored.sort
                == [WorkbenchWorkspaceSort(field: "upload", ascending: false)]
        )
        #expect(restored.activeTab == "closed")
        #expect(restored.groupFilters == ["group-a": "edge"])
        #expect(restored.selectedItemID == nil)
        #expect(restored.scrollAnchorID == nil)
        #expect(restored.openGroupIDs.isEmpty)
        #expect(restored.activeGroupID == nil)
        #expect(restored.selectedGroupMemberIDs.isEmpty)

        restoredStore.update(controllerID: controllerID, destination: .connections) {
            $0.searchText = "query-99"
            $0.selectedItemID = "session-only"
        }
        #expect(!restoredStore.hasPendingPersistence)
    }

    @MainActor
    @Test func scrollAnchorsAreSeparateAndRejectStaleGenerations() {
        let suiteName = "MicaTests.WorkbenchAnchors.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WorkbenchWorkspaceStore(
            defaults: defaults,
            persistenceKey: "workspace",
            persistenceDelay: .seconds(60)
        )
        let controllerID = UUID()
        let firstGeneration = UUID()
        let secondGeneration = UUID()

        store.update(controllerID: controllerID, destination: .logs) {
            $0.selectedItemID = "selected-log"
        }
        store.activateSession(
            controllerID: controllerID,
            generation: firstGeneration
        )

        #expect(
            !store.updateScrollAnchor(
                controllerID: controllerID,
                generation: firstGeneration,
                destination: .logs,
                anchorID: nil
            )
        )
        #expect(
            store.updateScrollAnchor(
                controllerID: controllerID,
                generation: firstGeneration,
                destination: .logs,
                anchorID: "log-41"
            )
        )
        #expect(
            store.scrollAnchorID(
                controllerID: controllerID,
                generation: firstGeneration,
                destination: .logs
            ) == "log-41"
        )
        #expect(
            store.workspace(
                controllerID: controllerID,
                destination: .logs
            ).selectedItemID == "selected-log"
        )
        #expect(!store.hasPendingPersistence)

        store.activateSession(
            controllerID: controllerID,
            generation: secondGeneration
        )

        #expect(
            store.scrollAnchorID(
                controllerID: controllerID,
                generation: secondGeneration,
                destination: .logs
            ) == nil
        )
        #expect(
            !store.updateScrollAnchor(
                controllerID: controllerID,
                generation: firstGeneration,
                destination: .logs,
                anchorID: "stale-log"
            )
        )
        #expect(
            store.updateScrollAnchor(
                controllerID: controllerID,
                generation: secondGeneration,
                destination: .logs,
                anchorID: "log-84"
            )
        )
        #expect(
            store.scrollAnchorID(
                controllerID: controllerID,
                generation: secondGeneration,
                destination: .logs
            ) == "log-84"
        )

        store.clearSessionBoundState(controllerID: controllerID)
        #expect(
            !store.updateScrollAnchor(
                controllerID: controllerID,
                generation: secondGeneration,
                destination: .logs,
                anchorID: "late-log"
            )
        )
    }
}
