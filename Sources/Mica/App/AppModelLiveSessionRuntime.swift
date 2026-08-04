import Foundation
import MicaCore

extension AppModel {
    func installLiveSessionRuntime(
        for router: RouterProfile,
        generation: UUID
    ) {
        cancelLiveSessionRuntime()
        guard isCurrentSession(routerID: router.id, generation: generation) else { return }

        let identity = LiveSessionRuntimeIdentity(
            controllerID: router.id,
            generation: generation
        )
        let controllerKind = runtimeControllerKind(for: router)
        guard let initialDemand = nextLiveSessionPresentationDemand(
            identity: identity
        ) else {
            return
        }
        let runtime = LiveSessionRuntime(
            controllerKind: controllerKind,
            initialPresentationDemand: initialDemand
        )
        switch controllerKind {
        case .surgeCompatible:
            sessionMihomoClient = nil
            sessionSurgeClient = SurgeHttpAPIClient(
                profile: router,
                apiKey: controllerSecrets[router.id]
            )
        case .singBoxCompatible:
            sessionMihomoClient = nil
            sessionSurgeClient = nil
        default:
            sessionMihomoClient = MihomoClient(
                profile: router,
                secret: controllerSecrets[router.id]
            )
            sessionSurgeClient = nil
        }
        MicaPerformanceObservation.record(
            .transportClientCreation,
            metadata: MicaPerformanceMetadata(
                count: 1,
                controllerKind: controllerKind
            )
        )
        liveSessionRuntime = runtime
        liveSessionRuntimeIdentity = identity
        lastRuntimePublicationRevisions.removeAll(keepingCapacity: true)
        lastRuntimeConnectionRevisions = LiveSessionConnectionRevisions()
        lastRuntimeLogSequence = 0
    }

    func cancelLiveSessionRuntime() {
        for task in runtimePublicationTasks.values {
            task.cancel()
        }
        runtimePublicationTasks.removeAll(keepingCapacity: true)

        let runtime = liveSessionRuntime
        liveSessionRuntime = nil
        liveSessionRuntimeIdentity = nil
        sessionMihomoClient = nil
        sessionSurgeClient = nil
        lastRuntimePublicationRevisions.removeAll(keepingCapacity: true)
        lastRuntimeConnectionRevisions = LiveSessionConnectionRevisions()
        lastRuntimeLogSequence = 0
        if let runtime {
            Task { @concurrent in
                await runtime.invalidate()
            }
        }
    }

    func updateLiveSessionRuntimePresentationDemand(
        forceVisible: Bool,
        newlyVisibleDomains: Set<LiveSessionPublicationDomain> = []
    ) {
        guard let runtime = liveSessionRuntime,
              let identity = liveSessionRuntimeIdentity else {
            return
        }

        guard let demand = nextLiveSessionPresentationDemand(
            identity: identity
        ) else {
            return
        }
        let requestedImmediateDomains = forceVisible
            ? demand.observedDomains
            : newlyVisibleDomains
        let immediateDomains = Set(
            requestedImmediateDomains.filter {
                demand.permitsImmediateVisibilityFlush($0)
            }
        )

        Task { @concurrent [weak self] in
            guard var remainingScheduledDomains = await runtime.setPresentationDemand(
                demand
            ) else {
                return
            }

            if !immediateDomains.isEmpty {
                for domain in immediateDomains {
                    remainingScheduledDomains.remove(domain)
                    if let publication = await runtime.publication(
                        for: domain,
                        force: true,
                        demandRevision: demand.revision
                    ) {
                        await self?.applyLiveSessionRuntimePublication(
                            publication,
                            runtime: runtime
                        )
                    } else {
                        await self?.flushStagedRuntimePresentationDomainIfVisible(
                            domain,
                            runtime: runtime,
                            identity: identity
                        )
                    }
                }
                if !remainingScheduledDomains.isEmpty {
                    await self?.scheduleLiveSessionRuntimePublications(
                        remainingScheduledDomains,
                        runtime: runtime,
                        identity: identity
                    )
                }
                return
            }

            guard !remainingScheduledDomains.isEmpty else { return }
            await self?.scheduleLiveSessionRuntimePublications(
                remainingScheduledDomains,
                runtime: runtime,
                identity: identity
            )
        }
    }

