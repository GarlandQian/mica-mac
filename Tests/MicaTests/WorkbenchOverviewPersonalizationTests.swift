import Foundation
import Testing
@testable import Mica

struct WorkbenchOverviewPersonalizationTests {
    @Test func stableIdentifiersSizesAndContentChoicesAreComplete() {
        #expect(OverviewDashboardModuleID.allCases.map(\.rawValue) == [
            "instrumentRail",
            "telemetry",
            "operationalSummaries",
            "routeTopology",
            "networkInformation",
        ])
        #expect(Set(OverviewDashboardModuleID.allCases).count == 5)
        #expect(OverviewDashboardModuleID.instrumentRail.legalSizes == [.standard, .full])
        #expect(OverviewDashboardModuleID.telemetry.legalSizes == [.standard, .full])
        #expect(
            OverviewDashboardModuleID.operationalSummaries.legalSizes
                == [.compact, .standard, .full]
        )
        #expect(OverviewDashboardModuleID.routeTopology.legalSizes == [.full])
        #expect(OverviewDashboardModuleID.networkInformation.legalSizes == [.standard, .full])

        #expect(OverviewDashboardInstrumentMetricID.allCases.map(\.rawValue) == [
            "upload",
            "download",
            "activeConnections",
            "memoryUsage",
        ])
        #expect(OverviewDashboardTimelineWindow.allCases.map(\.rawValue) == [
            "oneMinute",
            "threeMinutes",
            "fiveMinutes",
        ])
        #expect(OverviewDashboardSummaryCategoryID.allCases.map(\.rawValue) == [
            "latency",
            "ruleHits",
            "activeConnections",
        ])
        #expect(OverviewDashboardSummaryItemCount.allCases.map(\.rawValue) == [1, 3, 5])
        #expect(OverviewDashboardNetworkGroupID.allCases.map(\.rawValue) == [
            "controllerIdentity",
            "runtimeAndFeatures",
            "listenerPorts",
        ])

        let defaultLayout = OverviewDashboardLayout.repositoryDefault
        #expect(defaultLayout.modules.map(\.id) == OverviewDashboardModuleID.allCases)
        #expect(defaultLayout.visibleModules.map(\.id) == [
            .telemetry,
            .routeTopology,
            .networkInformation,
        ])
        #expect(!defaultLayout.configuration(for: .instrumentRail).isVisible)
        #expect(!defaultLayout.configuration(for: .operationalSummaries).isVisible)
        #expect(
            defaultLayout.contentPreferences.instrumentMetrics.map(\.id)
                == OverviewDashboardInstrumentMetricID.allCases
        )
        #expect(
            defaultLayout.contentPreferences.summaryCategories.map(\.id)
                == OverviewDashboardSummaryCategoryID.allCases
        )
        #expect(
            defaultLayout.contentPreferences.summaryCategories.map(\.itemCount)
                == [.three, .three, .three]
        )
        #expect(
            defaultLayout.contentPreferences.networkGroups
                == OverviewDashboardNetworkGroupID.allCases
        )
    }

    @Test func typedNormalizationRepairsDuplicatesMissingSizesAndVisibility() {
        let layout = OverviewDashboardLayout(
            modules: [
                .init(id: .telemetry, size: .compact, isVisible: true),
                .init(id: .telemetry, size: .full, isVisible: false),
                .init(id: .operationalSummaries, size: .standard, isVisible: true),
            ],
            contentPreferences: OverviewDashboardContentPreferences(
                instrumentMetrics: [
                    .init(id: .download, isVisible: false),
                    .init(id: .download, isVisible: true),
                ],
                timelineWindow: .threeMinutes,
                summaryCategories: [
                    .init(id: .ruleHits, isVisible: false, itemCount: .five),
                    .init(id: .ruleHits, isVisible: true, itemCount: .one),
                ],
                networkGroups: [.listenerPorts, .listenerPorts]
            )
        )

        let normalized = layout.normalized()

        #expect(normalized.modules.map(\.id) == [
            .telemetry,
            .operationalSummaries,
            .instrumentRail,
            .routeTopology,
            .networkInformation,
        ])
        #expect(Set(normalized.modules.map(\.id)).count == 5)
        #expect(normalized.configuration(for: .telemetry).size == .full)
        #expect(normalized.configuration(for: .instrumentRail).isVisible == false)
        #expect(
            normalized.contentPreferences.instrumentMetrics.map(\.id) == [
                .download,
                .upload,
                .activeConnections,
                .memoryUsage,
            ]
        )
        #expect(
            normalized.contentPreferences.instrumentMetrics.filter(\.isVisible).map(\.id)
                == [.download]
        )
        #expect(
            normalized.contentPreferences.summaryCategories.map(\.id) == [
                .ruleHits,
                .latency,
                .activeConnections,
            ]
        )
        #expect(
            normalized.contentPreferences.summaryCategories.filter(\.isVisible).map(\.id)
                == [.ruleHits]
        )
        #expect(
            normalized.contentPreferences.summaryCategories[0].itemCount == .five
        )
        #expect(normalized.contentPreferences.networkGroups == [
            .listenerPorts,
            .controllerIdentity,
            .runtimeAndFeatures,
        ])

        let allHidden = OverviewDashboardLayout(
            modules: OverviewDashboardModuleID.allCases.map {
                .init(id: $0, isVisible: false)
            }
        )
        #expect(allHidden.normalized() == .repositoryDefault)
    }

    @Test func hiddenSummaryMayRetainNoCategoryUntilItBecomesVisible() {
        let hiddenSummary = OverviewDashboardLayout(
            modules: [
                .init(id: .instrumentRail, isVisible: true),
                .init(id: .operationalSummaries, isVisible: false),
            ],
            contentPreferences: OverviewDashboardContentPreferences(
                summaryCategories: OverviewDashboardSummaryCategoryID.allCases.map {
                    .init(id: $0, isVisible: false)
                }
            )
        )
        let normalizedHidden = hiddenSummary.normalized()
        #expect(
            normalizedHidden.contentPreferences.summaryCategories.allSatisfy {
                !$0.isVisible
            }
        )

        var visibleSummary = normalizedHidden
        let summaryIndex = visibleSummary.modules.firstIndex {
            $0.id == .operationalSummaries
        }
        #expect(summaryIndex != nil)
        if let summaryIndex {
            visibleSummary.modules[summaryIndex].isVisible = true
        }
        let normalizedVisible = visibleSummary.normalized()
        #expect(
            normalizedVisible.contentPreferences.summaryCategories.filter(\.isVisible).count
                == 1
        )
    }

    @Test func presetsReplaceOnlyOrderVisibilityAndLegalSize() {
        let content = OverviewDashboardContentPreferences(
            instrumentMetrics: [
                .init(id: .memoryUsage, isVisible: true),
                .init(id: .upload, isVisible: false),
                .init(id: .download, isVisible: true),
                .init(id: .activeConnections, isVisible: false),
            ],
            timelineWindow: .oneMinute,
            summaryCategories: [
                .init(id: .activeConnections, isVisible: true, itemCount: .one),
                .init(id: .latency, isVisible: false, itemCount: .five),
                .init(id: .ruleHits, isVisible: true, itemCount: .three),
            ],
            networkGroups: [.listenerPorts, .runtimeAndFeatures, .controllerIdentity]
        )
        let original = OverviewDashboardLayout(
            modules: OverviewDashboardLayout.repositoryDefault.modules,
            contentPreferences: content
        )

        for preset in OverviewDashboardPreset.allCases {
            let applied = preset.applying(to: original)
            #expect(applied.contentPreferences == content)
            #expect(applied.modules.count == 5)
            #expect(Set(applied.modules.map(\.id)).count == 5)
            #expect(applied.modules.allSatisfy { $0.id.legalSizes.contains($0.size) })
        }

        #expect(
            OverviewDashboardPreset.routeAnalysis
                .applying(to: original)
                .modules
                .map(\.id) == [
                    .instrumentRail,
                    .routeTopology,
                    .operationalSummaries,
                    .telemetry,
                    .networkInformation,
                ]
        )
        let lightweight = OverviewDashboardPreset.lightweightMonitoring.applying(to: original)
        #expect(lightweight.visibleModules.map(\.id) == [
            .instrumentRail,
            .telemetry,
            .operationalSummaries,
        ])
    }

    @Test func rowPackerIsPureSequentialAcrossTwelveSixAndOneColumns() {
        let layout = OverviewDashboardLayout(
            modules: [
                .init(id: .instrumentRail, size: .standard),
                .init(id: .operationalSummaries, size: .compact),
                .init(id: .telemetry, size: .standard),
                .init(id: .routeTopology, size: .standard),
                .init(id: .networkInformation, size: .standard),
            ]
        )

        let wide = OverviewDashboardRowPacker.rows(for: layout, widthMode: .wide)
        #expect(wide.map { $0.modules.map(\.id) } == [
            [.instrumentRail, .operationalSummaries],
            [.telemetry],
            [.routeTopology],
            [.networkInformation],
        ])
        #expect(wide.map { $0.modules.map(\.columnSpan) } == [
            [6, 4],
            [6],
            [12],
            [6],
        ])

        let medium = OverviewDashboardRowPacker.rows(for: layout, widthMode: .medium)
        #expect(medium.map { $0.modules.map(\.id) } == [
            [.instrumentRail],
            [.operationalSummaries],
            [.telemetry],
            [.routeTopology],
            [.networkInformation],
        ])
        #expect(medium.map { $0.modules.map(\.columnSpan) } == [
            [6],
            [3],
            [6],
            [6],
            [6],
        ])

        let narrow = OverviewDashboardRowPacker.rows(for: layout, widthMode: .narrow)
        #expect(narrow.map { $0.modules.map(\.id) } == [
            [.instrumentRail],
            [.operationalSummaries],
            [.telemetry],
            [.routeTopology],
            [.networkInformation],
        ])
        #expect(narrow.allSatisfy { $0.modules.single?.columnSpan == 1 })
    }

    @MainActor
    @Test func rawPersistenceNormalizationToleratesUnknownDuplicateAndCorruptRecords() {
        let overrideID = UUID()
        let invalidOverrideID = UUID()
        let json = """
        {
          "version": 1,
          "persistenceRevision": 8,
          "globalRevision": 3,
          "globalDefault": {
            "modules": [
              {"id": "futureModule", "size": "full", "isVisible": true},
              {"id": "telemetry", "size": "compact", "isVisible": true},
              {"id": "telemetry", "size": "full", "isVisible": false},
              {"id": "operationalSummaries", "size": "compact", "isVisible": true}
            ],
            "instrumentMetrics": [
              12,
              {"id": "upload", "isVisible": false},
              {"id": "upload", "isVisible": true},
              {"id": "futureMetric", "isVisible": true}
            ],
            "timelineWindow": "futureWindow",
            "summaryCategories": [
              {"id": "latency", "isVisible": false, "itemCount": 2},
              {"id": "ruleHits", "isVisible": false, "itemCount": 5},
              {"id": "futureCategory", "isVisible": true, "itemCount": 1}
            ],
            "networkGroups": [
              "listenerPorts",
              10,
              "listenerPorts",
              "futureGroup"
            ]
          },
          "controllerOverrides": [
            42,
            {
              "controllerID": "\(invalidOverrideID.uuidString)",
              "revision": 6,
              "layout": {
                "modules": [
                  {"id": "instrumentRail", "size": "full", "isVisible": false}
                ],
                "instrumentMetrics": [],
                "timelineWindow": "fiveMinutes",
                "summaryCategories": [],
                "networkGroups": []
              }
            },
            {
              "controllerID": "\(overrideID.uuidString)",
              "revision": 7,
              "layout": {
                "modules": [
                  false,
                  {"id": "routeTopology", "size": "standard", "isVisible": true},
                  {"id": "routeTopology", "size": "full", "isVisible": false}
                ],
                "instrumentMetrics": [],
                "timelineWindow": "threeMinutes",
                "summaryCategories": [],
                "networkGroups": []
              }
            }
          ]
        }
        """
        let data = Data(json.utf8)
        let store = OverviewDashboardLayoutStore(
            persistence: OverviewDashboardPersistenceClient(
                loadData: { data },
                saveData: { _ in }
            )
        )

        let global = store.globalDefaultLayout
        #expect(global.modules.map(\.id) == [
            .telemetry,
            .operationalSummaries,
            .instrumentRail,
            .routeTopology,
            .networkInformation,
        ])
        #expect(global.configuration(for: .telemetry).size == .full)
        #expect(global.contentPreferences.timelineWindow == .fiveMinutes)
        #expect(
            global.contentPreferences.instrumentMetrics.filter(\.isVisible).map(\.id)
                == [.upload]
        )
        #expect(
            global.contentPreferences.summaryCategories.filter(\.isVisible).map(\.id)
                == [.latency]
        )
        #expect(global.contentPreferences.summaryCategories[0].itemCount == .three)
        #expect(global.contentPreferences.summaryCategories[1].itemCount == .five)
        #expect(global.contentPreferences.networkGroups == [
            .listenerPorts,
            .controllerIdentity,
            .runtimeAndFeatures,
        ])

        let override = store.effectiveSnapshot(for: overrideID)
        #expect(override.revisionToken.source == .controllerOverride)
        #expect(override.layout.visibleModules.map(\.id) == [.routeTopology])
        #expect(override.layout.configuration(for: .routeTopology).size == .full)
        #expect(
            override.layout.contentPreferences.instrumentMetrics.filter(\.isVisible).count
                == 1
        )

        let invalidOverride = store.effectiveSnapshot(for: invalidOverrideID)
        #expect(invalidOverride.revisionToken.source == .globalDefault)
        #expect(invalidOverride.layout == global)
    }

    @MainActor
    @Test func corruptOrFutureEnvelopeFallsBackToRepositoryDefault() {
        let corruptData = Data("{not-json".utf8)
        let corruptStore = OverviewDashboardLayoutStore(
            persistence: OverviewDashboardPersistenceClient(
                loadData: { corruptData },
                saveData: { _ in }
            )
        )
        #expect(corruptStore.globalDefaultLayout == .repositoryDefault)

        let futureData = Data(
            """
            {
              "version": 99,
              "persistenceRevision": 4,
              "globalRevision": 4,
              "globalDefault": null,
              "controllerOverrides": []
            }
            """.utf8
        )
        let futureStore = OverviewDashboardLayoutStore(
            persistence: OverviewDashboardPersistenceClient(
                loadData: { futureData },
                saveData: { _ in }
            )
        )
        #expect(futureStore.globalDefaultLayout == .repositoryDefault)
    }

    @MainActor
    @Test func globalAndControllerLayoutsRoundTripWithoutBusinessData() async throws {
        let fixture = PersonalizationDefaultsFixture()
        defer { fixture.clear() }
        let store = OverviewDashboardLayoutStore(
            defaults: fixture.defaults,
            persistenceKey: fixture.key
        )
        let firstControllerID = UUID()
        let secondControllerID = UUID()

        var globalLayout = OverviewDashboardPreset.lightweightMonitoring.applying(
            to: .repositoryDefault
        )
        globalLayout.contentPreferences.timelineWindow = .oneMinute
        globalLayout = globalLayout.normalized()
        _ = try await store.commit(
            globalLayout,
            for: firstControllerID,
            expected: store.editSnapshot(for: firstControllerID).token,
            mode: .globalDefault
        )

        var overrideLayout = OverviewDashboardPreset.routeAnalysis.applying(to: globalLayout)
        overrideLayout.contentPreferences.networkGroups = [
            .listenerPorts,
            .controllerIdentity,
            .runtimeAndFeatures,
        ]
        overrideLayout = overrideLayout.normalized()
        _ = try await store.commit(
            overrideLayout,
            for: secondControllerID,
            expected: store.editSnapshot(for: secondControllerID).token
        )

        let restored = OverviewDashboardLayoutStore(
            defaults: fixture.defaults,
            persistenceKey: fixture.key
        )
        #expect(restored.globalDefaultLayout == globalLayout)
        #expect(restored.effectiveSnapshot(for: firstControllerID).layout == globalLayout)
        #expect(
            restored.effectiveSnapshot(for: firstControllerID).revisionToken.source
                == .globalDefault
        )
        #expect(restored.effectiveSnapshot(for: secondControllerID).layout == overrideLayout)
        #expect(
            restored.effectiveSnapshot(for: secondControllerID).revisionToken.source
                == .controllerOverride
        )

        let data = try #require(fixture.defaults.data(forKey: fixture.key))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains(firstControllerID.uuidString) == false)
        #expect(json.contains(secondControllerID.uuidString))
        #expect(!json.contains("displayName"))
        #expect(!json.contains("endpoint"))
        #expect(!json.contains("host"))
        #expect(!json.contains("port"))
        #expect(!json.contains("secret"))
        #expect(!json.contains("token"))
    }

    @MainActor
    @Test func effectiveStateObjectsInvalidateOnlyWhenTheirLayoutSourceChanges() async throws {
        let fixture = PersonalizationDefaultsFixture()
        defer { fixture.clear() }
        let store = OverviewDashboardLayoutStore(
            defaults: fixture.defaults,
            persistenceKey: fixture.key
        )
        let firstControllerID = UUID()
        let secondControllerID = UUID()
        let firstState = store.effectiveState(for: firstControllerID)
        let secondState = store.effectiveState(for: secondControllerID)
        let secondBeforeOverride = secondState.snapshot

        let firstOverride = OverviewDashboardPreset.routeAnalysis.applying(
            to: .repositoryDefault
        )
        _ = try await store.commit(
            firstOverride,
            for: firstControllerID,
            expected: store.editSnapshot(for: firstControllerID).token
        )

        #expect(store.effectiveState(for: firstControllerID) === firstState)
        #expect(firstState.layout == firstOverride)
        #expect(firstState.revisionToken.source == .controllerOverride)
        #expect(secondState.snapshot == secondBeforeOverride)

        let firstBeforeGlobalChange = firstState.snapshot
        let nextGlobal = OverviewDashboardPreset.lightweightMonitoring.applying(
            to: .repositoryDefault
        )
        _ = try await store.commit(
            nextGlobal,
            for: secondControllerID,
            expected: store.editSnapshot(for: secondControllerID).token,
            mode: .globalDefault
        )

        #expect(firstState.snapshot == firstBeforeGlobalChange)
        #expect(secondState.layout == nextGlobal)
        #expect(secondState.revisionToken.source == .globalDefault)

        _ = try await store.commit(
            nextGlobal,
            for: firstControllerID,
            expected: store.editSnapshot(for: firstControllerID).token
        )
        #expect(firstState.layout == nextGlobal)
        #expect(firstState.revisionToken.source == .globalDefault)
    }

    @MainActor
    @Test func concurrentDifferentControllerCommitsMergeTheLatestEnvelope() async throws {
        let fixture = PersonalizationDefaultsFixture()
        defer { fixture.clear() }
        let store = OverviewDashboardLayoutStore(
            defaults: fixture.defaults,
            persistenceKey: fixture.key
        )
        let firstControllerID = UUID()
        let secondControllerID = UUID()
        let firstLayout = OverviewDashboardPreset.routeAnalysis.applying(
            to: .repositoryDefault
        )
        let secondLayout = OverviewDashboardPreset.lightweightMonitoring.applying(
            to: .repositoryDefault
        )
        let firstToken = store.editSnapshot(for: firstControllerID).token
        let secondToken = store.editSnapshot(for: secondControllerID).token

        async let firstCommit: OverviewDashboardEditSnapshot = store.commit(
            firstLayout,
            for: firstControllerID,
            expected: firstToken
        )
        async let secondCommit: OverviewDashboardEditSnapshot = store.commit(
            secondLayout,
            for: secondControllerID,
            expected: secondToken
        )
        _ = try await (firstCommit, secondCommit)

        let restored = OverviewDashboardLayoutStore(
            defaults: fixture.defaults,
            persistenceKey: fixture.key
        )
        #expect(restored.effectiveSnapshot(for: firstControllerID).layout == firstLayout)
        #expect(restored.effectiveSnapshot(for: secondControllerID).layout == secondLayout)

        let data = try #require(fixture.defaults.data(forKey: fixture.key))
        let envelope = try JSONDecoder().decode(
            OverviewDashboardPersistenceEnvelope.self,
            from: data
        )
        #expect(envelope.controllerOverrides.compactMap(\.controllerID) == [
            firstControllerID.uuidString,
            secondControllerID.uuidString,
        ].sorted())
    }

    @MainActor
    @Test func sameControllerStaleCommitReportsConflict() async throws {
        let fixture = PersonalizationDefaultsFixture()
        defer { fixture.clear() }
        let store = OverviewDashboardLayoutStore(
            defaults: fixture.defaults,
            persistenceKey: fixture.key
        )
        let controllerID = UUID()
        let staleToken = store.editSnapshot(for: controllerID).token
        let firstLayout = OverviewDashboardPreset.routeAnalysis.applying(
            to: .repositoryDefault
        )
        let secondLayout = OverviewDashboardPreset.lightweightMonitoring.applying(
            to: .repositoryDefault
        )

        _ = try await store.commit(
            firstLayout,
            for: controllerID,
            expected: staleToken
        )

        do {
            _ = try await store.commit(
                secondLayout,
                for: controllerID,
                expected: staleToken
            )
            Issue.record("Expected stale Overview commit to conflict.")
        } catch let error as OverviewDashboardLayoutStoreError {
            guard case .conflict(let current) = error else {
                Issue.record("Expected a conflict, got \(error).")
                return
            }
            #expect(current.layout == firstLayout)
            #expect(current.token.effective.source == .controllerOverride)
        }
        #expect(store.effectiveSnapshot(for: controllerID).layout == firstLayout)
    }

    @MainActor
    @Test func staleGlobalCommitCannotDeleteNewerControllerOverride() async throws {
        let fixture = PersonalizationDefaultsFixture()
        defer { fixture.clear() }
        let store = OverviewDashboardLayoutStore(
            defaults: fixture.defaults,
            persistenceKey: fixture.key
        )
        let controllerID = UUID()
        let initialOverride = OverviewDashboardPreset.routeAnalysis.applying(
            to: .repositoryDefault
        )
        _ = try await store.commit(
            initialOverride,
            for: controllerID,
            expected: store.editSnapshot(for: controllerID).token
        )
        let staleToken = store.editSnapshot(for: controllerID).token
        let newerOverride = OverviewDashboardPreset.lightweightMonitoring.applying(
            to: .repositoryDefault
        )
        _ = try await store.commit(
            newerOverride,
            for: controllerID,
            expected: staleToken
        )

        do {
            _ = try await store.commit(
                initialOverride,
                for: controllerID,
                expected: staleToken,
                mode: .globalDefault
            )
            Issue.record("Expected stale global commit to conflict.")
        } catch let error as OverviewDashboardLayoutStoreError {
            guard case .conflict = error else {
                Issue.record("Expected a conflict, got \(error).")
                return
            }
        }

        #expect(store.globalDefaultLayout == .repositoryDefault)
        #expect(store.effectiveSnapshot(for: controllerID).layout == newerOverride)
        #expect(
            store.effectiveSnapshot(for: controllerID).revisionToken.source
                == .controllerOverride
        )
    }

    @MainActor
    @Test func failedPersistenceDoesNotPublishCommittedState() async {
        let store = OverviewDashboardLayoutStore(
            persistence: OverviewDashboardPersistenceClient(
                loadData: { nil },
                saveData: { _ in throw PersonalizationPersistenceFailure() }
            )
        )
        let controllerID = UUID()
        let before = store.effectiveSnapshot(for: controllerID)
        let layout = OverviewDashboardPreset.routeAnalysis.applying(to: before.layout)

        do {
            _ = try await store.commit(
                layout,
                for: controllerID,
                expected: store.editSnapshot(for: controllerID).token
            )
            Issue.record("Expected persistence to fail.")
        } catch {
            #expect(error as? OverviewDashboardLayoutStoreError == .persistenceFailed)
        }

        #expect(store.effectiveSnapshot(for: controllerID) == before)
    }

    @MainActor
    @Test func coordinatorCancelAndUndoNeverWriteCommittedState() {
        let fixture = PersonalizationDefaultsFixture()
        defer { fixture.clear() }
        let store = OverviewDashboardLayoutStore(
            defaults: fixture.defaults,
            persistenceKey: fixture.key
        )
        let coordinator = OverviewDashboardWindowCoordinator(layoutStore: store)
        let controllerID = UUID()
        let undoManager = UndoManager()

        coordinator.beginEditing(
            controllerID: controllerID,
            undoManager: undoManager
        )
        let original = coordinator.draft
        coordinator.applyPreset(.lightweightMonitoring, actionName: "Preset")
        #expect(coordinator.hasDirtyDraft)
        #expect(undoManager.canUndo)
        #expect(fixture.defaults.data(forKey: fixture.key) == nil)

        undoManager.undo()
        #expect(coordinator.draft == original)
        #expect(!coordinator.hasDirtyDraft)
        #expect(undoManager.canRedo)

        undoManager.redo()
        #expect(
            coordinator.draft?.visibleModules.map(\.id) == [
                .instrumentRail,
                .telemetry,
                .operationalSummaries,
            ]
        )
        coordinator.cancel()

        #expect(!coordinator.isEditing)
        #expect(fixture.defaults.data(forKey: fixture.key) == nil)
        #expect(store.effectiveSnapshot(for: controllerID).layout == .repositoryDefault)
    }

    @MainActor
    @Test func coordinatorDoneResetAndSetDefaultArePersistenceFirstTransactions() async throws {
        let fixture = PersonalizationDefaultsFixture()
        defer { fixture.clear() }
        let store = OverviewDashboardLayoutStore(
            defaults: fixture.defaults,
            persistenceKey: fixture.key
        )
        let coordinator = OverviewDashboardWindowCoordinator(layoutStore: store)
        let controllerID = UUID()
        let override = OverviewDashboardPreset.routeAnalysis.applying(
            to: .repositoryDefault
        )

        coordinator.beginEditing(controllerID: controllerID)
        coordinator.applyPreset(.routeAnalysis)
        #expect(fixture.defaults.data(forKey: fixture.key) == nil)
        #expect(await coordinator.done())
        #expect(
            store.effectiveSnapshot(for: controllerID).revisionToken.source
                == .controllerOverride
        )
        #expect(store.effectiveSnapshot(for: controllerID).layout == override)
        #expect(fixture.defaults.data(forKey: fixture.key) != nil)

        coordinator.beginEditing(controllerID: controllerID)
        coordinator.resetCurrentController()
        #expect(await coordinator.done())
        #expect(
            store.effectiveSnapshot(for: controllerID).revisionToken.source
                == .globalDefault
        )
        #expect(store.effectiveSnapshot(for: controllerID).layout == .repositoryDefault)

        coordinator.beginEditing(controllerID: controllerID)
        coordinator.applyPreset(.lightweightMonitoring)
        coordinator.setAsGlobalDefault(true)
        let defaultDraft = try #require(coordinator.draft)
        #expect(await coordinator.done())
        #expect(store.globalDefaultLayout == defaultDraft)
        #expect(store.effectiveSnapshot(for: controllerID).layout == defaultDraft)
        #expect(
            store.effectiveSnapshot(for: controllerID).revisionToken.source
                == .globalDefault
        )
    }

    @MainActor
    @Test func resetKeepsInheritanceWhenGlobalDefaultChangesBeforeCommit() async throws {
        let fixture = PersonalizationDefaultsFixture()
        defer { fixture.clear() }
        let store = OverviewDashboardLayoutStore(
            defaults: fixture.defaults,
            persistenceKey: fixture.key
        )
        let controllerID = UUID()
        let otherControllerID = UUID()
        let controllerOverride = OverviewDashboardPreset.routeAnalysis.applying(
            to: .repositoryDefault
        )
        _ = try await store.commit(
            controllerOverride,
            for: controllerID,
            expected: store.editSnapshot(for: controllerID).token
        )

        let editor = OverviewDashboardWindowCoordinator(layoutStore: store)
        editor.beginEditing(controllerID: controllerID)
        editor.resetCurrentController()
        #expect(editor.resetsControllerOverride)

        let nextGlobal = OverviewDashboardPreset.lightweightMonitoring.applying(
            to: .repositoryDefault
        )
        _ = try await store.commit(
            nextGlobal,
            for: otherControllerID,
            expected: store.editSnapshot(for: otherControllerID).token,
            mode: .globalDefault
        )
        editor.reconcile(
            selectedControllerID: controllerID,
            targetControllerExists: true
        )

        #expect(editor.conflict == nil)
        #expect(editor.draft == nextGlobal)
        #expect(await editor.done())
        #expect(store.effectiveSnapshot(for: controllerID).layout == nextGlobal)
        #expect(
            store.effectiveSnapshot(for: controllerID).revisionToken.source
                == .globalDefault
        )
    }

    @MainActor
    @Test func coordinatorKeepsDraftAcrossConflictAndRequiresExplicitResolution() async {
        let fixture = PersonalizationDefaultsFixture()
        defer { fixture.clear() }
        let store = OverviewDashboardLayoutStore(
            defaults: fixture.defaults,
            persistenceKey: fixture.key
        )
        let controllerID = UUID()
        let first = OverviewDashboardWindowCoordinator(layoutStore: store)
        let second = OverviewDashboardWindowCoordinator(layoutStore: store)

        first.beginEditing(controllerID: controllerID)
        second.beginEditing(controllerID: controllerID)
        second.applyPreset(.lightweightMonitoring)
        let secondDraft = second.draft

        first.applyPreset(.routeAnalysis)
        #expect(await first.done())

        second.reconcile(
            selectedControllerID: controllerID,
            targetControllerExists: true
        )
        #expect(second.conflict?.kind == .committedLayoutChanged)
        #expect(second.draft == secondDraft)
        #expect(!(await second.done()))
        #expect(second.lastCommitFailure == .conflict)
        #expect(second.isEditing)

        #expect(await second.keepMineAndCommit())
        #expect(!second.isEditing)
        #expect(store.effectiveSnapshot(for: controllerID).layout == secondDraft)
    }

    @MainActor
    @Test func coordinatorReloadsConflictAndCanPromoteUnavailableTargetDraft() async throws {
        let fixture = PersonalizationDefaultsFixture()
        defer { fixture.clear() }
        let store = OverviewDashboardLayoutStore(
            defaults: fixture.defaults,
            persistenceKey: fixture.key
        )
        let controllerID = UUID()
        let editor = OverviewDashboardWindowCoordinator(layoutStore: store)
        let external = OverviewDashboardWindowCoordinator(layoutStore: store)

        editor.beginEditing(controllerID: controllerID)
        external.beginEditing(controllerID: controllerID)
        external.applyPreset(.routeAnalysis)
        #expect(await external.done())

        editor.reconcile(
            selectedControllerID: controllerID,
            targetControllerExists: true
        )
        #expect(editor.conflict?.kind == .committedLayoutChanged)
        editor.reloadFromCommitted()
        #expect(editor.draft == store.effectiveSnapshot(for: controllerID).layout)
        #expect(!editor.hasDirtyDraft)
        #expect(editor.conflict == nil)

        editor.applyPreset(.lightweightMonitoring)
        let retainedDraft = try #require(editor.draft)
        try await store.removeController(controllerID)
        editor.reconcile(
            selectedControllerID: nil,
            targetControllerExists: false
        )
        #expect(editor.conflict?.kind == .targetControllerUnavailable)
        #expect(!(await editor.done()))
        #expect(editor.lastCommitFailure == .targetControllerUnavailable)
        #expect(editor.draft == retainedDraft)

        editor.setAsGlobalDefault(true)
        #expect(await editor.keepMineAndCommit())
        #expect(store.globalDefaultLayout == retainedDraft)
        #expect(!editor.isEditing)
    }

    @MainActor
    @Test func selectedControllerConflictCannotBeClearedByReload() {
        let store = OverviewDashboardLayoutStore(
            persistence: OverviewDashboardPersistenceClient(
                loadData: { nil },
                saveData: { _ in }
            )
        )
        let controllerID = UUID()
        let editor = OverviewDashboardWindowCoordinator(layoutStore: store)
        editor.beginEditing(controllerID: controllerID)
        editor.applyPreset(.routeAnalysis)
        let retainedDraft = editor.draft

        editor.reconcile(
            selectedControllerID: UUID(),
            targetControllerExists: true
        )
        #expect(editor.conflict?.kind == .selectedControllerChanged)
        editor.reloadFromCommitted()

        #expect(editor.conflict?.kind == .selectedControllerChanged)
        #expect(editor.draft == retainedDraft)
        #expect(editor.hasDirtyDraft)
    }

    @MainActor
    @Test func undoReconcilesConflictAfterDefaultIntentIsRemoved() async throws {
        let fixture = PersonalizationDefaultsFixture()
        defer { fixture.clear() }
        let store = OverviewDashboardLayoutStore(
            defaults: fixture.defaults,
            persistenceKey: fixture.key
        )
        let controllerID = UUID()
        let otherControllerID = UUID()
        _ = try await store.commit(
            OverviewDashboardPreset.routeAnalysis.applying(to: .repositoryDefault),
            for: controllerID,
            expected: store.editSnapshot(for: controllerID).token
        )

        let undoManager = UndoManager()
        let editor = OverviewDashboardWindowCoordinator(layoutStore: store)
        editor.beginEditing(
            controllerID: controllerID,
            undoManager: undoManager
        )
        editor.setAsGlobalDefault(true, actionName: "Set Default")
        _ = try await store.commit(
            OverviewDashboardPreset.lightweightMonitoring.applying(
                to: .repositoryDefault
            ),
            for: otherControllerID,
            expected: store.editSnapshot(for: otherControllerID).token,
            mode: .globalDefault
        )
        editor.reconcile(
            selectedControllerID: controllerID,
            targetControllerExists: true
        )
        #expect(editor.conflict?.kind == .committedLayoutChanged)

        undoManager.undo()

        #expect(!editor.setsGlobalDefault)
        #expect(editor.conflict == nil)
    }

    @MainActor
    @Test func coordinatorRetainsDraftWhenPersistenceFails() async {
        let store = OverviewDashboardLayoutStore(
            persistence: OverviewDashboardPersistenceClient(
                loadData: { nil },
                saveData: { _ in throw PersonalizationPersistenceFailure() }
            )
        )
        let coordinator = OverviewDashboardWindowCoordinator(layoutStore: store)
        let controllerID = UUID()
        coordinator.beginEditing(controllerID: controllerID)
        coordinator.applyPreset(.routeAnalysis)
        let draft = coordinator.draft

        #expect(!(await coordinator.done()))
        #expect(coordinator.isEditing)
        #expect(coordinator.hasDirtyDraft)
        #expect(coordinator.draft == draft)
        #expect(coordinator.lastCommitFailure == .persistence)
        #expect(store.effectiveSnapshot(for: controllerID).layout == .repositoryDefault)
    }

    @MainActor
    @Test func windowCoordinatorOwnsStableDemandAndModuleRuntimes() {
        let store = OverviewDashboardLayoutStore(
            persistence: OverviewDashboardPersistenceClient(
                loadData: { nil },
                saveData: { _ in }
            )
        )
        let firstWindow = OverviewDashboardWindowCoordinator(layoutStore: store)
        let secondWindow = OverviewDashboardWindowCoordinator(layoutStore: store)
        let controllerID = UUID()
        let generation = UUID()

        #expect(
            firstWindow.liveSessionWindowDemandID
                != secondWindow.liveSessionWindowDemandID
        )

        let firstTelemetry = firstWindow.runtimeRegistry.telemetryRuntime(
            controllerID: controllerID,
            generation: generation,
            preferredWindow: .fiveMinutes
        )
        let reusedTelemetry = firstWindow.runtimeRegistry.telemetryRuntime(
            controllerID: controllerID,
            generation: generation,
            preferredWindow: .oneMinute
        )
        let firstTopology = firstWindow.runtimeRegistry.topologyRuntime(
            controllerID: controllerID,
            generation: generation
        )
        let reusedTopology = firstWindow.runtimeRegistry.topologyRuntime(
            controllerID: controllerID,
            generation: generation
        )

        #expect(firstTelemetry === reusedTelemetry)
        #expect(firstTopology === reusedTopology)

        let replacementGeneration = UUID()
        let replacementTelemetry = firstWindow.runtimeRegistry.telemetryRuntime(
            controllerID: controllerID,
            generation: replacementGeneration,
            preferredWindow: .threeMinutes
        )
        let replacementTopology = firstWindow.runtimeRegistry.topologyRuntime(
            controllerID: controllerID,
            generation: replacementGeneration
        )

        #expect(firstTelemetry !== replacementTelemetry)
        #expect(firstTopology !== replacementTopology)
    }
}

private struct PersonalizationPersistenceFailure: Error {}

private final class PersonalizationDefaultsFixture {
    let suiteName: String
    let defaults: UserDefaults
    let key = "overview-layout"

    init() {
        suiteName = "MicaTests.OverviewPersonalization.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    func clear() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private extension Collection {
    var single: Element? {
        count == 1 ? first : nil
    }
}
