import Foundation
import MicaCore
import Observation
import SwiftUI

struct WorkbenchWorkspaceSort: Codable, Equatable, Sendable {
    var field: String
    var ascending: Bool
}

struct WorkbenchConnectionNavigationSelection: Equatable, Sendable {
    let controllerID: RouterProfile.ID
    let generation: UUID
    let connectionID: String
}

struct WorkbenchRuleNavigationSelection: Equatable, Sendable {
    let controllerID: RouterProfile.ID
    let generation: UUID
    let type: String
    let payload: String
}

/// Typed selection shown in the workspace inspector (design.md §3). Surfaces
/// populate this in redesign Phases 3-6; the workspace store owns it so
/// inspector selection never touches AppModel or live-session state. Values
/// are window-level and session-bound: they clear with the session via
/// `clearSessionBoundState(controllerID:)` and are never persisted.
enum WorkbenchInspectorSelection: Equatable, Sendable {
    case none
    case proxyGroup(groupName: String)
    case proxyNode(groupName: String, nodeName: String)
    case connection(id: String)
    case rule(type: String, payload: String)
    case log(id: String)
    case source(id: String)
    case controller(id: RouterProfile.ID)
}

struct WorkbenchDestinationWorkspace: Equatable, Sendable {
    var searchText: String
    var filters: [String: String]
    var sort: [WorkbenchWorkspaceSort]
    var selectedItemID: String?
    var scrollAnchorID: String?
    var activeTab: String?
    var openGroupIDs: [String]
    var activeGroupID: String?
    var groupFilters: [String: String]
    var selectedGroupMemberIDs: [String: String]
    var pendingConnectionSelection: WorkbenchConnectionNavigationSelection?
    var pendingRuleSelection: WorkbenchRuleNavigationSelection?

    init(
        searchText: String = "",
        filters: [String: String] = [:],
        sort: [WorkbenchWorkspaceSort] = [],
        selectedItemID: String? = nil,
        scrollAnchorID: String? = nil,
        activeTab: String? = nil,
        openGroupIDs: [String] = [],
        activeGroupID: String? = nil,
        groupFilters: [String: String] = [:],
        selectedGroupMemberIDs: [String: String] = [:],
        pendingConnectionSelection: WorkbenchConnectionNavigationSelection? = nil,
        pendingRuleSelection: WorkbenchRuleNavigationSelection? = nil
    ) {
        self.searchText = searchText
        self.filters = filters
        self.sort = sort
        self.selectedItemID = selectedItemID
        self.scrollAnchorID = scrollAnchorID
        self.activeTab = activeTab
        self.openGroupIDs = openGroupIDs
        self.activeGroupID = activeGroupID
        self.groupFilters = groupFilters
        self.selectedGroupMemberIDs = selectedGroupMemberIDs
        self.pendingConnectionSelection = pendingConnectionSelection
        self.pendingRuleSelection = pendingRuleSelection
    }

    mutating func clearSessionBoundState() {
        selectedItemID = nil
        scrollAnchorID = nil
        openGroupIDs.removeAll(keepingCapacity: false)
        activeGroupID = nil
        selectedGroupMemberIDs.removeAll(keepingCapacity: false)
        pendingConnectionSelection = nil
        pendingRuleSelection = nil
    }
}

private struct WorkbenchWorkspaceKey: Hashable {
    let controllerID: RouterProfile.ID?
    let destination: WorkbenchDestination
}

@MainActor
@Observable
private final class WorkbenchWorkspaceState {
    private(set) var searchText: String
    private(set) var filters: [String: String]
    private(set) var sort: [WorkbenchWorkspaceSort]
    private(set) var selectedItemID: String?
    private(set) var scrollAnchorID: String?
    private(set) var activeTab: String?
    private(set) var openGroupIDs: [String]
    private(set) var activeGroupID: String?
    private(set) var groupFilters: [String: String]
    private(set) var selectedGroupMemberIDs: [String: String]
    private(set) var pendingConnectionSelection: WorkbenchConnectionNavigationSelection?
    private(set) var pendingRuleSelection: WorkbenchRuleNavigationSelection?