    private func flushStagedRuntimePresentationDomainIfVisible(
        _ domain: LiveSessionPublicationDomain,
        runtime: LiveSessionRuntime,
        identity: LiveSessionRuntimeIdentity
    ) {
        guard liveSessionRuntime === runtime,
              liveSessionRuntimeIdentity == identity,
              isCurrentSession(
                  routerID: identity.controllerID,
                  generation: identity.generation
              ),
              liveStreamRequested,
              !controllerSession.baselineTransaction.isActive,
              !dashboardSessionControls.dashboardUpdatesPaused,
              sessionPresentationCoordinator.observedDomains.contains(domain)
        else {
            return
        }
        if domain == .logs, dashboardSessionControls.logsPresentationPaused {
            return
        }
        flushSessionPublicationDomain(
            domain,
            generation: identity.generation,
            force: true
        )
    }

    private func nextLiveSessionPresentationDemand(
        identity: LiveSessionRuntimeIdentity
    ) -> LiveSessionPresentationDemand? {
        let presentationPaused = dashboardSessionControls.dashboardUpdatesPaused
        let logsPresentationPaused = dashboardSessionControls.logsPresentationPaused
        let baselinePublicationRequired = controllerSession.baselineTransaction.isActive
        return sessionPresentationCoordinator.nextPresentationDemand(
            identity: identity,
            presentationPaused: presentationPaused,
            logsPresentationPaused: logsPresentationPaused,
            baselinePublicationRequired: baselinePublicationRequired
        )
    }

    func clearLiveSessionRuntimeLogs() {
        guard let runtime = liveSessionRuntime,
              let identity = liveSessionRuntimeIdentity else {
            controllerSession.logBuffer.removeAll()
            publishControllerLogs([])
            return
        }

        Task { @concurrent [weak self] in
            let scheduled = await runtime.clearLogs()
            guard !scheduled.isEmpty else { return }
            await self?.scheduleLiveSessionRuntimePublications(
                scheduled,
                runtime: runtime,
                identity: identity
            )
        }
    }

    func scheduleLiveSessionRuntimePublications(
        _ domains: Set<LiveSessionPublicationDomain>,
        runtime: LiveSessionRuntime,
        identity: LiveSessionRuntimeIdentity
    ) {
        guard liveSessionRuntime === runtime,
              liveSessionRuntimeIdentity == identity,
              isCurrentSession(
                routerID: identity.controllerID,
                generation: identity.generation
              ) else {
            return
        }

        for domain in domains where runtimePublicationTasks[domain] == nil {
            runtimePublicationTasks[domain] = Task { [weak self] in
                guard let self else {
                    await runtime.cancelScheduledPublication(domain)
                    return
                }

                do {
                    try await sleepBeforeSessionPublication(
                        domain: domain,
                        cadence: domain.cadence
                    )
                } catch {
                    await runtime.cancelScheduledPublication(domain)
                    guard liveSessionRuntime === runtime,
                          liveSessionRuntimeIdentity == identity else {
                        return
                    }
                    runtimePublicationTasks[domain] = nil
                    return
                }

                guard liveSessionRuntime === runtime,
                      liveSessionRuntimeIdentity == identity,
                      isCurrentSession(
                        routerID: identity.controllerID,
                        generation: identity.generation
                      ) else {
                    runtimePublicationTasks[domain] = nil
                    await runtime.cancelScheduledPublication(domain)
                    return
                }

                // Release the task slot before awaiting the actor snapshot. A
                // newer frame can then reserve its own publication without
                // being stranded behind this task's final MainActor hop.
                runtimePublicationTasks[domain] = nil
                let publication = await runtime.publication(for: domain)
                guard let publication else { return }
                applyLiveSessionRuntimePublication(publication, runtime: runtime)
            }
        }
    }

