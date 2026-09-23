import Foundation
import MicaCore
import Testing
@testable import Mica

struct WorkbenchDataProjectionTests {
    private struct AccessibilityPayloadFixtureRow: Identifiable, Equatable, Sendable {
        let id: String
        var summary: String
        var nonsemanticRevision: Int
    }

    @Test(arguments: [0, 1, 31, 32, 33, 2_000])
    func accessibilityWindowNeverExposesMoreThanItsBoundedCapacity(_ count: Int) {
        let window = WorkbenchAccessibilityWindow.resolve(totalCount: count)

        #expect(window.range.count == min(count, WorkbenchAccessibilityWindow.capacity))
        #expect(window.range.count <= 32)
        #expect(window.totalCount == count)
        #expect(window.lowerBound == 0)
    }

    @Test func accessibilityWindowTraversalCoversTwoThousandItemsExactlyOnce() {
        let count = 2_000
        var window = WorkbenchAccessibilityWindow.resolve(totalCount: count)
        var visited: [Int] = []

        while true {
            visited.append(contentsOf: window.range)
            guard let nextLowerBound = window.nextLowerBound else { break }
            window = WorkbenchAccessibilityWindow.resolve(
                totalCount: count,
                preferredLowerBound: nextLowerBound
            )
        }

        #expect(visited == Array(0..<count))
        #expect(window.pageNumber == window.pageCount)

        while let previousLowerBound = window.previousLowerBound {
            window = WorkbenchAccessibilityWindow.resolve(
                totalCount: count,
                preferredLowerBound: previousLowerBound
            )
        }
        #expect(window.range == 0..<32)
    }

    @Test func accessibilityWindowClampsAfterShrinkAndResetsForGenerationChange() {
        let beforeShrink = WorkbenchAccessibilityWindow.resolve(
            totalCount: 2_000,
            preferredLowerBound: 1_984
        )
        #expect(beforeShrink.range == 1_984..<2_000)

        let afterShrink = WorkbenchAccessibilityWindow.resolve(
            totalCount: 33,
            preferredLowerBound: beforeShrink.lowerBound
        )
        #expect(afterShrink.range == 32..<33)

        let generationReset = WorkbenchAccessibilityWindow.resolve(
            totalCount: 33,
            preferredLowerBound: 0
        )
        #expect(generationReset.range == 0..<32)
    }

    @Test func accessibilityWindowRevealsSelectionAndPreservesStableAnchor() throws {
        let orderedIDs = (0..<2_000).map { "row-\($0)" }
        let selected = WorkbenchAccessibilityWindowProjection.resolve(
            orderedIDs: orderedIDs,
            preferredLowerBound: 0,
            revealing: "row-1999"
        )
        #expect(selected.range == 1_984..<2_000)

        let anchored = WorkbenchAccessibilityWindowProjection.resolve(
            orderedIDs: orderedIDs,
            preferredLowerBound: selected.lowerBound,
            anchorID: "row-1984"
        )
        #expect(anchored == selected)

        let metricOnlyUpdate = WorkbenchAccessibilityWindowProjection.resolve(
            orderedIDs: orderedIDs,
            preferredLowerBound: anchored.lowerBound,
            anchorID: "row-1984"
        )
        #expect(metricOnlyUpdate == anchored)

        let shiftedIDs = Array(orderedIDs.dropFirst(9)) + (2_000..<2_009).map { "row-\($0)" }
        let shiftedAnchor = WorkbenchAccessibilityWindowProjection.resolve(
            orderedIDs: shiftedIDs,
            preferredLowerBound: anchored.lowerBound,
            anchorID: "row-1984"
        )
        let anchorIndex = try #require(shiftedIDs.firstIndex(of: "row-1984"))
        #expect(shiftedAnchor.range.contains(anchorIndex))
    }

    @Test func accessibilityWindowUsesExactStableIdentityForDuplicateAndBlankReportedIDs() {
        let stableIDs = [
            "duplicate#source-0",
            "duplicate#source-1",
            "unreported#source-2",
            "unreported#source-3",
        ] + (4..<40).map { "row-\($0)" }

        let duplicate = WorkbenchAccessibilityWindowProjection.resolve(
            orderedIDs: stableIDs,
            revealing: "duplicate#source-1"
        )
        let blank = WorkbenchAccessibilityWindowProjection.resolve(
            orderedIDs: stableIDs,
            revealing: "unreported#source-3"
        )

        #expect(duplicate.range.contains(1))
        #expect(blank.range.contains(3))
        #expect(stableIDs[1] != stableIDs[0])
        #expect(stableIDs[3] != stableIDs[2])
    }

    @Test func accessibilityCursorKeepsTheOlderPageAfterLeavingFollowNewest() throws {
        let orderedIDs = (0..<2_000).map { "log-\($0)" }
        var cursor = WorkbenchAccessibilityWindowCursor()

        let newest = cursor.reconcile(
            orderedIDs: orderedIDs,
            followsNewest: true
        )
        let previousLowerBound = try #require(newest.previousLowerBound)
        let older = cursor.move(
            to: previousLowerBound,
            orderedIDs: orderedIDs
        )
        let reconciled = cursor.reconcile(
            orderedIDs: orderedIDs,
            followsNewest: false
        )

        #expect(reconciled == older)
        #expect(reconciled.range != newest.range)
    }

    @Test func accessibilityCursorUsesIndexedLookupAfterMetricSortReordersRows() throws {
        let originalIDs = (0..<96).map { "connection-\($0)" }
        var cursor = WorkbenchAccessibilityWindowCursor()
        cursor.move(to: 64, orderedIDs: originalIDs)

        let reorderedIDs = ["connection-64"]
            + originalIDs.filter { $0 != "connection-64" }
        let indexByID = Dictionary(
            uniqueKeysWithValues: reorderedIDs.enumerated().map { ($0.element, $0.offset) }
        )
        var lookupCount = 0
        let reconciled = cursor.reconcile(
            totalCount: reorderedIDs.count,
            indexOf: {
                lookupCount += 1
                return indexByID[$0]
            },
            idAt: { reorderedIDs.indices.contains($0) ? reorderedIDs[$0] : nil }
        )

        let anchorIndex = try #require(indexByID["connection-64"])
        #expect(reconciled.range.contains(anchorIndex))
        #expect(cursor.anchorID == "connection-64")
        #expect(lookupCount == 1)
    }

    @Test func accessibilityCursorAppliesLogPrefixDeltaWithoutScanningTheOrder() throws {
        let originalIDs = (0..<2_000).map { "log-\($0)" }
        var cursor = WorkbenchAccessibilityWindowCursor()
        cursor.move(to: 1_952, orderedIDs: originalIDs)

        let shiftedIDs = Array(originalIDs.dropFirst(9))
            + (2_000..<2_009).map { "log-\($0)" }
        var idLookupCount = 0
        let shifted = cursor.applyPrefixDelta(
            totalCount: shiftedIDs.count,
            droppedCount: 9,
            followsNewest: false,
            idAt: {
                idLookupCount += 1
                return shiftedIDs.indices.contains($0) ? shiftedIDs[$0] : nil
            }
        )

        let stableAnchorIndex = try #require(shiftedIDs.firstIndex(of: "log-1952"))
        #expect(shifted.range.contains(stableAnchorIndex))
        #expect(cursor.anchorID == "log-1952")
        #expect(cursor.anchorIndex == stableAnchorIndex)
        #expect(idLookupCount == 0)

        let newest = cursor.applyPrefixDelta(
            totalCount: shiftedIDs.count,
            droppedCount: 0,
            followsNewest: true,
            idAt: { shiftedIDs.indices.contains($0) ? shiftedIDs[$0] : nil }
        )
        #expect(newest.range == 1_984..<2_000)
        #expect(cursor.anchorID == shiftedIDs[1_984])
    }

    @Test func logAccessibilityDeltaReportsOnlyVisiblePrefixDrops() {
        func entry(_ id: String, type: String) -> ControllerLogEntry {
            ControllerLogEntry(
                id: id,
                receivedAt: Date(timeIntervalSince1970: 1),
                message: LogMessage(type: type, payload: id)
            )
        }

        let first = entry("first", type: "info")
        let second = entry("second", type: "warning")
        let third = entry("third", type: "warning")
        let fourth = entry("fourth", type: "warning")
        var cache = WorkbenchLogProjectionCache()
        cache.project(
            entries: [first, second, third],
            revision: 1,
            level: .warning,
            query: "",
            language: .english,
            change: .replace
        )
        cache.project(
            entries: [second, third, fourth],
            revision: 2,
            level: .warning,
            query: "",
            language: .english,
            change: .delta(
                droppedEntryIDs: ["first"],
                appendedEntries: [fourth]
            )
        )
        #expect(cache.accessibilityOrderChange == .prefixDelta(droppedCount: 0))

        let fifth = entry("fifth", type: "warning")
        cache.project(
            entries: [third, fourth, fifth],
            revision: 3,
            level: .warning,
            query: "",
            language: .english,
            change: .delta(
                droppedEntryIDs: ["second"],
                appendedEntries: [fifth]
            )
        )
        #expect(cache.accessibilityOrderChange == .prefixDelta(droppedCount: 1))
    }

    @Test func tableAccessibilityPayloadMaterializesOnlyTheBoundedWindow() {
        let sourceRows = (0..<2_000).map {
            AccessibilityPayloadFixtureRow(
                id: "row-\($0)",
                summary: "Summary \($0)",
                nonsemanticRevision: 0
            )
        }
        let scope = WorkbenchSessionIdentity(
            controllerID: UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
            generation: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )
        let localization = MicaStrings.localizationContext(for: .english)
        var summaryCount = 0
        var actionCount = 0

        let payload = WorkbenchTableAccessibilityPayload.materialize(
            scope: scope,
            title: localization.localizedKey("dashboard.tab_connections"),
            sourceRows: sourceRows,
            window: WorkbenchAccessibilityWindow.resolve(
                totalCount: sourceRows.count,
                preferredLowerBound: 1_984
            ),
            selectedRowID: "row-1999",
            localization: localization,
            summary: { row, _ in
                summaryCount += 1
                return row.summary
            },
            namedAction: { _ in
                actionCount += 1
                return nil
            }
        )

        #expect(payload.rows.count == 16)
        #expect(payload.rows.count <= WorkbenchAccessibilityWindow.capacity)
        #expect(summaryCount == 16)
        #expect(actionCount == 16)
        #expect(payload.rows.map(\.id) == (1_984..<2_000).map { "row-\($0)" })
        #expect(payload.rows.last?.isSelected == true)
    }