    init(_ workspace: WorkbenchDestinationWorkspace) {
        searchText = workspace.searchText
        filters = workspace.filters
        sort = workspace.sort
        selectedItemID = workspace.selectedItemID
        scrollAnchorID = workspace.scrollAnchorID
        activeTab = workspace.activeTab
        openGroupIDs = workspace.openGroupIDs
        activeGroupID = workspace.activeGroupID
        groupFilters = workspace.groupFilters
        selectedGroupMemberIDs = workspace.selectedGroupMemberIDs
        pendingConnectionSelection = workspace.pendingConnectionSelection
        pendingRuleSelection = workspace.pendingRuleSelection
    }

    var snapshot: WorkbenchDestinationWorkspace {
        WorkbenchDestinationWorkspace(
            searchText: searchText,
            filters: filters,
            sort: sort,
            selectedItemID: selectedItemID,
            scrollAnchorID: scrollAnchorID,
            activeTab: activeTab,
            openGroupIDs: openGroupIDs,
            activeGroupID: activeGroupID,
            groupFilters: groupFilters,
            selectedGroupMemberIDs: selectedGroupMemberIDs,
            pendingConnectionSelection: pendingConnectionSelection,
            pendingRuleSelection: pendingRuleSelection
        )
    }

    @discardableResult
    func apply(_ workspace: WorkbenchDestinationWorkspace) -> Bool {
        guard workspace != snapshot else { return false }

        if searchText != workspace.searchText { searchText = workspace.searchText }
        if filters != workspace.filters { filters = workspace.filters }
        if sort != workspace.sort { sort = workspace.sort }
        if selectedItemID != workspace.selectedItemID {
            selectedItemID = workspace.selectedItemID
        }
        if scrollAnchorID != workspace.scrollAnchorID {
            scrollAnchorID = workspace.scrollAnchorID
        }
        if activeTab != workspace.activeTab { activeTab = workspace.activeTab }
        if openGroupIDs != workspace.openGroupIDs { openGroupIDs = workspace.openGroupIDs }
        if activeGroupID != workspace.activeGroupID {
            activeGroupID = workspace.activeGroupID
        }
        if groupFilters != workspace.groupFilters { groupFilters = workspace.groupFilters }
        if selectedGroupMemberIDs != workspace.selectedGroupMemberIDs {
            selectedGroupMemberIDs = workspace.selectedGroupMemberIDs
        }
        if pendingConnectionSelection != workspace.pendingConnectionSelection {
            pendingConnectionSelection = workspace.pendingConnectionSelection
        }
        if pendingRuleSelection != workspace.pendingRuleSelection {
            pendingRuleSelection = workspace.pendingRuleSelection
        }

        return true
    }

    @discardableResult
    func setSearchText(_ value: String) -> Bool {
        guard searchText != value else { return false }
        searchText = value
        return true
    }
}

@MainActor
@Observable
final class WorkbenchWorkspaceStore {
    static let defaultPersistenceKey = "workbench.workspace.v1"

    @ObservationIgnored private let persistenceDelay: Duration
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persistenceKey: String
    @ObservationIgnored private let persistenceSink: WorkbenchWorkspacePersistenceSink
    @ObservationIgnored private var states: [WorkbenchWorkspaceKey: WorkbenchWorkspaceState]
    @ObservationIgnored private var persistedWorkspaces: [
        WorkbenchWorkspaceKey: PersistedWorkspace
    ]
    @ObservationIgnored private var activeSessionGenerations: [
        RouterProfile.ID: UUID
    ] = [:]
    @ObservationIgnored private var scrollAnchorGenerations: [
        WorkbenchWorkspaceKey: UUID
    ] = [:]
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored private var persistenceTaskPhase: WorkspacePersistenceTaskPhase?
    @ObservationIgnored private var persistenceIsDirty = false
    @ObservationIgnored private var persistenceRevision: UInt64 = 0
    @ObservationIgnored private var flushAfterCurrentWrite = false

    /// Right-side inspector visibility for this window. Ephemeral per-window
    /// chrome state: observed by the workbench root, never persisted.
    var isInspectorPresented = false

    /// Current typed inspector selection; `.none` renders the inspector empty
    /// state. Populated by workbench surfaces via `selectInspector(_:)`.
    private(set) var inspectorSelection: WorkbenchInspectorSelection = .none

