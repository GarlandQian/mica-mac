import Foundation

extension AppModel {
    func installSessionRefreshCoordinator(generation: UUID) {
        cancelSessionRefreshCoordinator()
        sessionRefreshCoordinator = SessionRefreshCoordinator(generation: generation)
    }

    func cancelSessionRefreshCoordinator() {
        guard let coordinator = sessionRefreshCoordinator else { return }
        let generation = controllerSession.generation
        sessionRefreshCoordinator = nil
        Task { @concurrent in
            await coordinator.invalidate(generation: generation)
        }
    }
}