    @Test func tableAccessibilityPayloadEqualityTracksOnlyResolvedSemantics() {
        let rows = (0..<40).map {
            AccessibilityPayloadFixtureRow(
                id: "row-\($0)",
                summary: "Summary \($0)",
                nonsemanticRevision: 0
            )
        }
        let scope = WorkbenchSessionIdentity(
            controllerID: UUID(uuidString: "00000000-0000-0000-0000-000000000011"),
            generation: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        )

        func payload(
            rows: [AccessibilityPayloadFixtureRow],
            lowerBound: Int = 0,
            selectedRowID: String? = nil,
            language: AppLanguage = .english,
            direction: WorkbenchAccessibilitySortDirection? = nil,
            actionTitle: String? = nil,
            scope: WorkbenchSessionIdentity
        ) -> WorkbenchTableAccessibilityPayload {
            let localization = MicaStrings.localizationContext(for: language)
            return WorkbenchTableAccessibilityPayload.materialize(
                scope: scope,
                title: localization.localizedKey("dashboard.tab_connections"),
                sourceRows: rows,
                window: WorkbenchAccessibilityWindow.resolve(
                    totalCount: rows.count,
                    preferredLowerBound: lowerBound
                ),
                selectedRowID: selectedRowID,
                localization: localization,
                sortOptions: [
                    WorkbenchAccessibilitySortOption(
                        id: "summary",
                        title: localization.localizedKey("dashboard.col_status"),
                        direction: direction
                    ),
                ],
                summary: { row, localization in
                    "\(localization.localizedKey("dashboard.col_status")): \(row.summary)"
                },
                namedAction: { _ in
                    actionTitle.map {
                        WorkbenchAccessibilityNamedAction(id: "fixture.action", title: $0)
                    }
                }
            )
        }

        let baseline = payload(rows: rows, scope: scope)
        var nonsemantic = rows
        nonsemantic[0].nonsemanticRevision = 1
        nonsemantic[39].summary = "Changed outside the active window"

        #expect(payload(rows: nonsemantic, scope: scope) == baseline)

        var changedSummary = rows
        changedSummary[0].summary = "Changed inside the active window"
        #expect(payload(rows: changedSummary, scope: scope) != baseline)
        #expect(payload(rows: rows, selectedRowID: "row-1", scope: scope) != baseline)
        #expect(payload(rows: rows, lowerBound: 32, scope: scope) != baseline)
        #expect(payload(rows: Array(rows.dropLast()), scope: scope) != baseline)
        #expect(payload(rows: rows, language: .simplifiedChinese, scope: scope) != baseline)
        #expect(payload(rows: rows, direction: .ascending, scope: scope) != baseline)
        #expect(payload(rows: rows, actionTitle: "Change state", scope: scope) != baseline)
        #expect(
            payload(
                rows: rows,
                scope: WorkbenchSessionIdentity(
                    controllerID: scope.controllerID,
                    generation: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
                )
            ) != baseline
        )
    }

    @MainActor
    @Test func tableAccessibilityHostEqualityIgnoresDispatcherIdentity() {
        let localization = MicaStrings.localizationContext(for: .english)
        let scope = WorkbenchSessionIdentity(
            controllerID: nil,
            generation: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        )
        let payload = WorkbenchTableAccessibilityPayload.materialize(
            scope: scope,
            title: "Table",
            sourceRows: [
                AccessibilityPayloadFixtureRow(
                    id: "row",
                    summary: "Summary",
                    nonsemanticRevision: 0
                ),
            ],
            window: WorkbenchAccessibilityWindow.resolve(totalCount: 1),
            selectedRowID: nil,
            localization: localization,
            summary: { row, _ in row.summary }
        )

        let first = WorkbenchTableAccessibilityHost(payload: payload) { _ in }
        let second = WorkbenchTableAccessibilityHost(payload: payload) { _ in
            Issue.record("Dispatcher must not participate in host equality")
        }

        #expect(first == second)
    }

    @Test func ruleAccessibilityMutationResolverRejectsStaleOrUnavailableIntents() throws {
        let scope = WorkbenchSessionIdentity(
            controllerID: UUID(uuidString: "00000000-0000-0000-0000-000000000031"),
            generation: UUID(uuidString: "00000000-0000-0000-0000-000000000032")!
        )
        let mutableRule = RuleViewState(
            id: "reported-rule",
            index: 7,
            type: "DOMAIN",
            payload: "example.com",
            proxy: "Policy",
            disabled: false,
            hasMutableExtra: true
        )
        let mutableRow = try #require(
            WorkbenchRuleProjection.rows(
                from: [mutableRule],
                connections: [],
                language: .english
            ).first
        )
        let intent = WorkbenchTableAccessibilityIntent.performNamedAction(
            rowID: mutableRow.id,
            actionID: WorkbenchRuleAccessibilityMutationResolver.actionID,
            scope: scope
        )

        func resolved(
            intent: WorkbenchTableAccessibilityIntent = intent,
            rows: [WorkbenchRuleRow] = [mutableRow],
            updatingRuleID: String? = nil,
            canRefresh: Bool = true,
            isBusy: Bool = false,
            supportsMutation: Bool = true
        ) -> RuleViewState? {
            WorkbenchRuleAccessibilityMutationResolver.resolve(
                intent: intent,
                currentScope: scope,
                rows: rows,
                updatingRuleID: updatingRuleID,
                canRefresh: canRefresh,
                isBusy: isBusy,
                supportsMutation: supportsMutation
            )
        }

        #expect(resolved() == mutableRule)
        #expect(
            WorkbenchRuleAccessibilityMutationResolver.namedAction(
                for: mutableRow,
                title: "Change state",
                updatingRuleID: nil,
                canRefresh: true,
                isBusy: false,
                supportsMutation: true
            )?.id == WorkbenchRuleAccessibilityMutationResolver.actionID
        )

        let staleScope = WorkbenchSessionIdentity(
            controllerID: scope.controllerID,
            generation: UUID(uuidString: "00000000-0000-0000-0000-000000000033")!
        )
        #expect(
            resolved(
                intent: .performNamedAction(
                    rowID: mutableRow.id,
                    actionID: WorkbenchRuleAccessibilityMutationResolver.actionID,
                    scope: staleScope
                )
            ) == nil
        )
        #expect(resolved(rows: []) == nil)
        #expect(resolved(updatingRuleID: mutableRule.id) == nil)
        #expect(resolved(canRefresh: false) == nil)
        #expect(resolved(isBusy: true) == nil)
        #expect(resolved(supportsMutation: false) == nil)
        #expect(
            resolved(
                intent: .performNamedAction(
                    rowID: mutableRow.id,
                    actionID: "different.action",
                    scope: scope
                )
            ) == nil
        )

        let updatedRule = RuleViewState(
            id: mutableRule.id,
            index: mutableRule.index,
            type: mutableRule.type,
            payload: mutableRule.payload,
            proxy: mutableRule.proxy,
            disabled: true,
            hasMutableExtra: true
        )
        let updatedRow = try #require(
            WorkbenchRuleProjection.rows(
                from: [updatedRule],
                connections: [],
                language: .english
            ).first
        )
        #expect(updatedRow.id == mutableRow.id)
        #expect(resolved(rows: [updatedRow]) == updatedRule)

        let missingIndexRule = RuleViewState(
            id: mutableRule.id,
            index: nil,
            type: mutableRule.type,
            payload: mutableRule.payload,
            proxy: mutableRule.proxy,
            disabled: mutableRule.disabled,
            hasMutableExtra: true
        )
        let missingIndexRow = try #require(
            WorkbenchRuleProjection.rows(
                from: [missingIndexRule],
                connections: [],
                language: .english
            ).first
        )
        #expect(missingIndexRow.id == mutableRow.id)
        #expect(resolved(rows: [missingIndexRow]) == nil)

        let immutableRow = try #require(
            WorkbenchRuleProjection.rows(
                from: [RuleViewState(
                    id: "immutable-rule",
                    type: "MATCH",
                    payload: "",
                    proxy: "DIRECT",
                    hasMutableExtra: false
                )],
                connections: [],
                language: .english
            ).first
        )
        #expect(resolved(rows: [immutableRow]) == nil)
    }

    @Test func sharedDataSearchKeepsUnicodeCaseInsensitiveSemantics() {
        #expect(WorkbenchDataSearch.contains("browser.app", in: "Browser.APP"))
        #expect(WorkbenchDataSearch.contains("mÜnchen", in: "München Edge"))
        #expect(WorkbenchDataSearch.contains("σίσυφος", in: "Σίσυφος"))
        #expect(WorkbenchDataSearch.contains("東京", in: "東京节点"))
        #expect(!WorkbenchDataSearch.contains("munchen", in: "München Edge"))
    }

    @Test func endpointStateDistinguishesUnavailableLoadingEmptyFilteredAndStale() {
        #expect(
            WorkbenchDataStateResolver.endpoint(
                hasController: false,
                isSupported: true,
                sourceCount: 0,
                visibleCount: 0,
                isFiltering: false,
                endpointStatus: .idle
            ) == .noController
        )
        #expect(
            WorkbenchDataStateResolver.endpoint(
                hasController: true,
                isSupported: true,
                sourceCount: 0,
                visibleCount: 0,
                isFiltering: false,
                endpointStatus: .checking
            ) == .loading
        )
        #expect(
            WorkbenchDataStateResolver.endpoint(
                hasController: true,
                isSupported: false,
                sourceCount: 0,
                visibleCount: 0,
                isFiltering: false,
                endpointStatus: .checking
            ) == .unsupported
        )
        #expect(
            WorkbenchDataStateResolver.endpoint(
                hasController: true,
                isSupported: true,
                sourceCount: 0,
                visibleCount: 0,
                isFiltering: false,
                endpointStatus: .failed("offline")
            ) == .failed("offline")
        )
        #expect(
            WorkbenchDataStateResolver.endpoint(
                hasController: true,
                isSupported: true,
                sourceCount: 2,
                visibleCount: 0,
                isFiltering: true,
                endpointStatus: .ready("2 rows")
            ) == .filterEmpty(staleMessage: nil)
        )
        #expect(
            WorkbenchDataStateResolver.endpoint(
                hasController: true,
                isSupported: true,
                sourceCount: 2,
                visibleCount: 2,
                isFiltering: false,
                endpointStatus: .failed("timeout")
            ) == .content(staleMessage: "timeout")
        )

        let stoppedDetail = MicaStrings.localizedKey(
            "live.detail_stopped",
            language: .english
        )
        #expect(
            WorkbenchDataStateResolver.endpoint(
                hasController: true,
                isSupported: true,
                sourceCount: 2,
                visibleCount: 2,
                isFiltering: false,
                endpointStatus: .ready("2 rows"),
                sessionState: .stopped,
                language: .english
            ) == .content(staleMessage: stoppedDetail)
        )
        #expect(
            WorkbenchDataStateResolver.endpoint(
                hasController: true,
                isSupported: true,
                sourceCount: 2,
                visibleCount: 0,
                isFiltering: true,
                endpointStatus: .ready("2 rows"),
                sessionState: .stopped,
                language: .english
            ) == .filterEmpty(staleMessage: stoppedDetail)
        )
    }

    @Test func logStateRetainsRowsAcrossStreamFailureAndPreservesFilterEmpty() {
        #expect(
            WorkbenchDataStateResolver.logs(
                hasController: true,
                isSupported: false,
                sourceCount: 0,
                visibleCount: 0,
                isFiltering: false,
                streamState: .connecting
            ) == .unsupported
        )
        #expect(
            WorkbenchDataStateResolver.logs(
                hasController: true,
                isSupported: true,
                sourceCount: 0,
                visibleCount: 0,
                isFiltering: false,
                streamState: .connecting
            ) == .loading
        )
        #expect(
            WorkbenchDataStateResolver.logs(
                hasController: true,
                isSupported: true,
                sourceCount: 2,
                visibleCount: 2,
                isFiltering: false,
                streamState: .partial("stream interrupted")
            ) == .content(staleMessage: "stream interrupted")
        )
        #expect(
            WorkbenchDataStateResolver.logs(
                hasController: true,
                isSupported: true,
                sourceCount: 2,
                visibleCount: 0,
                isFiltering: true,
                streamState: .failed("stream failed")
            ) == .filterEmpty(staleMessage: "stream failed")
        )

        let stoppedDetail = MicaStrings.localizedKey(
            "live.detail_stopped",
            language: .english
        )
        #expect(
            WorkbenchDataStateResolver.logs(
                hasController: true,
                isSupported: true,
                sourceCount: 2,
                visibleCount: 2,
                isFiltering: false,
                streamState: .live,
                sessionState: .stopped,
                language: .english
            ) == .content(staleMessage: stoppedDetail)
        )
    }

    @Test func dataWidthModeAndScrollPhaseUseDiscreteStableTransitions() {
        let budget = WorkbenchDataWidthBudget(
            fullMinimum: 900,
            compactMinimum: 500
        )
        #expect(budget.mode(for: 900) == .full)
        #expect(budget.mode(for: 899) == .compact)
        #expect(budget.mode(for: 500) == .compact)
        #expect(budget.mode(for: 499) == .stacked)

        var phase = WorkbenchDataScrollPhaseState()
        #expect(phase.update(isUserScrolling: false) == nil)
        #expect(phase.update(isUserScrolling: true) == .began)
        #expect(phase.update(isUserScrolling: true) == nil)
        #expect(phase.update(isUserScrolling: false) == .ended)
        phase.reset()
        #expect(!phase.isUserScrolling)
    }

    @Test func connectionProjectionKeepsCompleteValuesAndSortsOnlyTheCopy() {
        let source = [
            Self.connection(
                id: "low",
                upload: 10,
                host: "full.example.internal",
                destinationIP: "2001:db8::1",
                destinationPort: "443",
                process: "Browser",
                processPath: "/Applications/Browser.app/Contents/MacOS/Browser"
            ),
            Self.connection(
                id: "high",
                upload: 90,
                host: "api.example.internal",
                destinationIP: "203.0.113.9",
                destinationPort: "8443",
                process: "Terminal",
                processPath: "/Applications/Terminal.app/Contents/MacOS/Terminal"
            ),
        ]

        let rows = WorkbenchConnectionProjection.rows(from: source)
        #expect(rows.map(\.id) == ["low", "high"])
        #expect(rows[0].host == "full.example.internal")
        #expect(rows[0].destination == "[2001:db8::1]:443")
        #expect(rows[0].identityDetailText == "[2001:db8::1]:443 · tcp / HTTPS")
        #expect(rows[0].processNetworkText == "Browser · tcp / HTTPS")
        #expect(rows[0].rulePayloadText == "DOMAIN · full.example.internal")
        #expect(rows[0].ruleRouteText == "DOMAIN · Proxy → DIRECT")
        #expect(rows[0].stackedDetailText == "[2001:db8::1]:443 · DOMAIN · Proxy → DIRECT")
        #expect(rows[0].timestampText == "2026-07-27T10:00:00Z")
        #expect(rows[0].uploadDisplayText == "10 B")
        #expect(rows[0].uploadSummaryText == "↑ 10 B")
        #expect(rows[0].searchText.contains("/Applications/Browser.app/Contents/MacOS/Browser"))

        let sorted = WorkbenchConnectionProjection.visibleRows(
            from: rows,
            query: "",
            sortOrder: [KeyPathComparator(\WorkbenchConnectionRow.upload, order: .reverse)]
        )
        #expect(sorted.map(\.id) == ["high", "low"])
        #expect(source.map(\.id) == ["low", "high"])

        let filtered = WorkbenchConnectionProjection.visibleRows(
            from: rows,
            query: "browser.app",
            sortOrder: []
        )
        #expect(filtered.map(\.id) == ["low"])
    }

    @Test func connectionProjectionSeparatesActiveAndClosedRowsWithReceiptTime() throws {
        let active = Self.connection(
            id: "active",
            upload: 10,
            host: "active.example",
            destinationIP: "203.0.113.10",
            destinationPort: "443",
            process: "Browser",
            processPath: "/Applications/Browser.app"
        )
        let closed = Self.connection(
            id: "closed",
            upload: 9_999,
            host: "closed.example",
            destinationIP: "203.0.113.11",
            destinationPort: "443",
            process: "Terminal",
            processPath: "/Applications/Terminal.app"
        )
        let closedAt = Date(timeIntervalSince1970: 100)
        let records = [ClosedConnectionRecord(snapshot: closed, closedAt: closedAt)]

        let activeRows = WorkbenchConnectionProjection.rows(
            activeConnections: [active],
            closedConnections: records,
            scope: .active
        )
        let closedRows = WorkbenchConnectionProjection.rows(
            activeConnections: [active],
            closedConnections: records,
            scope: .closed
        )

        #expect(activeRows.map(\.connection.id) == ["active"])
        #expect(activeRows.reduce(0) { $0 + max(0, $1.upload) } == 10)
        #expect(activeRows.first?.closedAt == nil)
        #expect(closedRows.map(\.connection.id) == ["closed"])
        let closedRow = try #require(closedRows.first)
        #expect(closedRow.closedAt == closedAt)
    }

    @Test func duplicateAndBlankConnectionIdentitiesStayStableAcrossSourceReordering() throws {
        let first = Self.connection(
            id: "duplicate",
            upload: 1,
            host: "first.example",
            destinationIP: "203.0.113.1",
            destinationPort: "443",
            process: "First",
            processPath: "/Applications/First.app"
        )
        let second = Self.connection(
            id: "duplicate",
            upload: 2,
            host: "second.example",
            destinationIP: "203.0.113.2",
            destinationPort: "443",
            process: "Second",
            processPath: "/Applications/Second.app"
        )
        let blank = Self.connection(
            id: "  ",
            upload: 3,
            host: "blank.example",
            destinationIP: "203.0.113.3",
            destinationPort: "443",
            process: "Blank",
            processPath: "/Applications/Blank.app"
        )

        let initial = WorkbenchConnectionProjection.rows(from: [first, second, blank])
        let reordered = WorkbenchConnectionProjection.rows(from: [blank, second, first])
        let initialIDs = Dictionary(uniqueKeysWithValues: initial.map { ($0.host, $0.id) })
        let reorderedIDs = Dictionary(uniqueKeysWithValues: reordered.map { ($0.host, $0.id) })

        #expect(initialIDs == reorderedIDs)
        #expect(Set(initial.map(\.id)).count == 3)

        let selected = try #require(initial.first { $0.host == "second.example" })
        #expect(
            WorkbenchDataSelection.reconciled(
                selected.id,
                previousRows: initial,
                nextVisibleRows: reordered,
                identityFamily: \.identityFamily
            ) == selected.id
        )
    }

    @Test func connectionProjectionCacheSeparatesStaticMetricsAndVisibleWork() {
        var alpha = Self.connection(
            id: "alpha",
            upload: 10,
            host: "zeta.example",
            destinationIP: "203.0.113.10",
            destinationPort: "443",
            process: "Browser",
            processPath: "/Applications/Browser.app"
        )
        alpha.uploadSpeed = 1
        var beta = Self.connection(
            id: "beta",
            upload: 20,
            host: "alpha.example",
            destinationIP: "203.0.113.20",
            destinationPort: "443",
            process: "Terminal",
            processPath: "/Applications/Terminal.app"
        )
        beta.uploadSpeed = 2
        let hostSort = [
            KeyPathComparator(\WorkbenchConnectionRow.host, order: .forward),
        ]
        var cache = WorkbenchConnectionProjectionCache()

        cache.project(
            activeConnections: [alpha, beta],
            closedConnections: [],
            scope: .active,
            structureRevision: 1,
            metricsRevision: 1,
            closedRevision: 0,
            query: "",
            sortOrder: hostSort,
            language: .english
        )

        let alphaSearchText = cache.row(id: "alpha")?.searchText
        #expect(cache.visibleRows.map(\.id) == ["beta", "alpha"])
        #expect(cache.staticProjectionCount == 1)
        #expect(cache.metricsProjectionCount == 0)
        #expect(cache.staticRowProjectionCount == 2)
        #expect(cache.filterProjectionCount == 1)
        #expect(cache.sortProjectionCount == 1)

        alpha.upload = 4_096
        alpha.uploadSpeed = 512
        cache.project(
            activeConnections: [alpha, beta],
            closedConnections: [],
            scope: .active,
            structureRevision: 1,
            metricsRevision: 2,
            closedRevision: 0,
            query: "",
            sortOrder: hostSort,
            language: .english
        )

        #expect(cache.staticProjectionCount == 1)
        #expect(cache.metricsProjectionCount == 1)
        #expect(cache.metricsRowProjectionCount == 1)
        #expect(cache.filterProjectionCount == 1)
        #expect(cache.sortProjectionCount == 1)
        #expect(cache.visibleRows.map(\.id) == ["beta", "alpha"])
        #expect(cache.row(id: "alpha")?.searchText == alphaSearchText)
        #expect(cache.row(id: "alpha")?.uploadText == WorkbenchDataFormat.bytes(4_096))
        #expect(cache.row(id: "alpha")?.uploadRateText == WorkbenchDataFormat.rate(512, language: .english))

        let uploadSort = [
            KeyPathComparator(\WorkbenchConnectionRow.upload, order: .reverse),
        ]
        cache.project(
            activeConnections: [alpha, beta],
            closedConnections: [],
            scope: .active,
            structureRevision: 1,
            metricsRevision: 2,
            closedRevision: 0,
            query: "",
            sortOrder: uploadSort,
            language: .english
        )
        #expect(cache.visibleRows.map(\.id) == ["alpha", "beta"])
        #expect(cache.sortProjectionCount == 2)

        beta.upload = 8_192
        cache.project(
            activeConnections: [alpha, beta],
            closedConnections: [],
            scope: .active,
            structureRevision: 1,
            metricsRevision: 3,
            closedRevision: 0,
            query: "",
            sortOrder: uploadSort,
            language: .english
        )
        #expect(cache.visibleRows.map(\.id) == ["beta", "alpha"])
        #expect(cache.sortProjectionCount == 3)

        alpha.rulePayload = "changed-static-field"
        cache.project(
            activeConnections: [alpha, beta],
            closedConnections: [],
            scope: .active,
            structureRevision: 2,
            metricsRevision: 4,
            closedRevision: 0,
            query: "",
            sortOrder: uploadSort,
            language: .english,
            isActive: false
        )
        #expect(cache.staticProjectionCount == 1)

        cache.project(
            activeConnections: [alpha, beta],
            closedConnections: [],
            scope: .active,
            structureRevision: 2,
            metricsRevision: 4,
            closedRevision: 0,
            query: "",
            sortOrder: uploadSort,
            language: .english
        )
        #expect(cache.staticProjectionCount == 2)
        #expect(cache.row(id: "alpha")?.searchText.contains("changed-static-field") == true)
    }

    @Test func connectionProjectionCacheConsumesKeyedMetricsAndDefersLiveSort() {
        var alpha = Self.connection(
            id: "alpha",
            upload: 10,
            host: "alpha.example",
            destinationIP: "203.0.113.10",
            destinationPort: "443",
            process: "Alpha",
            processPath: "/Applications/Alpha.app"
        )
        var beta = Self.connection(
            id: "beta",
            upload: 20,
            host: "beta.example",
            destinationIP: "203.0.113.20",
            destinationPort: "443",
            process: "Beta",
            processPath: "/Applications/Beta.app"
        )
        let uploadSort = [
            KeyPathComparator(\WorkbenchConnectionRow.upload, order: .reverse),
        ]
        var cache = WorkbenchConnectionProjectionCache()

        cache.project(
            activeConnections: [alpha, beta],
            closedConnections: [],
            scope: .active,
            structureRevision: 1,
            metricsRevision: 1,
            closedRevision: 0,
            query: "",
            sortOrder: uploadSort,
            language: .english
        )
        #expect(cache.visibleRows.map(\.id) == ["beta", "alpha"])
        #expect(cache.metricsCandidateProjectionCount == 0)
        #expect(cache.sortProjectionCount == 1)

        alpha.upload = 30
        var alphaChange = ConnectionsCatalogChange.none
        alphaChange.changedMetricIndices = [0]
        cache.project(
            activeConnections: [alpha, beta],
            closedConnections: [],
            scope: .active,
            structureRevision: 1,
            metricsRevision: 2,
            closedRevision: 0,
            query: "",
            sortOrder: uploadSort,
            language: .english,
            change: alphaChange,
            deferMetricSorting: true
        )

        #expect(cache.metricsCandidateProjectionCount == 1)
        #expect(cache.metricsRowProjectionCount == 1)
        #expect(cache.visibleRows.map(\.id) == ["beta", "alpha"])
        #expect(cache.visibleRows.first(where: { $0.id == "alpha" })?.upload == 30)
        #expect(cache.sortProjectionCount == 1)
        let committedDeferredSort = cache.commitDeferredMetricSort()
        #expect(committedDeferredSort)
        #expect(cache.visibleRows.map(\.id) == ["alpha", "beta"])
        #expect(cache.sortProjectionCount == 2)
        let committedWithoutPendingSort = cache.commitDeferredMetricSort()
        #expect(!committedWithoutPendingSort)

        beta.upload = 40
        var betaChange = ConnectionsCatalogChange.none
        betaChange.changedMetricIndices = [1]
        cache.project(
            activeConnections: [alpha, beta],
            closedConnections: [],
            scope: .active,
            structureRevision: 1,
            metricsRevision: 4,
            closedRevision: 0,
            query: "",
            sortOrder: uploadSort,
            language: .english,
            change: betaChange
        )

        #expect(cache.metricsCandidateProjectionCount == 3)
        #expect(cache.visibleRows.map(\.id) == ["beta", "alpha"])
    }

    @Test func connectionMetricSortCadenceKeepsTheFirstBoundedDeadline() {
        let start = Date(timeIntervalSince1970: 10_000)
        var cadence = WorkbenchConnectionMetricSortCadence()

        cadence.schedule(now: start)
        let deadline = cadence.pendingDeadline
        cadence.schedule(now: start.addingTimeInterval(0.1))

        #expect(
            deadline
                == start.addingTimeInterval(
                    WorkbenchConnectionMetricSortCadence.maximumDeferral
                )
        )
        #expect(cadence.pendingDeadline == deadline)
        let consumedBeforeDeadline = cadence.consume(
            now: start.addingTimeInterval(0.199)
        )
        #expect(!consumedBeforeDeadline)
        let consumedAtDeadline = cadence.consume(
            now: start.addingTimeInterval(0.2)
        )
        #expect(consumedAtDeadline)
        #expect(cadence.pendingDeadline == nil)
    }

    @Test func connectionPulseProjectionTracksVisibleResultsAndStableOwners() {
        var connections = [
            Self.connection(
                id: "terminal-1",
                upload: 10,
                host: "terminal-one.example",
                destinationIP: "203.0.113.10",
                destinationPort: "443",
                process: "Terminal",
                processPath: "/Applications/Terminal.app"
            ),
            Self.connection(
                id: "browser",
                upload: 20,
                host: "browser.example",
                destinationIP: "203.0.113.20",
                destinationPort: "443",
                process: "Browser",
                processPath: "/Applications/Browser.app"
            ),
            Self.connection(
                id: "terminal-2",
                upload: 30,
                host: "terminal-two.example",
                destinationIP: "203.0.113.30",
                destinationPort: "443",
                process: "Terminal",
                processPath: "/Applications/Terminal.app"
            ),
            Self.connection(
                id: "mail",
                upload: 40,
                host: "mail.example",
                destinationIP: "203.0.113.40",
                destinationPort: "443",
                process: "Mail",
                processPath: "/Applications/Mail.app"
            ),
            Self.connection(
                id: "sync",
                upload: 50,
                host: "sync.example",
                destinationIP: "203.0.113.50",
                destinationPort: "443",
                process: "Sync",
                processPath: "/Applications/Sync.app"
            ),
        ]
        for index in connections.indices {
            connections[index].uploadSpeed = index + 1
            connections[index].downloadSpeed = (index + 1) * 2
        }

        var cache = WorkbenchConnectionProjectionCache()
        cache.project(
            activeConnections: connections,
            closedConnections: [],
            scope: .active,
            structureRevision: 1,
            metricsRevision: 1,
            closedRevision: 0,
            query: "",
            sortOrder: [],
            language: .english
        )

        let pulse = cache.pulseProjection
        #expect(pulse.visibleCount == 5)
        #expect(pulse.totalCount == 5)
        #expect(!pulse.isFiltered)
        #expect(pulse.uploadBytes == 150)
        #expect(pulse.downloadBytes == 300)
        #expect(pulse.totalBytes == 450)
        #expect(pulse.uploadRate == 15)
        #expect(pulse.downloadRate == 30)
        #expect(pulse.owners.map(\.id) == [
            "process:Terminal", "process:Browser", "process:Mail",
        ])
        #expect(pulse.owners.map(\.count) == [2, 1, 1])
        #expect(pulse.remainingOwnerCount == 1)

        cache.project(
            activeConnections: connections,
            closedConnections: [],
            scope: .active,
            structureRevision: 1,
            metricsRevision: 1,
            closedRevision: 0,
            query: "browser.app",
            sortOrder: [],
            language: .english
        )

        let filteredPulse = cache.pulseProjection
        #expect(filteredPulse.visibleCount == 1)
        #expect(filteredPulse.totalCount == 5)
        #expect(filteredPulse.isFiltered)
        #expect(filteredPulse.uploadBytes == 20)
        #expect(filteredPulse.downloadBytes == 40)
        #expect(filteredPulse.owners.map(\.id) == ["process:Browser"])
        #expect(filteredPulse.remainingOwnerCount == 0)
    }

    @Test func connectionPulseCacheSkipsSortRebuildAndAppliesKeyedMetricDeltas() {
        var alpha = Self.connection(
            id: "alpha",
            upload: 10,
            host: "alpha.example",
            destinationIP: "203.0.113.10",
            destinationPort: "443",
            process: "Alpha",
            processPath: "/Applications/Alpha.app"
        )
        alpha.uploadSpeed = 2
        alpha.downloadSpeed = 3
        var beta = Self.connection(
            id: "beta",
            upload: 20,
            host: "beta.example",
            destinationIP: "203.0.113.20",
            destinationPort: "443",
            process: "Beta",
            processPath: "/Applications/Beta.app"
        )
        beta.uploadSpeed = 4
        beta.downloadSpeed = 5
        var cache = WorkbenchConnectionProjectionCache()

        cache.project(
            activeConnections: [alpha, beta],
            closedConnections: [],
            scope: .active,
            structureRevision: 1,
            metricsRevision: 1,
            closedRevision: 0,
            query: "",
            sortOrder: [],
            language: .english
        )
        #expect(cache.pulseProjectionCount == 1)
        #expect(cache.pulseMetricUpdateCount == 0)

        cache.project(
            activeConnections: [alpha, beta],
            closedConnections: [],
            scope: .active,
            structureRevision: 1,
            metricsRevision: 1,
            closedRevision: 0,
            query: "",
            sortOrder: [KeyPathComparator(\WorkbenchConnectionRow.host, order: .reverse)],
            language: .english
        )
        #expect(cache.pulseProjectionCount == 1)
        #expect(cache.pulseMetricUpdateCount == 0)

        alpha.upload = 110
        alpha.download = 220
        alpha.uploadSpeed = 12
        alpha.downloadSpeed = 13
        var change = ConnectionsCatalogChange.none
        change.metricsChanged = true
        change.changedMetricIndices = [0]
        cache.project(
            activeConnections: [alpha, beta],
            closedConnections: [],
            scope: .active,
            structureRevision: 1,
            metricsRevision: 2,
            closedRevision: 0,
            query: "",
            sortOrder: [KeyPathComparator(\WorkbenchConnectionRow.host, order: .reverse)],
            language: .english,
            change: change
        )

        #expect(cache.pulseProjectionCount == 1)
        #expect(cache.pulseMetricUpdateCount == 1)
        #expect(cache.pulseMetricCandidateCount == 1)
        #expect(cache.pulseProjection.uploadBytes == 130)
        #expect(cache.pulseProjection.downloadBytes == 260)
        #expect(cache.pulseProjection.uploadRate == 16)
        #expect(cache.pulseProjection.downloadRate == 18)

        cache.project(
            activeConnections: [alpha, beta],
            closedConnections: [],
            scope: .active,
            structureRevision: 1,
            metricsRevision: 2,
            closedRevision: 0,
            query: "alpha.example",
            sortOrder: [],
            language: .english
        )
        #expect(cache.pulseProjectionCount == 2)

        beta.upload = 320
        var filteredOutChange = ConnectionsCatalogChange.none
        filteredOutChange.metricsChanged = true
        filteredOutChange.changedMetricIndices = [1]
        cache.project(
            activeConnections: [alpha, beta],
            closedConnections: [],
            scope: .active,
            structureRevision: 1,
            metricsRevision: 3,
            closedRevision: 0,
            query: "alpha.example",
            sortOrder: [],
            language: .english,
            change: filteredOutChange
        )
        #expect(cache.pulseMetricUpdateCount == 1)
        #expect(cache.pulseMetricCandidateCount == 1)
        #expect(cache.pulseProjection.uploadBytes == 110)
    }

    @Test func closedConnectionPulseNeverPresentsHistoricalRatesAsLive() {
        var closed = Self.connection(
            id: "closed",
            upload: 64,
            host: "closed.example",
            destinationIP: "203.0.113.64",
            destinationPort: "443",
            process: "Browser",
            processPath: "/Applications/Browser.app"
        )
        closed.uploadSpeed = 1_024
        closed.downloadSpeed = 2_048
        var cache = WorkbenchConnectionProjectionCache()

        cache.project(
            activeConnections: [],
            closedConnections: [
                ClosedConnectionRecord(snapshot: closed, closedAt: Date(timeIntervalSince1970: 1)),
            ],
            scope: .closed,
            structureRevision: 0,
            metricsRevision: 0,
            closedRevision: 1,
            query: "",
            sortOrder: [],
            language: .english
        )

        #expect(cache.pulseProjection.scope == .closed)
        #expect(cache.pulseProjection.uploadBytes == 64)
        #expect(cache.pulseProjection.downloadBytes == 128)
        #expect(cache.pulseProjection.uploadRate == nil)
        #expect(cache.pulseProjection.downloadRate == nil)
    }

    @Test func connectionPulseDistinguishesReportedZeroFromMissingMetrics() {
        var cache = WorkbenchConnectionProjectionCache()
        cache.project(
            activeConnections: [ConnectionSnapshot(id: "missing")],
            closedConnections: [],
            scope: .active,
            structureRevision: 1,
            metricsRevision: 1,
            closedRevision: 0,
            query: "",
            sortOrder: [],
            language: .english
        )

        #expect(cache.pulseProjection.uploadBytes == nil)
        #expect(cache.pulseProjection.downloadBytes == nil)
        #expect(cache.pulseProjection.totalBytes == nil)
        #expect(cache.pulseProjection.uploadRate == nil)
        #expect(cache.pulseProjection.downloadRate == nil)

        cache.project(
            activeConnections: [
                ConnectionSnapshot(
                    id: "zero",
                    upload: 0,
                    download: 0,
                    uploadSpeed: 0,
                    downloadSpeed: 0
                ),
            ],
            closedConnections: [],
            scope: .active,
            structureRevision: 2,
            metricsRevision: 2,
            closedRevision: 0,
            query: "",
            sortOrder: [],
            language: .english
        )

        #expect(cache.pulseProjection.uploadBytes == 0)
        #expect(cache.pulseProjection.downloadBytes == 0)
        #expect(cache.pulseProjection.totalBytes == 0)
        #expect(cache.pulseProjection.uploadRate == 0)
        #expect(cache.pulseProjection.downloadRate == 0)
    }

    @Test func ruleProjectionCountsActiveMatchesAndSupportsLocalizedFiltering() {
        let rules = [
            RuleViewState(
                id: "domain-rule",
                index: 0,
                type: "DOMAIN",
                payload: "example.com",
                proxy: "Proxy",
                disabled: false,
                hitCount: 12
            ),
            RuleViewState(
                id: "match-rule",
                index: 1,
                type: "MATCH",
                payload: "",
                proxy: "DIRECT",
                disabled: true,
                hitCount: 2
            ),
        ]
        let connections = [
            ConnectionSnapshot(id: "a", rule: "DOMAIN", rulePayload: "example.com"),
            ConnectionSnapshot(id: "b", rule: "DOMAIN", rulePayload: "example.com"),
            ConnectionSnapshot(id: "c", rule: "MATCH"),
        ]

        let rows = WorkbenchRuleProjection.rows(
            from: rules,
            connections: connections,
            language: .english
        )
        #expect(rows.map(\.activeConnections) == [2, 1])
        #expect(rows[0].indexText == "0")
        #expect(rows[0].indexSortValue == 0)
        #expect(rows[0].typeText == "DOMAIN")
        #expect(rows[0].definitionTitleText == "example.com")
        #expect(rows[0].definitionDetailText == "DOMAIN · #0")
        #expect(rows[0].targetText == "Proxy")
        #expect(rows[0].activeConnectionsText == "2")
        #expect(rows[0].hitCountText == "12")
        #expect(rows[0].activityText == "2 · 12")
        #expect(
            rows[0].activityAccessibilityText
                == "\(MicaStrings.localizedKey("dashboard.active_sessions", language: .english)): 2, \(MicaStrings.localizedKey("traffic.rule_hits", language: .english)): 12"
        )
        #expect(rows[0].statusText == MicaStrings.localizedKey("traffic.rule_status_enabled", language: .english))
        #expect(rows[1].statusText == MicaStrings.localizedKey("traffic.rule_status_disabled", language: .english))

        let sorted = WorkbenchRuleProjection.visibleRows(
            from: rows,
            query: "",
            sortOrder: [KeyPathComparator(\WorkbenchRuleRow.hitCount, order: .reverse)]
        )
        #expect(sorted.map(\.id) == ["domain-rule", "match-rule"])
        #expect(rules.map(\.id) == ["domain-rule", "match-rule"])

        let filtered = WorkbenchRuleProjection.visibleRows(
            from: rows,
            query: rows[1].statusText,
            sortOrder: []
        )
        #expect(filtered.map(\.id) == ["match-rule"])
    }

    @Test func ruleDecisionPathResolvesOnlyExactPolicyGroupTargets() throws {
        let catalog = PolicyGroupCatalogSnapshot(
            mode: "Global",
            groups: [
                ProxyGroupViewState(
                    id: "Proxy",
                    type: "Selector",
                    selected: "Node A",
                    options: ["Node A"]
                ),
                ProxyGroupViewState(
                    id: "proxy",
                    type: "Selector",
                    selected: "Node B",
                    options: ["Node B"]
                ),
                ProxyGroupViewState(
                    id: "GLOBAL",
                    type: "Selector",
                    selected: "Proxy",
                    options: ["Proxy", "proxy"]
                ),
            ]
        )

        let upper = WorkbenchRulePolicyTargetResolver.resolve(
            target: "Proxy",
            catalog: catalog,
            visibility: .followMode
        )
        let lower = WorkbenchRulePolicyTargetResolver.resolve(
            target: "proxy",
            catalog: catalog,
            visibility: .followMode
        )

        #expect(upper?.group.id == "Proxy")
        #expect(lower?.group.id == "proxy")
        #expect(
            WorkbenchRulePolicyTargetResolver.resolve(
                target: "PROXY",
                catalog: catalog,
                visibility: .followMode
            ) == nil
        )
        for target in ["DIRECT", "direct", "REJECT", "Node A", "Unknown"] {
            #expect(
                WorkbenchRulePolicyTargetResolver.resolve(
                    target: target,
                    catalog: catalog,
                    visibility: .followMode
                ) == nil
            )
        }

        let row = try #require(
            WorkbenchRuleProjection.rows(
                from: [
                    RuleViewState(
                        id: "path",
                        type: "DOMAIN",
                        payload: "example.com",
                        proxy: "Proxy",
                        disabled: false,
                        hitCount: 8,
                        missCount: 2
                    ),
                ],
                connections: [
                    ConnectionSnapshot(
                        id: "active",
                        rule: "DOMAIN",
                        rulePayload: "example.com"
                    ),
                ],
                language: .english
            ).first
        )
        let path = WorkbenchRuleDecisionPathProjection(row: row)

        #expect(path.type == "DOMAIN")
        #expect(path.payload == "example.com")
        #expect(path.target == "Proxy")
        #expect(path.activeConnections == 1)
        #expect(path.hitCount == 8)
        #expect(path.missCount == 2)
        #expect(path.isDisabled == false)
    }

    @Test func ruleNavigationResolvesOnlyTheExactSourceOccurrence() throws {
        let controllerID = UUID(uuidString: "00000000-0000-0000-0000-000000000041")!
        let generation = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
        let rules = [
            RuleViewState(
                id: "duplicate",
                type: "DOMAIN",
                payload: "same.example",
                proxy: "First"
            ),
            RuleViewState(
                id: "duplicate",
                type: "DOMAIN",
                payload: "same.example",
                proxy: "Second"
            ),
            RuleViewState(
                id: "",
                type: "MATCH",
                payload: "",
                proxy: "Third"
            ),
            RuleViewState(
                id: "",
                type: "MATCH",
                payload: "",
                proxy: "Fourth"
            ),
        ]
        let rows = WorkbenchRuleProjection.rows(
            from: rules,
            connections: [],
            language: .english
        )
        let duplicateSelection = WorkbenchRuleNavigationSelection(
            controllerID: controllerID,
            generation: generation,
            sourceIndex: 1,
            reportedRuleID: "duplicate",
            type: "DOMAIN",
            payload: "same.example"
        )
        let blankSelection = WorkbenchRuleNavigationSelection(
            controllerID: controllerID,
            generation: generation,
            sourceIndex: 3,
            reportedRuleID: "",
            type: "MATCH",
            payload: ""
        )

        #expect(rows.map(\.id).count == Set(rows.map(\.id)).count)
        #expect(
            WorkbenchRuleNavigationResolver.resolve(
                duplicateSelection,
                controllerID: controllerID,
                generation: generation,
                in: rows
            )?.id == rows[1].id
        )
        #expect(
            WorkbenchRuleNavigationResolver.resolve(
                blankSelection,
                controllerID: controllerID,
                generation: generation,
                in: rows
            )?.id == rows[3].id
        )
        #expect(
            WorkbenchRuleNavigationResolver.resolve(
                duplicateSelection,
                controllerID: UUID(),
                generation: generation,
                in: rows
            ) == nil
        )
        #expect(
            WorkbenchRuleNavigationResolver.resolve(
                duplicateSelection,
                controllerID: controllerID,
                generation: UUID(),
                in: rows
            ) == nil
        )

        var reordered = rows
        reordered.swapAt(0, 1)
        #expect(
            WorkbenchRuleNavigationResolver.resolve(
                duplicateSelection,
                controllerID: controllerID,
                generation: generation,
                in: reordered
            ) == nil
        )

        var changedRules = rules
        changedRules[1].payload = "changed.example"
        let changedRows = WorkbenchRuleProjection.rows(
            from: changedRules,
            connections: [],
            language: .english
        )
        #expect(
            WorkbenchRuleNavigationResolver.resolve(
                duplicateSelection,
                controllerID: controllerID,
                generation: generation,
                in: changedRows
            ) == nil
        )
    }

    @Test func connectionNavigationDirectoryKeepsOnlyUniqueExactTargets() throws {
        let rules = [
            RuleViewState(
                id: "unique",
                type: "DOMAIN",
                payload: "example.com",
                proxy: "Policy A"
            ),
            RuleViewState(
                id: "duplicate-first",
                type: "DOMAIN-SUFFIX",
                payload: "example.org",
                proxy: "Policy B"
            ),
            RuleViewState(
                id: "duplicate-second",
                type: "DOMAIN-SUFFIX",
                payload: "example.org",
                proxy: "Policy B"
            ),
            RuleViewState(
                id: "",
                type: "PROCESS-NAME",
                payload: "tool",
                proxy: "Policy A"
            ),
        ]
        let groups = ProxyProjection.arrangedGroups(
            [
                ProxyGroupViewState(
                    id: "Policy A",
                    type: "Selector",
                    selected: "Node A",
                    options: ["Node A"]
                ),
                ProxyGroupViewState(
                    id: "Duplicate",
                    type: "Selector",
                    selected: "Node B",
                    options: ["Node B"]
                ),
                ProxyGroupViewState(
                    id: "Duplicate",
                    type: "Selector",
                    selected: "Node C",
                    options: ["Node C"]
                ),
            ],
            mode: "Rule",
            visibility: .followMode
        )
        let directory = WorkbenchConnectionNavigationDirectory(
            rules: rules,
            groups: groups
        )

        #expect(
            directory.ruleTarget(type: "DOMAIN", payload: "example.com")?.reportedRuleID
                == "unique"
        )
        #expect(
            directory.ruleTarget(type: "DOMAIN", payload: "example.com")?.sourceIndex
                == 0
        )
        #expect(
            directory.ruleTarget(type: "domain", payload: "example.com") == nil
        )
        #expect(
            directory.ruleTarget(type: "DOMAIN-SUFFIX", payload: "example.org") == nil
        )
        #expect(
            directory.ruleTarget(type: "PROCESS-NAME", payload: "tool")
                == WorkbenchConnectionRuleNavigationTarget(
                    sourceIndex: 3,
                    reportedRuleID: "",
                    type: "PROCESS-NAME",
                    payload: "tool"
                )
        )
        #expect(directory.policyTarget(named: "Policy A")?.group.id == "Policy A")
        #expect(directory.policyTarget(named: "policy a") == nil)
        #expect(directory.policyTarget(named: "Duplicate") == nil)
        #expect(directory.policyTarget(named: "DIRECT") == nil)
        #expect(directory.policyTarget(named: "REJECT") == nil)

        let row = try #require(
            WorkbenchConnectionProjection.rows(
                from: [
                    ConnectionSnapshot(
                        id: "connection",
                        chains: ["Policy A", "Node A"],
                        providerChains: ["Provider A"],
                        rule: "DOMAIN",
                        rulePayload: "example.com",
                        metadata: ConnectionMetadataSnapshot(
                            host: "example.com",
                            sourceIP: "192.0.2.10",
                            destinationIP: "203.0.113.10",
                            sourcePort: "51000",
                            destinationPort: "443",
                            process: "Browser",
                            inboundIP: "127.0.0.1",
                            inboundPort: "7890",
                            inboundName: "mixed-in"
                        )
                    ),
                ]
            ).first
        )
        let path = WorkbenchConnectionDecisionPathProjection(row: row)

        #expect(path.rule == "DOMAIN")
        #expect(path.payload == "example.com")
        #expect(path.origin == "Browser · 192.0.2.10:51000")
        #expect(path.inbound == "mixed-in · 127.0.0.1:7890")
        #expect(path.destination == "example.com · 203.0.113.10:443")
        #expect(path.segments.map { $0.value } == ["Provider A", "Policy A", "Node A"])
        #expect(
            path.segments.map { $0.kind }
                == [
                    WorkbenchConnectionDecisionPathSegment.Kind.provider,
                    WorkbenchConnectionDecisionPathSegment.Kind.policy,
                    WorkbenchConnectionDecisionPathSegment.Kind.policy,
                ]
        )
    }

    @Test func ruleConnectionIndexBuildsOncePerControllerGenerationAndRevision() {
        let controllerID = UUID()
        let generation = UUID()
        let rule = RuleViewState(
            id: "rule",
            type: "DOMAIN",
            payload: "example.com",
            proxy: "Proxy"
        )
        var cache = WorkbenchRuleConnectionIndexCache()

        let initial = cache.resolve(
            connections: [ConnectionSnapshot(id: "one", rule: "DOMAIN", rulePayload: "example.com")],
            controllerID: controllerID,
            generation: generation,
            revision: 4
        )
        let sameRevision = cache.resolve(
            connections: [],
            controllerID: controllerID,
            generation: generation,
            revision: 4
        )

        #expect(initial.count(for: rule) == 1)
        #expect(sameRevision.count(for: rule) == 1)
        #expect(cache.rebuildCount == 1)

        let nextRevision = cache.resolve(
            connections: [],
            controllerID: controllerID,
            generation: generation,
            revision: 5
        )
        #expect(nextRevision.count(for: rule) == 0)
        #expect(cache.rebuildCount == 2)
    }

    @Test func ruleProjectionCacheRebuildsConnectionHitsOnlyForStructureRevision() {
        let controllerID = UUID()
        let generation = UUID()
        let rules = [
            RuleViewState(
                id: "domain-rule",
                type: "DOMAIN",
                payload: "example.com",
                proxy: "Proxy"
            ),
            RuleViewState(
                id: "match-rule",
                type: "MATCH",
                payload: "",
                proxy: "DIRECT"
            ),
        ]
        var first = ConnectionSnapshot(
            id: "first",
            upload: 1,
            rule: "DOMAIN",
            rulePayload: "example.com"
        )
        var cache = WorkbenchRuleProjectionCache()

        cache.project(
            update: .source,
            rules: rules,
            connections: [first],
            controllerID: controllerID,
            generation: generation,
            structureRevision: 10,
            query: "",
            sortOrder: [],
            language: .english
        )

        #expect(cache.allRows.map(\.activeConnections) == [1, 0])
        #expect(cache.staticProjectionCount == 1)
        #expect(cache.connectionIndexRebuildCount == 1)
        #expect(cache.activeCountProjectionCount == 0)

        first.upload = 999
        cache.project(
            update: .connectionStructure,
            rules: rules,
            connections: [first],
            controllerID: controllerID,
            generation: generation,
            structureRevision: 10,
            query: "",
            sortOrder: [],
            language: .english
        )

        #expect(cache.connectionIndexRebuildCount == 1)
        #expect(cache.activeCountProjectionCount == 0)
        #expect(cache.staticProjectionCount == 1)

        let second = ConnectionSnapshot(
            id: "second",
            rule: "DOMAIN",
            rulePayload: "example.com"
        )
        cache.project(
            update: .connectionStructure,
            rules: rules,
            connections: [first, second],
            controllerID: controllerID,
            generation: generation,
            structureRevision: 11,
            query: "",
            sortOrder: [],
            language: .english
        )

        #expect(cache.allRows.map(\.activeConnections) == [2, 0])
        #expect(cache.connectionIndexRebuildCount == 2)
        #expect(cache.activeCountProjectionCount == 1)
        #expect(cache.activeCountRowProjectionCount == 1)
        #expect(cache.staticProjectionCount == 1)

        cache.project(
            update: .visibleOnly,
            rules: rules,
            connections: [first, second],
            controllerID: controllerID,
            generation: generation,
            structureRevision: 11,
            query: "example.com",
            sortOrder: [
                KeyPathComparator(\WorkbenchRuleRow.activeConnections, order: .reverse),
            ],
            language: .english
        )
        #expect(cache.visibleRows.map(\.id) == ["domain-rule"])
        #expect(cache.connectionIndexRebuildCount == 2)
        #expect(cache.staticProjectionCount == 1)

        cache.project(
            update: .source,
            rules: rules,
            connections: [first, second],
            controllerID: controllerID,
            generation: generation,
            structureRevision: 11,
            query: "example.com",
            sortOrder: [],
            language: .simplifiedChinese,
            isActive: false
        )
        #expect(cache.staticProjectionCount == 1)
    }

    @Test func sourceProjectionPreservesControllerOrderAndFiltersByKind() {
        let sources = [
            ProxyProviderViewState(
                kind: .rule,
                name: "Rule Source",
                type: "HTTP",
                updatedAt: "1970-01-01T00:00:00Z",
                itemCount: 20
            ),
            ProxyProviderViewState(
                kind: .proxy,
                name: "Proxy Source",
                type: "File",
                behavior: "domain",
                format: "yaml",
                testURL: "https://probe.example.test/generate_204",
                subscriptionInfo: .object(["remaining": .number(2048)]),
                itemCount: 4
            ),
        ]

        let rows = WorkbenchSourceProjection.rows(from: sources, language: .english)
        #expect(rows.map(\.name) == ["Rule Source", "Proxy Source"])
        #expect(rows[0].updatedText == MicaStrings.localizedKey("overview.config_not_reported", language: .english))
        #expect(rows[1].typeText == "File")
        #expect(rows[1].configurationDetailText == "yaml · domain")
        #expect(rows[1].compactConfigurationText == "File · yaml · domain")
        #expect(rows[1].itemCountText == "4")
        #expect(rows[1].compactStatusText == "4 · Not reported")
        #expect(
            rows[1].statusAccessibilityText
                == "Read-only, This source does not report an available health-check configuration."
        )

        let proxyRows = WorkbenchSourceProjection.visibleRows(
            from: rows,
            kind: .proxy,
            query: "yaml",
            sortOrder: []
        )
        #expect(proxyRows.map(\.name) == ["Proxy Source"])

        let metadataRows = WorkbenchSourceProjection.visibleRows(
            from: rows,
            kind: .all,
            query: "2048",
            sortOrder: []
        )
        #expect(metadataRows.map(\.name) == ["Proxy Source"])

        let sorted = WorkbenchSourceProjection.visibleRows(
            from: rows,
            kind: .all,
            query: "",
            sortOrder: [KeyPathComparator(\WorkbenchSourceRow.itemCount, order: .forward)]
        )
        #expect(sorted.map(\.name) == ["Proxy Source", "Rule Source"])
        #expect(sources.map(\.name) == ["Rule Source", "Proxy Source"])
    }

    @Test func sourceFocusProjectionUsesOnlyTheSelectedReportedSource() throws {
        let source = ProxyProviderViewState(
            kind: .proxy,
            name: "Selected Source",
            type: "HTTP",
            updatedAt: "2026-08-01T10:00:00Z",
            updatable: true,
            healthCheck: .object(["alive": .bool(true)]),
            itemCount: 42
        )
        let row = try #require(
            WorkbenchSourceProjection.rows(
                from: [source],
                language: .english
            ).first
        )
        let focus = WorkbenchSourceFocusProjection(row: row)

        #expect(focus.name == "Selected Source")
        #expect(focus.configuration == "Proxy · HTTP")
        #expect(focus.itemCount == "42")
        #expect(focus.updatedAt == row.updatedText)
        #expect(focus.updatableStatus == "Updatable")
        #expect(focus.healthAvailability == "Available")
        #expect(focus.health?.contains("alive") == true)
    }

    @Test func sourceUpdateTargetsPreserveReportedOrderAndSkipReadOnlyEntries() {
        let sources = [
            ProxyProviderViewState(
                kind: .rule,
                name: "Rule Remote",
                type: "HTTP",
                updatable: true,
                itemCount: 1
            ),
            ProxyProviderViewState(
                kind: .proxy,
                name: "Local File",
                type: "File",
                updatable: false,
                itemCount: 2
            ),
            ProxyProviderViewState(
                kind: .proxy,
                name: "Proxy Remote",
                type: "HTTP",
                updatable: true,
                itemCount: 3
            ),
        ]

        #expect(
            WorkbenchSourceProjection.updateTargets(from: sources).map(\.name)
                == ["Rule Remote", "Proxy Remote"]
        )
        #expect(sources.map(\.name) == ["Rule Remote", "Local File", "Proxy Remote"])
    }

    @Test func sourceProjectionCacheSeparatesSourceFormattingFromVisibleFilters() {
        let sources = [
            ProxyProviderViewState(
                kind: .rule,
                name: "Rule Remote",
                type: "HTTP",
                updatedAt: "2026-07-29T10:00:00Z",
                updatable: true,
                itemCount: 20
            ),
            ProxyProviderViewState(
                kind: .proxy,
                name: "Proxy File",
                type: "File",
                behavior: "domain",
                format: "yaml",
                updatable: false,
                itemCount: 4
            ),
        ]
        var cache = WorkbenchSourceProjectionCache()

        cache.project(
            update: .source,
            sources: sources,
            kind: .all,
            query: "",
            sortOrder: [],
            language: .english
        )
        #expect(cache.sourceProjectionCount == 1)
        #expect(cache.staticRowProjectionCount == 2)
        #expect(cache.filterProjectionCount == 1)
        #expect(cache.updatableSourceCount == 1)

        cache.project(
            update: .visibleOnly,
            sources: sources,
            kind: .proxy,
            query: "yaml",
            sortOrder: [
                KeyPathComparator(\WorkbenchSourceRow.itemCount, order: .reverse),
            ],
            language: .english
        )
        #expect(cache.visibleRows.map(\.name) == ["Proxy File"])
        #expect(cache.sourceProjectionCount == 1)
        #expect(cache.staticRowProjectionCount == 2)
        #expect(cache.filterProjectionCount == 2)
        #expect(cache.sortProjectionCount == 1)

        cache.project(
            update: .source,
            sources: [],
            kind: .all,
            query: "",
            sortOrder: [],
            language: .english,
            isActive: false
        )
        #expect(cache.sourceProjectionCount == 1)
        #expect(cache.allRows.count == 2)
    }

    @Test func logSeverityIsStableAndRetainsExplicitTextOutsideColor() throws {
        #expect(WorkbenchLogSeverity(type: "err", level: nil) == .error)
        #expect(WorkbenchLogSeverity(type: "information", level: nil) == .info)
        #expect(WorkbenchLogSeverity(type: "debug", level: "warn") == .warning)
        #expect(WorkbenchLogSeverity(type: "trace", level: nil) == .trace)
        #expect(WorkbenchLogSeverity(type: "unrecognized", level: nil) == .info)

        guard let row = WorkbenchLogProjection.rows(
            from: [
                ControllerLogEntry(
                    id: "warning",
                    receivedAt: Date(timeIntervalSince1970: 1),
                    message: LogMessage(
                        type: "debug",
                        payload: "controller warning",
                        level: "warn"
                    )
                ),
            ]
        ).first else {
            Issue.record("Expected a projected log row")
            return
        }

        #expect(row.severity == .warning)
        #expect(row.levelText == "warn")
        #expect(row.typeText == "debug")
        #expect(
            WorkbenchLogProjection.accessibilitySummary(
                for: row,
                localization: MicaStrings.localizationContext(for: .english)
            ).contains("controller warning")
        )
    }

    @Test func boundedAccessibilitySummariesSwitchLabelsWithoutChangingRowValues() throws {
        let english = MicaStrings.localizationContext(for: .english)
        let simplifiedChinese = MicaStrings.localizationContext(for: .simplifiedChinese)
        let connectionRow = try #require(
            WorkbenchConnectionProjection.rows(
                from: [Self.connection(
                    id: "localized-connection",
                    upload: 64,
                    host: "summary.example",
                    destinationIP: "203.0.113.10",
                    destinationPort: "443",
                    process: "Browser",
                    processPath: "/Applications/Browser.app"
                )],
                language: .english
            ).first
        )
        let logRow = try #require(
            WorkbenchLogProjection.rows(
                from: [ControllerLogEntry(
                    id: "localized-log",
                    receivedAt: Date(timeIntervalSince1970: 1),
                    message: LogMessage(type: "info", payload: "summary payload")
                )],
                language: .english
            ).first
        )
        let ruleRow = try #require(
            WorkbenchRuleProjection.rows(
                from: [RuleViewState(
                    id: "localized-rule",
                    index: 7,
                    type: "DOMAIN",
                    payload: "summary.example",
                    proxy: "Policy"
                )],
                connections: [],
                language: .english
            ).first
        )
        let sourceRow = try #require(
            WorkbenchSourceProjection.rows(
                from: [ProxyProviderViewState(
                    kind: .proxy,
                    name: "Summary Provider",
                    type: "HTTP",
                    itemCount: 4
                )],
                language: .english
            ).first
        )

        let summaries = [
            (
                WorkbenchConnectionProjection.accessibilitySummary(
                    for: connectionRow,
                    localization: english
                ),
                WorkbenchConnectionProjection.accessibilitySummary(
                    for: connectionRow,
                    localization: simplifiedChinese
                ),
                english.localizedKey("traffic.connection_host"),
                simplifiedChinese.localizedKey("traffic.connection_host"),
                connectionRow.host
            ),
            (
                WorkbenchLogProjection.accessibilitySummary(
                    for: logRow,
                    localization: english
                ),
                WorkbenchLogProjection.accessibilitySummary(
                    for: logRow,
                    localization: simplifiedChinese
                ),
                english.localizedKey("traffic.log_payload"),
                simplifiedChinese.localizedKey("traffic.log_payload"),
                logRow.payloadText
            ),
            (
                WorkbenchRuleProjection.accessibilitySummary(
                    for: ruleRow,
                    localization: english
                ),
                WorkbenchRuleProjection.accessibilitySummary(
                    for: ruleRow,
                    localization: simplifiedChinese
                ),
                english.localizedKey("dashboard.col_payload"),
                simplifiedChinese.localizedKey("dashboard.col_payload"),
                ruleRow.rule.payload
            ),
            (
                WorkbenchSourceProjection.accessibilitySummary(
                    for: sourceRow,
                    localization: english
                ),
                WorkbenchSourceProjection.accessibilitySummary(
                    for: sourceRow,
                    localization: simplifiedChinese
                ),
                english.localizedKey("dashboard.col_provider"),
                simplifiedChinese.localizedKey("dashboard.col_provider"),
                sourceRow.source.name
            ),
        ]

        for (englishSummary, chineseSummary, englishLabel, chineseLabel, value) in summaries {
            #expect(englishSummary.contains("\(englishLabel): \(value)"))
            #expect(chineseSummary.contains("\(chineseLabel): \(value)"))
            #expect(englishSummary != chineseSummary)
        }
    }

    @Test func logProjectionNeverSortsAndFilteringRetainsIncomingOrder() {
        let entries = [
            ControllerLogEntry(
                id: "first",
                receivedAt: Date(timeIntervalSince1970: 1),
                message: LogMessage(type: "warn", payload: "first warning")
            ),
            ControllerLogEntry(
                id: "second",
                receivedAt: Date(timeIntervalSince1970: 2),
                message: LogMessage(type: "info", payload: "second info")
            ),
            ControllerLogEntry(
                id: "third",
                receivedAt: Date(timeIntervalSince1970: 3),
                message: LogMessage(type: "warning", payload: "third warning")
            ),
        ]

        let rows = WorkbenchLogProjection.rows(from: entries)
        #expect(rows.map(\.id) == ["first", "second", "third"])

        let warnings = WorkbenchLogProjection.visibleRows(
            from: rows,
            level: .warning,
            query: "warning"
        )
        #expect(warnings.map(\.id) == ["first", "third"])
        #expect(entries.map(\.id) == ["first", "second", "third"])
    }

    @Test func logProjectionCacheReusesSourceRowsAcrossFiltersAtTwoThousandEntries() {
        let entries = (0..<2_000).map { index in
            ControllerLogEntry(
                id: "log-\(index)",
                receivedAt: Date(timeIntervalSince1970: TimeInterval(index + 1)),
                message: LogMessage(
                    type: index.isMultiple(of: 2) ? "info" : "warning",
                    payload: "payload-\(index)"
                )
            )
        }
        var cache = WorkbenchLogProjectionCache()

        cache.project(
            entries: entries,
            revision: 1,
            level: .all,
            query: "",
            language: .english
        )
        #expect(cache.allRows.count == 2_000)
        #expect(cache.sourceProjectionCount == 1)
        #expect(cache.filterProjectionCount == 1)
        #expect(cache.fullProjectionCount == 1)
        #expect(cache.incrementalProjectionCount == 0)
        #expect(cache.formattedRowCount == 2_000)
        #expect(cache.reusedRowCount == 0)
        #expect(cache.filterEvaluationCount == 0)

        cache.project(
            entries: entries,
            revision: 1,
            level: .warning,
            query: "payload-1999",
            language: .english
        )
        #expect(cache.sourceProjectionCount == 1)
        #expect(cache.filterProjectionCount == 2)
        #expect(cache.visibleRows.map(\.entry.id) == ["log-1999"])
        #expect(cache.filterEvaluationCount == 2_000)

        cache.project(
            entries: entries,
            revision: 1,
            level: .warning,
            query: "payload-1999",
            language: .english
        )
        #expect(cache.sourceProjectionCount == 1)
        #expect(cache.filterProjectionCount == 2)
        #expect(cache.filterEvaluationCount == 2_000)

        let nextEntries = Array(entries.dropFirst()) + [
            ControllerLogEntry(
                id: "log-2000",
                receivedAt: Date(timeIntervalSince1970: 2_001),
                message: LogMessage(type: "warning", payload: "payload-2000")
            ),
        ]
        cache.project(
            entries: nextEntries,
            revision: 2,
            level: .warning,
            query: "payload-1999",
            language: .english
        )

        #expect(cache.sourceProjectionCount == 2)
        #expect(cache.fullProjectionCount == 1)
        #expect(cache.incrementalProjectionCount == 1)
        #expect(cache.formattedRowCount == 2_001)
        #expect(cache.reusedRowCount == 1_999)
        #expect(cache.filterEvaluationCount == 2_001)
        #expect(cache.allRows.count == 2_000)
        #expect(cache.allRows.first?.entry.id == "log-1")
        #expect(cache.allRows.last?.entry.id == "log-2000")
        #expect(cache.visibleRows.map(\.entry.id) == ["log-1999"])

        cache.project(
            entries: nextEntries,
            revision: 2,
            level: .all,
            query: "",
            language: .english
        )
        #expect(cache.visibleRows.map(\.entry.id) == nextEntries.map(\.id))
        #expect(cache.formattedRowCount == 2_001)
    }

    @Test func logProjectionCacheConsumesContiguousDeltaAndFallsBackAfterGap() {
        let first = ControllerLogEntry(
            id: "first",
            receivedAt: Date(timeIntervalSince1970: 1),
            message: LogMessage(type: "info", payload: "drop")
        )
        let second = ControllerLogEntry(
            id: "second",
            receivedAt: Date(timeIntervalSince1970: 2),
            message: LogMessage(type: "warning", payload: "keep second")
        )
        let third = ControllerLogEntry(
            id: "third",
            receivedAt: Date(timeIntervalSince1970: 3),
            message: LogMessage(type: "warning", payload: "keep third")
        )
        let fourth = ControllerLogEntry(
            id: "fourth",
            receivedAt: Date(timeIntervalSince1970: 4),
            message: LogMessage(type: "warning", payload: "keep fourth")
        )
        let fifth = ControllerLogEntry(
            id: "fifth",
            receivedAt: Date(timeIntervalSince1970: 5),
            message: LogMessage(type: "warning", payload: "keep fifth")
        )
        var cache = WorkbenchLogProjectionCache()

        cache.project(
            entries: [first, second, third],
            revision: 1,
            level: .warning,
            query: "keep",
            language: .english,
            change: .replace
        )
        #expect(cache.visibleRows.map(\.id) == ["second", "third"])
        #expect(cache.formattedRowCount == 3)
        #expect(cache.filterEvaluationCount == 3)

        cache.project(
            entries: [second, third, fourth],
            revision: 2,
            level: .warning,
            query: "keep",
            language: .english,
            change: .delta(
                droppedEntryIDs: ["first"],
                appendedEntries: [fourth]
            )
        )

        #expect(cache.deltaProjectionCount == 1)
        #expect(cache.incrementalProjectionCount == 1)
        #expect(cache.formattedRowCount == 4)
        #expect(cache.reusedRowCount == 2)
        #expect(cache.filterEvaluationCount == 4)
        #expect(cache.allRows.map(\.id) == ["second", "third", "fourth"])
        #expect(cache.visibleRows.map(\.id) == ["second", "third", "fourth"])
        #expect(cache.accessibilityOrderChange == .prefixDelta(droppedCount: 0))

        cache.project(
            entries: [third, fourth, fifth],
            revision: 4,
            level: .warning,
            query: "keep",
            language: .english,
            change: .delta(
                droppedEntryIDs: ["second"],
                appendedEntries: [fifth]
            )
        )

        #expect(cache.deltaProjectionCount == 1)
        #expect(cache.incrementalProjectionCount == 2)
        #expect(cache.formattedRowCount == 5)
        #expect(cache.allRows.map(\.id) == ["third", "fourth", "fifth"])
        #expect(cache.visibleRows.map(\.id) == ["third", "fourth", "fifth"])
        #expect(cache.accessibilityOrderChange == .replace)
    }

    @Test func logProjectionCacheFallsBackForDuplicateOrBlankControllerIDs() {
        let first = ControllerLogEntry(
            id: "duplicate",
            receivedAt: Date(timeIntervalSince1970: 1),
            message: LogMessage(type: "info", payload: "first")
        )
        let second = ControllerLogEntry(
            id: "duplicate",
            receivedAt: Date(timeIntervalSince1970: 2),
            message: LogMessage(type: "info", payload: "second")
        )
        let blank = ControllerLogEntry(
            id: " ",
            receivedAt: Date(timeIntervalSince1970: 3),
            message: LogMessage(type: "info", payload: "blank")
        )
        var cache = WorkbenchLogProjectionCache()

        cache.project(
            entries: [first, second],
            revision: 1,
            level: .all,
            query: "",
            language: .english
        )
        cache.project(
            entries: [second, blank],
            revision: 2,
            level: .all,
            query: "",
            language: .english
        )

        #expect(cache.fullProjectionCount == 2)
        #expect(cache.incrementalProjectionCount == 0)
        #expect(cache.allRows.map(\.entry) == [second, blank])
        #expect(Set(cache.allRows.map(\.id)).count == 2)
    }

    @Test func logProjectionCacheUsesStableIDsForReorderingSelectionAndVisibility() {
        let entries = [
            ControllerLogEntry(
                id: "first",
                receivedAt: Date(timeIntervalSince1970: 1),
                message: LogMessage(type: "info", payload: "first")
            ),
            ControllerLogEntry(
                id: "second",
                receivedAt: Date(timeIntervalSince1970: 2),
                message: LogMessage(type: "warning", payload: "second")
            ),
            ControllerLogEntry(
                id: "third",
                receivedAt: Date(timeIntervalSince1970: 3),
                message: LogMessage(type: "error", payload: "third")
            ),
        ]
        var cache = WorkbenchLogProjectionCache()

        cache.project(
            entries: entries,
            revision: 1,
            level: .all,
            query: "",
            language: .english
        )
        let previousRows = cache.allRows

        cache.project(
            entries: [entries[2], entries[0], entries[1]],
            revision: 2,
            level: .all,
            query: "",
            language: .english
        )

        #expect(cache.allRows.map(\.id) == ["third", "first", "second"])
        #expect(cache.formattedRowCount == 3)
        #expect(cache.reusedRowCount == 3)
        #expect(cache.fullProjectionCount == 1)
        #expect(cache.incrementalProjectionCount == 1)
        #expect(cache.reconciledSelection("second", previousRows: previousRows) == "second")

        cache.project(
            entries: [],
            revision: 3,
            level: .all,
            query: "",
            language: .english,
            isActive: false
        )
        #expect(cache.sourceProjectionCount == 2)
        #expect(cache.allRows.map(\.id) == ["third", "first", "second"])
    }

    @Test func followNewestCadenceCoalescesSteadyRequestsWithoutRestartingDeadline() {
        let start = Date(timeIntervalSince1970: 10_000)
        var cadence = WorkbenchLogFollowCadence()
        cadence.recordImmediateScroll(to: "initial", now: start)

        cadence.request(
            newestRowID: "first",
            isEnabled: true,
            hasSelection: false,
            now: start.addingTimeInterval(0.05)
        )
        let deadline = cadence.pendingDeadline
        cadence.request(
            newestRowID: "latest",
            isEnabled: true,
            hasSelection: false,
            now: start.addingTimeInterval(0.10)
        )

        #expect(deadline == start.addingTimeInterval(0.2))
        #expect(cadence.pendingDeadline == deadline)
        #expect(cadence.pendingNewestRowID == "latest")
        #expect(
            cadence.consume(
                isEnabled: true,
                hasSelection: false,
                now: start.addingTimeInterval(0.199)
            ) == nil
        )
        #expect(
            cadence.consume(
                isEnabled: true,
                hasSelection: false,
                now: start.addingTimeInterval(0.2)
            ) == "latest"
        )

        cadence.request(
            newestRowID: "blocked",
            isEnabled: true,
            hasSelection: true,
            now: start.addingTimeInterval(0.21)
        )
        #expect(cadence.pendingDeadline == nil)
        #expect(cadence.pendingNewestRowID == nil)
    }

    @Test func ambiguousDuplicateSelectionClearsInsteadOfSelectingAnotherRow() throws {
        let duplicate = ControllerLogEntry(
            id: "duplicate",
            receivedAt: Date(timeIntervalSince1970: 1),
            message: LogMessage(type: "info", payload: "same")
        )
        let previous = WorkbenchLogProjection.rows(from: [duplicate, duplicate])
        let next = WorkbenchLogProjection.rows(from: [duplicate])
        let selected = try #require(previous.first?.id)

        #expect(
            WorkbenchDataSelection.reconciled(
                selected,
                previousRows: previous,
                nextVisibleRows: next,
                identityFamily: \.identityFamily
            ) == nil
        )
    }

    @Test func connectionCloseGroupsPreserveFirstSeenOwnerOrder() {
        let connections = [
            Self.connection(
                id: "terminal-1",
                upload: 1,
                host: "a.example",
                destinationIP: "203.0.113.1",
                destinationPort: "443",
                process: "Terminal",
                processPath: "/Applications/Terminal.app"
            ),
            Self.connection(
                id: "browser-1",
                upload: 2,
                host: "b.example",
                destinationIP: "203.0.113.2",
                destinationPort: "443",
                process: "Browser",
                processPath: "/Applications/Browser.app"
            ),
            Self.connection(
                id: "terminal-2",
                upload: 3,
                host: "c.example",
                destinationIP: "203.0.113.3",
                destinationPort: "443",
                process: "Terminal",
                processPath: "/Applications/Terminal.app"
            ),
        ]

        let groups = WorkbenchConnectionProjection.closeGroups(
            from: WorkbenchConnectionProjection.rows(from: connections)
        )

        #expect(groups.map(\.id) == ["process:Terminal", "process:Browser"])
        #expect(groups.map(\.connections.count) == [2, 1])
        #expect(groups[0].connections.map(\.id) == ["terminal-1", "terminal-2"])
    }

    @Test func connectionCloseGroupsExcludeRowsWithoutControllerIDs() {
        let connections = [
            Self.connection(
                id: "  \n",
                upload: 1,
                host: "missing.example",
                destinationIP: "203.0.113.1",
                destinationPort: "443",
                process: "Terminal",
                processPath: "/Applications/Terminal.app"
            ),
            Self.connection(
                id: "closable-1",
                upload: 2,
                host: "visible.example",
                destinationIP: "203.0.113.2",
                destinationPort: "443",
                process: "Terminal",
                processPath: "/Applications/Terminal.app"
            ),
        ]

        let groups = WorkbenchConnectionProjection.closeGroups(
            from: WorkbenchConnectionProjection.rows(from: connections)
        )

        #expect(groups.count == 1)
        #expect(groups[0].connections.map(\.id) == ["closable-1"])
    }

    @Test func connectionCloseIntentsRejectReconnectedSessionWithUnchangedTargets() {
        let routerID = UUID()
        let generation = UUID()
        let reconnectedGeneration = UUID()
        let connectionIDs: Set<String> = ["connection-1"]
        let groupIDs: Set<String> = ["process:Terminal"]
        let intents = [
            WorkbenchConnectionCloseIntent(
                routerID: routerID,
                generation: generation,
                target: .connection("connection-1")
            ),
            WorkbenchConnectionCloseIntent(
                routerID: routerID,
                generation: generation,
                target: .group("process:Terminal")
            ),
        ]

        for intent in intents {
            #expect(
                intent.reconciled(
                    routerID: routerID,
                    generation: generation,
                    connectionIDs: connectionIDs,
                    groupIDs: groupIDs
                ) == intent
            )
            #expect(
                intent.reconciled(
                    routerID: routerID,
                    generation: reconnectedGeneration,
                    connectionIDs: connectionIDs,
                    groupIDs: groupIDs
                ) == nil
            )
        }
    }

    @Test func connectionCloseIntentReconciliationDropsMissingTargets() {
        let routerID = UUID()
        let generation = UUID()
        let connection = WorkbenchConnectionCloseIntent(
            routerID: routerID,
            generation: generation,
            target: .connection("connection-1")
        )
        let group = WorkbenchConnectionCloseIntent(
            routerID: routerID,
            generation: generation,
            target: .group("process:Terminal")
        )
        let all = WorkbenchConnectionCloseIntent(
            routerID: routerID,
            generation: generation,
            target: .all
        )

        #expect(
            connection.reconciled(
                routerID: routerID,
                generation: generation,
                connectionIDs: [],
                groupIDs: []
            ) == nil
        )
        #expect(
            group.reconciled(
                routerID: routerID,
                generation: generation,
                connectionIDs: ["connection-1"],
                groupIDs: []
            ) == nil
        )
        #expect(
            all.reconciled(
                routerID: routerID,
                generation: generation,
                connectionIDs: [],
                groupIDs: []
            ) == nil
        )
    }

    @Test func inspectorProjectionsExposeCompleteReportedValuesWithoutMasking() throws {
        let connection = ConnectionSnapshot(
            id: "connection-id",
            upload: 0,
            download: 1_024,
            uploadSpeed: 0,
            downloadSpeed: 2_048,
            start: "2026-07-29T12:00:00Z",
            chains: ["Policy", "Node"],
            providerChains: ["Provider A", "Provider B"],
            rule: "DOMAIN",
            rulePayload: "full.example",
            metadata: ConnectionMetadataSnapshot(
                host: "full.example",
                network: "tcp",
                type: "HTTPS",
                sourceIP: "192.0.2.10",
                destinationIP: "2001:db8::10",
                sourcePort: "54123",
                destinationPort: "443",
                process: "Browser",
                processPath: "/Applications/Browser.app/Contents/MacOS/Browser",
                inboundIP: "127.0.0.1",
                inboundPort: "7890",
                inboundName: "mixed-in",
                dnsMode: "fake-ip",
                sniffHost: "sniff.example",
                specialProxy: "special-proxy",
                specialRules: "special-rules",
                remoteDestination: "remote.example:443",
                connectionLogs: ["connected", "routed"],
                uid: 501,
                fields: [
                    "metadataCustom": .string("metadata-value"),
                    "nestedMetadata": .object([
                        "enabled": .bool(true),
                    ]),
                ]
            ),
            fields: [
                "connectionCustom": .string("connection-value"),
                "hops": .array([.string("one"), .string("two")]),
            ]
        )
        let closedAt = Date(timeIntervalSince1970: 1_000)
        let connectionRow = try #require(
            WorkbenchConnectionProjection.rows(
                from: [ClosedConnectionRecord(snapshot: connection, closedAt: closedAt)]
            ).first
        )
        let connectionValues = WorkbenchDataInspectorProjection.connectionIdentity(connectionRow)
            + WorkbenchDataInspectorProjection.connectionRouting(connectionRow)
            + WorkbenchDataInspectorProjection.connectionTransfer(
                connectionRow,
                language: .english
            )
            + WorkbenchDataInspectorProjection.connectionMetadata(connectionRow)

        #expect(connectionRow.connection == connection)
        #expect(connectionValues.map(\.id) == [
            "connection.id", "connection.host", "connection.process",
            "connection.process-path", "connection.network", "connection.type",
            "connection.source-address", "connection.destination-address",
            "connection.inbound-name", "connection.inbound-address", "connection.uid",
            "connection.rule", "connection.rule-payload", "connection.chains",
            "connection.provider-chains", "connection.dns-mode", "connection.sniff-host",
            "connection.remote-destination", "connection.special-proxy",
            "connection.special-rules", "connection.started-at", "connection.closed-at",
            "connection.upload", "connection.upload-speed", "connection.download",
            "connection.download-speed", "connection.logs",
        ])
        #expect(Self.inspectorValue("connection.source-address", in: connectionValues) == "192.0.2.10:54123")
        #expect(Self.inspectorValue("connection.destination-address", in: connectionValues) == "[2001:db8::10]:443")
        #expect(Self.inspectorValue("connection.upload", in: connectionValues) == "0 B")
        #expect(Self.inspectorValue("connection.upload-speed", in: connectionValues) == "0 B/s")
        #expect(connectionRow.metadataAdditionalFields.map(\.key) == [
            "metadataCustom", "nestedMetadata",
        ])
        #expect(connectionRow.metadataAdditionalFields.first?.value == .string("metadata-value"))
        #expect(connectionRow.metadataAdditionalFields.last?.value == .object([
            "enabled": .bool(true),
        ]))
        #expect(connectionRow.connectionAdditionalFields.map(\.key) == [
            "connectionCustom", "hops",
        ])
        #expect(connectionRow.connectionAdditionalFields.last?.value == .array([
            .string("one"), .string("two"),
        ]))

        let rule = RuleViewState(
            id: "rule-id",
            index: 7,
            type: "DOMAIN-SUFFIX",
            payload: "example.com",
            proxy: "Policy",
            size: 12,
            disabled: false,
            hitCount: 8,
            hitAt: "2026-07-29T12:01:00Z",
            missCount: 2,
            missAt: "2026-07-29T12:02:00Z",
            hasMutableExtra: true,
            extraMetadata: [
                "disabled": .bool(false),
                "customExtra": .string("extra-value"),
            ],
            metadata: ["customMetadata": .string("metadata-value")]
        )
        let ruleRow = try #require(
            WorkbenchRuleProjection.rows(
                from: [rule],
                connections: [connection],
                language: .english
            ).first
        )
        let ruleValues = WorkbenchDataInspectorProjection.ruleDefinition(ruleRow)
            + WorkbenchDataInspectorProjection.ruleStatistics(ruleRow)
            + WorkbenchDataInspectorProjection.ruleMetadata(ruleRow)

        #expect(ruleRow.rule == rule)
        #expect(ruleValues.map(\.id) == [
            "rule.id", "rule.payload", "rule.type", "rule.proxy", "rule.index",
            "rule.size", "rule.active-connections", "rule.hit-count", "rule.hit-at",
            "rule.miss-count", "rule.miss-at", "rule.hit-rate", "rule.extra-fields",
            "rule.metadata-fields",
        ])
        #expect(Self.inspectorValue("rule.extra-fields", in: ruleValues) == #"{"customExtra":"extra-value"}"#)
        #expect(Self.inspectorValue("rule.metadata-fields", in: ruleValues) == #"{"customMetadata":"metadata-value"}"#)

        let source = ProxyProviderViewState(
            kind: .proxy,
            name: "Provider A",
            type: "HTTP",
            behavior: "domain",
            format: "yaml",
            vehicleType: "HTTP",
            updatedAt: "2026-07-29T12:03:00Z",
            updatable: true,
            testURL: "https://probe.example/generate_204",
            healthCheck: .object(["enabled": .bool(true)]),
            subscriptionInfo: .object(["remaining": .number(4_096)]),
            itemCount: 42
        )
        let sourceRow = try #require(
            WorkbenchSourceProjection.rows(from: [source], language: .english).first
        )
        let sourceValues = WorkbenchDataInspectorProjection.sourceConfiguration(sourceRow)
            + WorkbenchDataInspectorProjection.sourceStatus(sourceRow)

        #expect(sourceRow.source == source)
        #expect(sourceValues.map(\.id) == [
            "source.id", "source.kind", "source.type", "source.vehicle",
            "source.behavior", "source.format", "source.test-url", "source.item-count",
            "source.updated-at", "source.health-check", "source.subscription-info",
        ])
        #expect(Self.inspectorValue("source.test-url", in: sourceValues) == "https://probe.example/generate_204")
        #expect(Self.inspectorValue("source.health-check", in: sourceValues) == #"{"enabled":true}"#)
        #expect(Self.inspectorValue("source.subscription-info", in: sourceValues) == #"{"remaining":4096}"#)

        let logEntry = ControllerLogEntry(
            id: "log-id",
            receivedAt: Date(timeIntervalSince1970: 2_000),
            message: LogMessage(
                type: "warning",
                payload: "full payload",
                time: "2026-07-29T12:04:00Z",
                level: "warn",
                message: "full message",
                fields: .object(["requestURL": .string("https://full.example/path")])
            )
        )
        let logRow = try #require(
            WorkbenchLogProjection.rows(from: [logEntry], language: .english).first
        )
        let logValues = WorkbenchDataInspectorProjection.logEvent(
            logRow,
            language: .english
        ) + WorkbenchDataInspectorProjection.logContent(logRow)

        #expect(logRow.entry == logEntry)
        #expect(logValues.map(\.id) == [
            "log.id", "log.received-at", "log.controller-time", "log.type",
            "log.level", "log.payload", "log.message", "log.structured-fields",
        ])
        #expect(Self.inspectorValue("log.payload", in: logValues) == "full payload")
        #expect(Self.inspectorValue("log.message", in: logValues) == "full message")
        #expect(Self.inspectorValue("log.structured-fields", in: logValues) == #"{"requestURL":"https:\/\/full.example\/path"}"#)
    }

    @Test func dataFormattingKeepsFullAddressesRoutesAndStructuredValues() {
        #expect(WorkbenchDataFormat.address("2001:db8::10", port: "443") == "[2001:db8::10]:443")
        #expect(WorkbenchDataFormat.address("controller.example", port: "9090") == "controller.example:9090")
        #expect(WorkbenchDataFormat.chain(["Proxy A", "", "DIRECT"]) == "Proxy A → DIRECT")
        #expect(
            WorkbenchDataFormat.json([
                "node": .string("Node A"),
                "weight": .number(2),
            ]) == #"{"node":"Node A","weight":2}"#
        )
        #expect(WorkbenchDataFormat.bytes(0) == "0 B")
        #expect(WorkbenchDataFormat.rate(0, language: .english) == "0 B/s")
        #expect(WorkbenchDataFormat.rate(0, language: .simplifiedChinese) == "0 B/s")
        #expect(WorkbenchDataFormat.reportedTimestamp(nil) == nil)
        #expect(WorkbenchDataFormat.reportedTimestamp("0001-01-01T00:00:00Z") == nil)
        #expect(WorkbenchDataFormat.reportedTimestamp("1970-01-01T00:00:00Z") == nil)
        #expect(
            WorkbenchDataFormat.reportedTimestamp("2026-07-29T12:00:00Z")
                == "2026-07-29T12:00:00Z"
        )
        #expect(WorkbenchDataRowGeometry.height == 40)
        #expect(WorkbenchDataRowGeometry.height > MicaTheme.Metrics.controlMinHeight)
    }

    private static func connection(
        id: String,
        upload: Int,
        host: String,
        destinationIP: String,
        destinationPort: String,
        process: String,
        processPath: String
    ) -> ConnectionSnapshot {
        ConnectionSnapshot(
            id: id,
            upload: upload,
            download: upload * 2,
            start: "2026-07-27T10:00:00Z",
            chains: ["Proxy", "DIRECT"],
            rule: "DOMAIN",
            rulePayload: host,
            metadata: ConnectionMetadataSnapshot(
                host: host,
                network: "tcp",
                type: "HTTPS",
                destinationIP: destinationIP,
                destinationPort: destinationPort,
                process: process,
                processPath: processPath
            )
        )
    }

    private static func inspectorValue(
        _ id: String,
        in values: [WorkbenchDataInspectorValue]
    ) -> String? {
        values.first(where: { $0.id == id })?.value
    }
}
