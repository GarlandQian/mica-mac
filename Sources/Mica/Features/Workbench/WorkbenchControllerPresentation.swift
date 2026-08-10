import Foundation
import MicaCore

// MARK: - Controller presentation

struct WorkbenchControllerDeleteConfirmation: Equatable {
    let profileID: RouterProfile.ID
    let selectedRouterID: RouterProfile.ID?
    let generation: UUID

    func isCurrent(
        selectedRouterID: RouterProfile.ID?,
        generation: UUID
    ) -> Bool {
        self.selectedRouterID == selectedRouterID && self.generation == generation
    }
}

enum WorkbenchControllerListProjection {
    static func filtered(
        _ profiles: [RouterProfile],
        query: String,
        controllerTypeLabel: (RouterProfile) -> String
    ) -> [RouterProfile] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return profiles }

        return profiles.filter { profile in
            [
                profile.displayName,
                profile.endpointURL,
                controllerTypeLabel(profile),
            ].contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
        }
    }

    static func reconciledSelection(
        storedID: RouterProfile.ID?,
        activeID: RouterProfile.ID?,
        candidates: [RouterProfile]
    ) -> RouterProfile.ID? {
        if let storedID, candidates.contains(where: { $0.id == storedID }) {
            return storedID
        }
        if let activeID, candidates.contains(where: { $0.id == activeID }) {
            return activeID
        }
        return candidates.first?.id
    }
}

struct WorkbenchConnectionTestProjection {
    struct ProfileIdentity: Equatable, Sendable {
        let id: RouterProfile.ID
        let displayName: String
        let scheme: ControllerScheme
        let host: String
        let port: Int
        let secretReference: String?
        let tlsPolicy: TLSValidationPolicy
        let controllerKind: ControllerKind
        let surgePlatform: SurgeControllerPlatform

        init(_ profile: RouterProfile) {
            id = profile.id
            displayName = profile.displayName
            scheme = profile.scheme
            host = profile.host
            port = profile.port
            secretReference = profile.secretReference
            tlsPolicy = profile.tlsPolicy
            controllerKind = profile.controllerKind
            surgePlatform = profile.surgePlatform
        }
    }

    struct Intent: Equatable, Sendable {
        let id: UUID
        let presentationID: UUID
        let profile: ProfileIdentity
    }

    private struct StoredReport: Equatable {
        let profile: ProfileIdentity
        let report: ConnectionTestReport
    }

    private(set) var presentationID: UUID
    private var reports: [RouterProfile.ID: StoredReport] = [:]
    private var activeIntents: [RouterProfile.ID: Intent] = [:]

    init(presentationID: UUID = UUID()) {
        self.presentationID = presentationID
    }

    mutating func replacePresentation(with presentationID: UUID = UUID()) {
        self.presentationID = presentationID
        reports.removeAll(keepingCapacity: true)
        activeIntents.removeAll(keepingCapacity: true)
    }

    mutating func begin(
        profile: RouterProfile,
        intentID: UUID = UUID()
    ) -> Intent {
        let identity = ProfileIdentity(profile)
        let intent = Intent(
            id: intentID,
            presentationID: presentationID,
            profile: identity
        )
        reports[profile.id] = nil
        activeIntents[profile.id] = intent
        return intent
    }

    @discardableResult
    mutating func receive(
        _ report: ConnectionTestReport,
        for intent: Intent,
        profiles: [RouterProfile]
    ) -> Bool {
        guard activeIntents[intent.profile.id] == intent else {
            return false
        }
        activeIntents[intent.profile.id] = nil

        guard intent.presentationID == presentationID,
              let profile = profiles.first(where: { $0.id == intent.profile.id }),
              ProfileIdentity(profile) == intent.profile else {
            reports[intent.profile.id] = nil
            return false
        }

        reports[intent.profile.id] = StoredReport(
            profile: intent.profile,
            report: report
        )
        return true
    }

    mutating func reconcile(profiles: [RouterProfile]) {
        let identities = Dictionary(
            uniqueKeysWithValues: profiles.map { ($0.id, ProfileIdentity($0)) }
        )
        reports = reports.filter { identities[$0.key] == $0.value.profile }
        activeIntents = activeIntents.filter {
            $0.value.presentationID == presentationID
                && identities[$0.key] == $0.value.profile
        }
    }

    func report(for profile: RouterProfile) -> ConnectionTestReport? {
        guard let stored = reports[profile.id],
              stored.profile == ProfileIdentity(profile) else {
            return nil
        }
        return stored.report
    }

    func isTesting(_ profile: RouterProfile) -> Bool {
        guard let intent = activeIntents[profile.id] else {
            return false
        }
        return intent.presentationID == presentationID
            && intent.profile == ProfileIdentity(profile)
    }
}