    /// Live lookup registered by the Connections destination so the workspace
    /// inspector resolves the selected connection against that destination's
    /// current projection cache without the store owning business state
    /// (task 08-17 Phase 4C). Cleared when the destination unmounts.
    var connectionRowResolver: ((String) -> WorkbenchConnectionRow?)?

    /// Same live-lookup pattern for the Rules destination, keyed by the
    /// controller-reported rule type + payload identity (task 08-17 Phase 4D).
    var ruleRowResolver: ((String, String) -> WorkbenchRuleRow?)?

    /// Same live-lookup pattern for the Logs destination, keyed by the log
    /// row's stable entry ID (task 08-17 Phase 5A). Cleared when the
    /// destination unmounts.
    var logEntryResolver: ((String) -> WorkbenchLogRow?)?

    /// Same live-lookup pattern for the Sources destination, keyed by the
    /// source row's stable projection identity (task 08-17 Phase 5B). Cleared
    /// when the destination unmounts.
    var sourceRowResolver: ((String) -> WorkbenchSourceRow?)?

    init(
        defaults: UserDefaults = .standard,
        persistenceKey: String = WorkbenchWorkspaceStore.defaultPersistenceKey,
        persistenceDelay: Duration = .milliseconds(500)
    ) {
        self.persistenceDelay = persistenceDelay
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        persistenceSink = WorkbenchWorkspacePersistenceSink()
        states = [:]
        persistedWorkspaces = Self.loadPersistedWorkspaces(
            defaults: defaults,
            persistenceKey: persistenceKey
        )
    }

    deinit {
        if persistenceTaskPhase == .waiting {
            persistenceTask?.cancel()
        }
    }

    func workspace(
        controllerID: RouterProfile.ID?,
        destination: WorkbenchDestination
    ) -> WorkbenchDestinationWorkspace {
        state(for: key(controllerID: controllerID, destination: destination)).snapshot
    }

    func update(
        controllerID: RouterProfile.ID?,
        destination: WorkbenchDestination,
        _ update: (inout WorkbenchDestinationWorkspace) -> Void
    ) {
        let key = key(controllerID: controllerID, destination: destination)
        let state = state(for: key)
        var workspace = state.snapshot
        let previousScrollAnchorID = workspace.scrollAnchorID
        update(&workspace)
        guard state.apply(workspace) else { return }
        if workspace.scrollAnchorID != previousScrollAnchorID {
            scrollAnchorGenerations.removeValue(forKey: key)
        }
        workspaceDidChange(workspace, for: key)
    }

    func activateSession(
        controllerID: RouterProfile.ID,
        generation: UUID
    ) {
        let previousGeneration = activeSessionGenerations[controllerID]
        guard previousGeneration != generation else {
            return
        }

        activeSessionGenerations[controllerID] = generation
        let keys = states.keys.filter { $0.controllerID == controllerID }
        for key in keys {
            scrollAnchorGenerations.removeValue(forKey: key)
            guard let state = states[key] else {
                continue
            }
            var workspace = state.snapshot
            var didChange = false
            if workspace.scrollAnchorID != nil {
                workspace.scrollAnchorID = nil
                didChange = true
            }
            if previousGeneration != nil,
               (workspace.pendingConnectionSelection != nil || workspace.pendingRuleSelection != nil) {
                workspace.pendingConnectionSelection = nil
                workspace.pendingRuleSelection = nil
                didChange = true
            }
            if didChange {
                _ = state.apply(workspace)
            }
        }
    }

    @discardableResult
    func updateScrollAnchor(
        controllerID: RouterProfile.ID,
        generation: UUID,
        destination: WorkbenchDestination,
        anchorID: String?
    ) -> Bool {
        guard activeSessionGenerations[controllerID] == generation else {
            return false
        }

        let key = key(controllerID: controllerID, destination: destination)
        let state = state(for: key)
        var workspace = state.snapshot
        if anchorID == nil, workspace.scrollAnchorID == nil {
            scrollAnchorGenerations.removeValue(forKey: key)
            return false
        }
        guard workspace.scrollAnchorID != anchorID
                || scrollAnchorGenerations[key] != generation else {
            return false
        }

        workspace.scrollAnchorID = anchorID
        _ = state.apply(workspace)
        if anchorID == nil {
            scrollAnchorGenerations.removeValue(forKey: key)
        } else {
            scrollAnchorGenerations[key] = generation
        }
        return true
    }

