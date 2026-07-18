import Foundation
import MicaCore
import Testing
@testable import Mica

struct ControllerManagementPresentationTests {
    @Test func sidebarHasElevenStableDestinationsAndControllersStartsManagement() {
        #expect(WorkbenchDestination.allCases.count == 11)
        #expect(WorkbenchDestination.allCases.filter { $0.group == .controllerManagement } == [
            .controllers, .configuration, .actions, .diagnostics,
        ])
        #expect(WorkbenchDestination.workbenchTabCases == [
            .overview, .proxies, .connections, .logs, .rules, .sources,
        ])
        #expect(WorkbenchDestination.controllers.shortcut == nil)
    }

    @Test func controllerFilteringPreservesManualOrderAndCompleteEndpointMatches() {
        let profiles = [
            Self.profile("C", host: "2001:db8::3"),
            Self.profile("A", host: "controller-a.example"),
            Self.profile("B", host: "controller-b.example"),
        ]

        #expect(ControllerManagementPresentation.filteredProfiles(profiles, matching: "", language: .english) == profiles)
        #expect(
            ControllerManagementPresentation.filteredProfiles(
                profiles,
                matching: "[2001:db8::3]",
                language: .english
            ).map(\.displayName) == ["C"]
        )
    }

    @Test func compactAndWideColumnsExposeEquivalentBusinessFields() {
        let wide = ControllerTableColumnModel.columns(for: .wide)
        let compact = ControllerTableColumnModel.columns(for: .compact)

        #expect(Set(wide.flatMap(\.fields)) == Set(compact.flatMap(\.fields)))
        #expect(wide.count == 7)
        #expect(compact.count == 3)
        #expect(compact.last?.id == .actions)
    }

    @Test func tableModeAccountsForFontScaleWithoutChangingRows() {
        #expect(ControllerManagementPresentation.tableMode(availableWidth: 1_200, fontMultiplier: 1) == .wide)
        #expect(ControllerManagementPresentation.tableMode(availableWidth: 820, fontMultiplier: 1) == .compact)
        #expect(ControllerManagementPresentation.tableMode(availableWidth: 1_200, fontMultiplier: 1.32) == .compact)
    }

    @Test func managementSelectionReconcilesWithoutImplyingActiveSelection() {
        let a = UUID()
        let b = UUID()
        let c = UUID()

        #expect(
            ControllerManagementPresentation.reconciledManagementSelection(
                b,
                previousOrder: [a, b, c],
                currentOrder: [a, c]
            ) == c
        )
        #expect(
            ControllerManagementPresentation.reconciledManagementSelection(
                a,
                previousOrder: [a, b, c],
                currentOrder: [a, c]
            ) == a
        )
    }

    @Test func explicitReorderNeverSortsNamesAutomatically() {
        let profiles = [Self.profile("C"), Self.profile("A"), Self.profile("B")]
        let moved = ControllerManagementPresentation.applying(
            .move(profiles[2].id, .up),
            to: profiles
        )

        #expect(moved.map(\.displayName) == ["C", "B", "A"])
        #expect(ControllerManagementPresentation.isReorderingEnabled(searchText: ""))
        #expect(!ControllerManagementPresentation.isReorderingEnabled(searchText: "A"))
    }

    private static func profile(_ name: String, host: String = "127.0.0.1") -> RouterProfile {
        RouterProfile(
            displayName: name,
            host: host,
            controllerKind: .unsupported
        )
    }
}