    func applyLiveSessionRuntimePublication(
        _ publication: LiveSessionRuntimePublication,
        runtime: LiveSessionRuntime
    ) {
        let identity = publication.identity
        guard liveSessionRuntime === runtime,
              liveSessionRuntimeIdentity == identity,
              isCurrentSession(
                routerID: identity.controllerID,
                generation: identity.generation
              ),
              liveStreamRequested,
              let router = selectedRouter else {
            return
        }
        let lastRevision = lastRuntimePublicationRevisions[publication.domain] ?? 0
        guard publication.revision > lastRevision else { return }
        lastRuntimePublicationRevisions[publication.domain] = publication.revision

        controllerSession.liveObservation.record(
            publication.observation,
            receivedAt: publication.receivedAt
        )
        var runtimeStructureChanged = false
        var runtimeMetricsChanged = false
        var runtimeTrafficChanged = false

        switch publication.payload {
        case .logs(let logs):
            stageRuntimeLogs(logs)

        case .traffic(let traffic):
            controllerSession.trafficTimeline = traffic.timeline
            if let status = traffic.singBoxStatus {
                controllerSession.singBoxStatus = status
            }

        case .memory(let memory):
            controllerSession.memoryTimeline = memory.timeline
            controllerSession.runtime = memory.runtime

        case .connections(let connections):
            runtimeStructureChanged = connections.revisions.structure
                != lastRuntimeConnectionRevisions.structure
            runtimeMetricsChanged = connections.revisions.metrics
                != lastRuntimeConnectionRevisions.metrics
            runtimeTrafficChanged = connections.revisions.traffic
                != lastRuntimeConnectionRevisions.traffic
            lastRuntimeConnectionRevisions = connections.revisions
            stageRuntimeConnections(
                connections,
                receivedAt: publication.receivedAt
            )
        }

        completeLiveTransportIngestion(
            receivedAt: publication.receivedAt,
            router: router,
            streamState: .live
        )

        guard !controllerSession.baselineTransaction.isActive,
              !dashboardSessionControls.dashboardUpdatesPaused else {
            return
        }
        guard sessionPresentationCoordinator.observedDomains.contains(
            publication.domain
        ) else {
            return
        }

        switch publication.payload {
        case .logs(let logs):
            guard !dashboardSessionControls.logsPresentationPaused else {
                return
            }
            MicaPerformanceObservation.recordDebug(
                logs.fullSnapshot == nil
                    ? .incrementalPresentationProjection
                    : .fullPresentationProjection,
                metadata: MicaPerformanceMetadata(
                    count: UInt64(
                        logs.fullSnapshot?.count
                            ?? (logs.droppedEntryIDs.count + logs.appendedEntries.count)
                    ),
                    revision: logs.sequence
                )
            )
            logsCatalog = logsCatalog.applying(logs)

        case .traffic(let traffic):
            trafficTimeline = traffic.timeline
            liveTrafficRate = traffic.latestRate
            if let status = traffic.singBoxStatus {
                dashboard.replaceSingBoxStatus(with: status)
                synchronizeConnectionsCatalog()
                synchronizeInsightCatalog()
            }

        case .memory(let memory):
            memoryTimeline = memory.timeline
            controllerSessionPresentation.publishRuntime(memory.runtime)

        case .connections(let connections):
            connectionCountTimeline = connections.timeline
            publishRuntimeConnections(
                connections,
                structureChanged: runtimeStructureChanged,
                metricsChanged: runtimeMetricsChanged,
                trafficChanged: runtimeTrafficChanged
            )
        }

        liveStreamUpdatedAt = max(
            liveStreamUpdatedAt ?? publication.receivedAt,
            publication.receivedAt
        )
    }