    func scrollAnchorID(
        controllerID: RouterProfile.ID,
        generation: UUID,
        destination: WorkbenchDestination
    ) -> String? {
        let key = key(controllerID: controllerID, destination: destination)
        guard activeSessionGenerations[controllerID] == generation,
              scrollAnchorGenerations[key] == generation else {
            return nil
        }
        return state(for: key).scrollAnchorID
    }

    func searchBinding(
        controllerID: RouterProfile.ID?,
        destination: WorkbenchDestination
    ) -> Binding<String> {
        let key = key(controllerID: controllerID, destination: destination)
        let state = state(for: key)

        return Binding(
            get: { state.searchText },
            set: { value in
                guard state.setSearchText(value) else { return }
                self.workspaceDidChange(state.snapshot, for: key)
            }
        )
    }

    func stageConnectionNavigation(
        _ selection: WorkbenchConnectionNavigationSelection
    ) {
        update(
            controllerID: selection.controllerID,
            destination: .connections
        ) { workspace in
            workspace.selectedItemID = selection.connectionID
            workspace.pendingConnectionSelection = selection
        }
    }

    func consumeConnectionNavigation(
        controllerID: RouterProfile.ID,
        generation: UUID
    ) -> WorkbenchConnectionNavigationSelection? {
        let workspace = workspace(
            controllerID: controllerID,
            destination: .connections
        )
        guard let selection = workspace.pendingConnectionSelection,
              selection.controllerID == controllerID,
              selection.generation == generation else {
            return nil
        }

        update(controllerID: controllerID, destination: .connections) {
            $0.pendingConnectionSelection = nil
        }
        return selection
    }

    func stageRuleNavigation(_ selection: WorkbenchRuleNavigationSelection) {
        update(
            controllerID: selection.controllerID,
            destination: .rules
        ) { workspace in
            workspace.selectedItemID = nil
            workspace.pendingRuleSelection = selection
        }
    }

    func consumeRuleNavigation(
        controllerID: RouterProfile.ID,
        generation: UUID
    ) -> WorkbenchRuleNavigationSelection? {
        let workspace = workspace(
            controllerID: controllerID,
            destination: .rules
        )
        guard let selection = workspace.pendingRuleSelection,
              selection.controllerID == controllerID,
              selection.generation == generation else {
            return nil
        }

        update(controllerID: controllerID, destination: .rules) {
            $0.pendingRuleSelection = nil
        }
        return selection
    }

    /// Records a typed inspector selection from a workbench surface and reveals
    /// the inspector. Selection plumbing lives in this store only - AppModel and
    /// the live session stay untouched (task 08-17 Phase 2).
    func selectInspector(_ selection: WorkbenchInspectorSelection) {
        guard inspectorSelection != selection else { return }
        inspectorSelection = selection
        if selection != .none {
            isInspectorPresented = true
        }
    }

    func clearSessionBoundState(controllerID: RouterProfile.ID) {
        activeSessionGenerations.removeValue(forKey: controllerID)
        if inspectorSelection != .none {
            inspectorSelection = .none
        }
        let keys = states.keys.filter { $0.controllerID == controllerID }
        for key in keys {
            scrollAnchorGenerations.removeValue(forKey: key)
            guard let state = states[key] else { continue }
            var workspace = state.snapshot
            workspace.clearSessionBoundState()
            guard state.apply(workspace) else { continue }
            workspaceDidChange(workspace, for: key)
        }
    }

    func remove(controllerID: RouterProfile.ID) {
        activeSessionGenerations.removeValue(forKey: controllerID)
        scrollAnchorGenerations = scrollAnchorGenerations.filter {
            $0.key.controllerID != controllerID
        }
        states = states.filter { $0.key.controllerID != controllerID }
        let previousCount = persistedWorkspaces.count
        persistedWorkspaces = persistedWorkspaces.filter {
            $0.key.controllerID != controllerID
        }
        guard persistedWorkspaces.count != previousCount else { return }
        markPersistenceDirty()
    }

