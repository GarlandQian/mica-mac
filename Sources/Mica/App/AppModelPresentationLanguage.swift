import Foundation
import MicaCore

extension AppModel {
    func applyPresentationLanguage(_ language: AppLanguage) {
        Bundle.setMicaLocalizationLanguage(MicaStrings.resolvedLanguageCode(for: language))

        let shouldRefresh = presentationLanguage != language
        presentationLanguage = language

        guard shouldRefresh else {
            return
        }

        operationState = operationState?.relocalized(language: language)
        rulesSnapshotState = rulesSnapshotState.relocalized(language: language)
        providersSnapshotState = providersSnapshotState.relocalized(language: language)
        providerUpdateFailures = providerUpdateFailures.mapValues {
            MicaStrings.relocalizedText($0, language: language)
        }
        providerHealthCheckFailures = providerHealthCheckFailures.mapValues {
            MicaStrings.relocalizedText($0, language: language)
        }
        controllerHealth = controllerHealth.relocalized(language: language)
        setLiveStreamState(liveStreamState.relocalized(language: language))
        controllerSession.relocalizePresentation(language: language)
        trialSessions = trialSessions.mapValues { $0.relocalized(language: language) }
        unifiedSnapshot = unifiedSnapshot.relocalized(language: language)
    }
}

private extension OperationState {
    func relocalized(language: AppLanguage) -> OperationState {
        OperationState(
            kind: kind,
            message: MicaStrings.relocalizedText(message, language: language),
            action: action.map { MicaStrings.relocalizedText($0, language: language) },
            target: target,
            nextStep: nextStep.map { MicaStrings.relocalizedText($0, language: language) },
            event: event
        )
    }
}

private extension EnhancedSnapshotState {
    func relocalized(language: AppLanguage) -> EnhancedSnapshotState {
        switch self {
        case .idle, .loading, .available:
            return self
        case .unavailable(let message):
            return .unavailable(MicaStrings.relocalizedText(message, language: language))
        }
    }
}

private extension ControllerHealthSnapshot {
    func relocalized(language: AppLanguage) -> ControllerHealthSnapshot {
        var copy = self
        copy.routerName = MicaStrings.relocalizedText(routerName, language: language)
        copy.endpoints = endpoints.map { $0.relocalized(language: language) }
        return copy
    }
}

private extension ControllerEndpointHealth {
    func relocalized(language: AppLanguage) -> ControllerEndpointHealth {
        ControllerEndpointHealth(
            endpoint: endpoint,
            status: status.relocalized(language: language)
        )
    }
}

private extension ControllerEndpointStatus {
    func relocalized(language: AppLanguage) -> ControllerEndpointStatus {
        switch self {
        case .idle, .checking:
            return self
        case .ready(let detail):
            return .ready(MicaStrings.relocalizedText(detail, language: language))
        case .failed(let detail):
            return .failed(MicaStrings.relocalizedText(detail, language: language))
        }
    }
}

private extension LiveStreamState {
    func relocalized(language: AppLanguage) -> LiveStreamState {
        switch self {
        case .idle, .connecting, .live, .nearLive, .stopped:
            return self
        case .partial(let message):
            return .partial(MicaStrings.relocalizedText(message, language: language))
        case .failed(let message):
            return .failed(MicaStrings.relocalizedText(message, language: language))
        case .unavailable(let message):
            return .unavailable(MicaStrings.relocalizedText(message, language: language))
        }
    }
}

private extension ControllerSession {
    mutating func relocalizePresentation(language: AppLanguage) {
        switch state {
        case .staleReconnecting(let message):
            state = .staleReconnecting(
                MicaStrings.relocalizedText(message, language: language)
            )
        case .partial(let message):
            state = .partial(MicaStrings.relocalizedText(message, language: language))
        case .failedBeforeFirstSnapshot(let message):
            state = .failedBeforeFirstSnapshot(
                MicaStrings.relocalizedText(message, language: language)
            )
        case .failed(let message):
            state = .failed(MicaStrings.relocalizedText(message, language: language))
        case .idle, .connecting, .live, .stopped:
            break
        }
    }
}

private extension TrialSessionSnapshot {
    func relocalized(language: AppLanguage) -> TrialSessionSnapshot {
        var copy = self
        copy.routerName = MicaStrings.relocalizedText(routerName, language: language)
        copy.lastCommandSummary = lastCommandSummary.map {
            MicaStrings.relocalizedText($0, language: language)
        }
        copy.commandLog = commandLog.map { $0.relocalized(language: language) }
        return copy
    }
}

private extension CommandLogEntry {
    func relocalized(language: AppLanguage) -> CommandLogEntry {
        CommandLogEntry(
            id: id,
            action: action,
            status: status,
            timestamp: timestamp,
            safeTarget: safeTarget,
            safeSummary: MicaStrings.relocalizedText(safeSummary, language: language)
        )
    }
}

private extension UnifiedControllerSnapshot {
    func relocalized(language: AppLanguage) -> UnifiedControllerSnapshot {
        var copy = self
        copy.health = health.relocalized(language: language)
        copy.versionLabel = MicaStrings.relocalizedText(versionLabel, language: language)
        copy.modeLabel = MicaStrings.relocalizedText(modeLabel, language: language)
        copy.unavailableReason = unavailableReason.map {
            MicaStrings.relocalizedText($0, language: language)
        }
        return copy
    }
}

private extension UnifiedControllerHealth {
    func relocalized(language: AppLanguage) -> UnifiedControllerHealth {
        var copy = self
        copy.safeSummary = MicaStrings.relocalizedText(safeSummary, language: language)
        copy.endpointStatuses = endpointStatuses.map { $0.relocalized(language: language) }
        return copy
    }
}

private extension UnifiedControllerEndpointStatus {
    func relocalized(language: AppLanguage) -> UnifiedControllerEndpointStatus {
        UnifiedControllerEndpointStatus(
            endpoint: endpoint,
            state: state,
            safeDetail: MicaStrings.relocalizedText(safeDetail, language: language)
        )
    }
}