    private func stageRuntimeLogs(_ publication: LiveSessionLogsPublication) {
        if let fullSnapshot = publication.fullSnapshot {
            controllerSession.logBuffer.replace(with: fullSnapshot)
        } else {
            for entry in publication.appendedEntries {
                controllerSession.logBuffer.append(entry)
            }
        }
        lastRuntimeLogSequence = publication.sequence
    }

    private func stageRuntimeConnections(
        _ publication: LiveSessionConnectionsPublication,
        receivedAt: Date
    ) {
        controllerSession.connectionCountTimeline = publication.timeline
        switch publication.source {
        case .mihomo(let response):
            controllerSession.endpointCache.connections = response

        case .singBox(let connections):
            controllerSession.singBoxActiveConnections = connections
            controllerSession.recordSingBoxConnectionsReceived(at: receivedAt)
        }

        if publication.clearsClosedRecords {
            controllerSession.pendingPresentation.closedConnections.removeAll()
            controllerSession.pendingPresentation.clearClosedConnections = true
        }
        if !publication.closedRecords.isEmpty {
            controllerSession.pendingPresentation.closedConnections.record(
                publication.closedRecords
            )
        }
    }

    private func publishRuntimeConnections(
        _ publication: LiveSessionConnectionsPublication,
        structureChanged: Bool,
        metricsChanged: Bool,
        trafficChanged: Bool
    ) {
        switch publication.source {
        case .mihomo(let response):
            dashboard.replaceConnections(
                with: response,
                structureChanged: structureChanged,
                metricsChanged: metricsChanged,
                trafficChanged: trafficChanged
            )

        case .singBox(let connections):
            if structureChanged || metricsChanged {
                dashboard.connections = connections
                dashboard.insight.updateConnections(
                    connections,
                    structureChanged: structureChanged,
                    metricsChanged: metricsChanged
                )
            }
            if let status = controllerSession.singBoxStatus {
                dashboard.replaceSingBoxStatus(with: status)
            }
        }

        var structureRevision = connectionsCatalog.structureRevision
        var metricsRevision = connectionsCatalog.metricsRevision
        var trafficRevision = connectionsCatalog.trafficRevision
        if structureChanged {
            structureRevision &+= 1
        }
        if metricsChanged {
            metricsRevision &+= 1
        }
        if trafficChanged {
            trafficRevision &+= 1
        }

        if structureChanged || metricsChanged || trafficChanged {
            if structureChanged || metricsChanged {
                MicaPerformanceObservation.recordDebug(
                    structureChanged
                        ? .fullPresentationProjection
                        : .incrementalPresentationProjection,
                    metadata: MicaPerformanceMetadata(
                        count: UInt64(
                            structureChanged
                                ? dashboard.connections.count
                                : publication.changedMetricIndices?.count
                                    ?? dashboard.connections.count
                        ),
                        revision: metricsRevision
                    )
                )
            }
            connectionsCatalog = ConnectionsCatalogSnapshot(
                dashboard: dashboard,
                structureRevision: structureRevision,
                metricsRevision: metricsRevision,
                trafficRevision: trafficRevision,
                lastChange: ConnectionsCatalogChange(
                    structureChanged: structureChanged,
                    metricsChanged: metricsChanged,
                    changedMetricIndices: publication.changedMetricIndices,
                    trafficChanged: trafficChanged
                )
            )
            synchronizeInsightCatalog()
        }

        if controllerSession.pendingPresentation.clearClosedConnections {
            dashboardSessionControls.clearClosedConnections()
            controllerSession.pendingPresentation.clearClosedConnections = false
        }
        if !controllerSession.pendingPresentation.closedConnections.entries.isEmpty {
            dashboardSessionControls.recordClosed(
                controllerSession.pendingPresentation.closedConnections.entries
            )
            controllerSession.pendingPresentation.closedConnections.removeAll()
        }
    }
}