    func retainControllers(_ controllerIDs: Set<RouterProfile.ID>) {
        activeSessionGenerations = activeSessionGenerations.filter {
            controllerIDs.contains($0.key)
        }
        scrollAnchorGenerations = scrollAnchorGenerations.filter { key, _ in
            guard let controllerID = key.controllerID else { return true }
            return controllerIDs.contains(controllerID)
        }
        states = states.filter { key, _ in
            guard let controllerID = key.controllerID else { return true }
            return controllerIDs.contains(controllerID)
        }

        let previousCount = persistedWorkspaces.count
        persistedWorkspaces = persistedWorkspaces.filter { key, _ in
            guard let controllerID = key.controllerID else { return true }
            return controllerIDs.contains(controllerID)
        }
        guard persistedWorkspaces.count != previousCount else { return }
        markPersistenceDirty()
    }

    func flushPendingPersistence() {
        guard persistenceIsDirty else { return }

        switch persistenceTaskPhase {
        case .waiting:
            persistenceTask?.cancel()
            persistenceTask = nil
            persistenceTaskPhase = nil
            startPersistenceWrite()
        case .writing:
            flushAfterCurrentWrite = true
        case nil:
            startPersistenceWrite()
        }
    }

    func waitForPendingPersistence() async {
        while persistenceIsDirty || persistenceTask != nil {
            if let task = persistenceTask {
                await task.value
            } else {
                await Task.yield()
            }
        }
    }

    var hasPendingPersistence: Bool {
        persistenceIsDirty
    }

    private func state(for key: WorkbenchWorkspaceKey) -> WorkbenchWorkspaceState {
        if let state = states[key] {
            return state
        }

        let workspace = persistedWorkspaces[key]?.workspace ?? .init()
        let state = WorkbenchWorkspaceState(workspace)
        states[key] = state
        return state
    }

    private func workspaceDidChange(
        _ workspace: WorkbenchDestinationWorkspace,
        for key: WorkbenchWorkspaceKey
    ) {
        let persisted = PersistedWorkspace(workspace)
        if persisted.isDefault {
            guard persistedWorkspaces.removeValue(forKey: key) != nil else { return }
        } else {
            guard persistedWorkspaces[key] != persisted else { return }
            persistedWorkspaces[key] = persisted
        }
        markPersistenceDirty()
    }

    private func markPersistenceDirty() {
        persistenceIsDirty = true
        persistenceRevision &+= 1
        schedulePersistenceIfNeeded()
    }

    private func schedulePersistenceIfNeeded() {
        guard persistenceTask == nil,
              persistenceIsDirty else {
            return
        }
        let delay = persistenceDelay
        persistenceTaskPhase = .waiting
        persistenceTask = Task { @concurrent [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            await self?.persistenceDeadlineReached()
        }
    }

    private func persistenceDeadlineReached() {
        guard persistenceTaskPhase == .waiting else { return }
        persistenceTask = nil
        persistenceTaskPhase = nil
        startPersistenceWrite()
    }

    private func startPersistenceWrite() {
        guard persistenceTask == nil,
              persistenceIsDirty else {
            return
        }

        let entries = persistedWorkspaces.map { key, workspace in
            PersistenceEntry(
                controllerID: key.controllerID,
                destination: key.destination.rawValue,
                workspace: workspace
            )
        }
        .sorted(by: PersistenceEntry.isOrderedBefore)
        let envelope = PersistenceEnvelope(version: 1, entries: entries)
        let revision = persistenceRevision
        let sink = persistenceSink

        persistenceTaskPhase = .writing
        persistenceTask = Task { @concurrent [weak self] in
            let outcome = await sink.write(
                envelope,
                revision: revision
            )
            await self?.persistenceWriteCompleted(
                outcome,
                revision: revision,
                entryCount: entries.count
            )
        }
    }

    private func persistenceWriteCompleted(
        _ outcome: WorkspacePersistenceWriteOutcome,
        revision: UInt64,
        entryCount: Int
    ) {
        persistenceTask = nil
        persistenceTaskPhase = nil

        if case .encoded(let data, let encodingDuration) = outcome {
            let clock = ContinuousClock()
            let commitStartedAt = clock.now
            if let data {
                defaults.set(data, forKey: persistenceKey)
            } else {
                defaults.removeObject(forKey: persistenceKey)
            }
            let commitDuration = commitStartedAt.duration(to: clock.now)
            MicaPerformanceObservation.recordDebug(
                .workspaceEncoding,
                metadata: MicaPerformanceMetadata(
                    count: UInt64(entryCount),
                    duration: encodingDuration
                )
            )
            MicaPerformanceObservation.recordDebug(
                .workspacePersistence,
                metadata: MicaPerformanceMetadata(
                    count: UInt64(entryCount),
                    duration: commitDuration
                )
            )
            if revision == persistenceRevision {
                persistenceIsDirty = false
            }
        }

        let shouldFlush = flushAfterCurrentWrite
        flushAfterCurrentWrite = false
        guard persistenceIsDirty else { return }

        if shouldFlush {
            startPersistenceWrite()
        } else {
            schedulePersistenceIfNeeded()
        }
    }

    private func key(
        controllerID: RouterProfile.ID?,
        destination: WorkbenchDestination
    ) -> WorkbenchWorkspaceKey {
        WorkbenchWorkspaceKey(
            controllerID: destination.requiresController ? controllerID : nil,
            destination: destination
        )
    }

    private static func loadPersistedWorkspaces(
        defaults: UserDefaults,
        persistenceKey: String
    ) -> [WorkbenchWorkspaceKey: PersistedWorkspace] {
        guard let data = defaults.data(forKey: persistenceKey),
              let envelope = try? JSONDecoder().decode(
                  PersistenceEnvelope.self,
                  from: data
              ),
              envelope.version == 1 else {
            return [:]
        }

        return envelope.entries.reduce(into: [:]) { result, entry in
            guard let destination = WorkbenchDestination(rawValue: entry.destination) else {
                return
            }
            let key = WorkbenchWorkspaceKey(
                controllerID: destination.requiresController ? entry.controllerID : nil,
                destination: destination
            )
            result[key] = entry.workspace
        }
    }
}

private struct PersistedWorkspace: Codable, Equatable, Sendable {
    var searchText = ""
    var filters: [String: String] = [:]
    var sort: [WorkbenchWorkspaceSort] = []
    var activeTab: String?
    var groupFilters: [String: String] = [:]

