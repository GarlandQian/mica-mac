import Foundation
import MicaCore

/// Identity captured when a command-bearing control is rendered. Persisted
/// handlers must carry this value back into AppModel instead of substituting
/// whichever generation happens to be current when the handler fires.
struct LiveCommandScope: Equatable, Sendable {
    let controllerID: RouterProfile.ID
    let generation: UUID

    init?(controllerID: RouterProfile.ID?, generation: UUID) {
        guard let controllerID else { return nil }
        self.controllerID = controllerID
        self.generation = generation
    }
}

extension AppModel {
    func matchesCurrentCommandScope(_ scope: LiveCommandScope) -> Bool {
        selectedRouterID == scope.controllerID
            && controllerSessionPresentation.controllerID == scope.controllerID
            && controllerSessionPresentation.generation == scope.generation
            && controllerSession.controllerID == scope.controllerID
            && controllerSession.generation == scope.generation
    }
}