    init() {}

    init(_ workspace: WorkbenchDestinationWorkspace) {
        searchText = workspace.searchText
        filters = workspace.filters
        sort = workspace.sort
        activeTab = workspace.activeTab
        groupFilters = workspace.groupFilters
    }

    var workspace: WorkbenchDestinationWorkspace {
        WorkbenchDestinationWorkspace(
            searchText: searchText,
            filters: filters,
            sort: sort,
            activeTab: activeTab,
            groupFilters: groupFilters
        )
    }

    var isDefault: Bool {
        self == PersistedWorkspace()
    }
}

private struct PersistenceEntry: Codable, Sendable {
    let controllerID: RouterProfile.ID?
    let destination: String
    let workspace: PersistedWorkspace

    static func isOrderedBefore(_ lhs: Self, _ rhs: Self) -> Bool {
        let lhsController = lhs.controllerID?.uuidString ?? ""
        let rhsController = rhs.controllerID?.uuidString ?? ""
        if lhsController != rhsController {
            return lhsController < rhsController
        }
        return lhs.destination < rhs.destination
    }
}

private struct PersistenceEnvelope: Codable, Sendable {
    let version: Int
    let entries: [PersistenceEntry]
}

private enum WorkspacePersistenceTaskPhase {
    case waiting
    case writing
}

private enum WorkspacePersistenceWriteOutcome: Sendable {
    case encoded(data: Data?, encodingDuration: Duration)
    case superseded
    case failed
}

private actor WorkbenchWorkspacePersistenceSink {
    private var latestRequestedRevision: UInt64 = 0
    private var latestEncodedRevision: UInt64 = 0

    func write(
        _ envelope: PersistenceEnvelope,
        revision: UInt64
    ) -> WorkspacePersistenceWriteOutcome {
        guard revision >= latestRequestedRevision,
              revision > latestEncodedRevision else {
            return .superseded
        }
        latestRequestedRevision = revision

        let clock = ContinuousClock()
        let encodingStartedAt = clock.now

        do {
            let data: Data?
            if envelope.entries.isEmpty {
                data = nil
            } else {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                data = try encoder.encode(envelope)
            }
            latestEncodedRevision = revision
            return .encoded(
                data: data,
                encodingDuration: encodingStartedAt.duration(to: clock.now)
            )
        } catch {
            return .failed
        }
    }
}
