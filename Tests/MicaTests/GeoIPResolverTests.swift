import Foundation
import Testing
@testable import Mica

struct GeoIPResolverTests {
    @MainActor
    @Test func languageIsPartOfTheCoordinatorQueryAndCacheKey() async {
        let resolver = FixtureGeoIPResolver(records: [
            "8.8.8.8": .init(
                country: "US",
                localizedCityNames: [
                    AppLanguage.english.rawValue: "Mountain View",
                    AppLanguage.simplifiedChinese.rawValue: "山景城",
                ]
            ),
        ])
        let coordinator = GeoIPSessionCoordinator(resolver: resolver)
        let generation = UUID()
        coordinator.bind(generation: generation)

        let english = await coordinator.lookup(
            ip: "8.8.8.8",
            generation: generation,
            language: .english
        )
        let simplifiedChinese = await coordinator.lookup(
            ip: "8.8.8.8",
            generation: generation,
            language: .simplifiedChinese
        )

        #expect(english.city == "Mountain View")
        #expect(simplifiedChinese.city == "山景城")
        #expect(coordinator.cachedResult(
            for: "8.8.8.8",
            generation: generation,
            language: .english
        )?.city == "Mountain View")
        #expect(coordinator.cachedResult(
            for: "8.8.8.8",
            generation: generation,
            language: .simplifiedChinese
        )?.city == "山景城")
    }

    @MainActor
    @Test func duplicateLookupsShareWorkWhenOneCallerIsCancelled() async {
        let probe = GeoIPResolverProbe()
        let resolver = DelayedGeoIPResolver(
            probe: probe,
            delay: .milliseconds(100),
            result: .resolved(ip: "8.8.8.8", city: "Mountain View")
        )
        let coordinator = GeoIPSessionCoordinator(resolver: resolver)
        let generation = UUID()
        coordinator.bind(generation: generation)

        let first = Task {
            await coordinator.lookup(ip: "8.8.8.8", generation: generation, language: .english)
        }
        await probe.waitUntilStarted()
        let second = Task {
            await coordinator.lookup(ip: "8.8.8.8", generation: generation, language: .english)
        }
        first.cancel()

        let firstResult = await first.value
        let secondResult = await second.value
        let counts = await probe.counts()

        #expect(firstResult.status == .resolved)
        #expect(secondResult == firstResult)
        #expect(counts.starts == 1)
        #expect(counts.cancellations == 0)
        #expect(coordinator.cachedResult(
            for: "8.8.8.8",
            generation: generation,
            language: .english
        )?.status == .resolved)
    }

    @MainActor
    @Test func invalidateCancelsSharedLookupAndClearsPendingState() async {
        let probe = GeoIPResolverProbe()
        let resolver = DelayedGeoIPResolver(
            probe: probe,
            delay: .seconds(30),
            result: .resolved(ip: "8.8.8.8", city: "Mountain View")
        )
        let coordinator = GeoIPSessionCoordinator(resolver: resolver)
        let generation = UUID()
        coordinator.bind(generation: generation)

        let lookup = Task {
            await coordinator.lookup(ip: "8.8.8.8", generation: generation, language: .english)
        }
        await probe.waitUntilStarted()
        coordinator.invalidate()

        let result = await lookup.value
        let counts = await probe.counts()
        #expect(result.status == .unavailable)
        #expect(counts.starts == 1)
        #expect(counts.cancellations == 1)
        #expect(coordinator.cachedResult(
            for: "8.8.8.8",
            generation: generation,
            language: .english
        ) == nil)
    }

    @MainActor
    @Test func staleGenerationLookupCannotRebindTheCoordinator() async {
        let resolver = FixtureGeoIPResolver(records: [
            "8.8.8.8": .init(country: "US"),
        ])
        let coordinator = GeoIPSessionCoordinator(resolver: resolver)
        let currentGeneration = UUID()
        let staleGeneration = UUID()
        coordinator.bind(generation: currentGeneration)

        let result = await coordinator.lookup(
            ip: "8.8.8.8",
            generation: staleGeneration,
            language: .english
        )

        #expect(result.status == .unavailable)
        #expect(coordinator.cache.generation == currentGeneration)
        #expect(coordinator.cachedResult(
            for: "8.8.8.8",
            generation: staleGeneration,
            language: .english
        ) == nil)
    }

    @MainActor
    @Test func databaseExistenceAndOpeningAreDeferredUntilResolve() async throws {
        let directory = repositoryRoot()
            .appending(path: "tmp/codex/geoip-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let destination = directory.appending(path: "GeoLite2-City-Test.mmdb")
        let resolver = OfflineLocalGeoIPResolver(databasePaths: [destination.path])

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.copyItem(
            at: fixtureURL("GeoLite2-City-Test.mmdb"),
            to: destination
        )

        let result = await resolver.resolve("81.2.69.142", language: .english)
        #expect(result.status == .resolved)
        #expect(result.country == "GB")
        #expect(result.city == "London")
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures", directoryHint: .isDirectory)
            .appending(path: name)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private actor GeoIPResolverProbe {
    private var starts = 0
    private var cancellations = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        starts += 1
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func markCancelled() {
        cancellations += 1
    }

    func waitUntilStarted() async {
        guard starts == 0 else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func counts() -> (starts: Int, cancellations: Int) {
        (starts, cancellations)
    }
}

private struct DelayedGeoIPResolver: GeoIPResolving {
    var probe: GeoIPResolverProbe
    var delay: Duration
    var result: GeoIPLookupResult

    @concurrent
    func resolve(_ ip: String, language _: AppLanguage) async -> GeoIPLookupResult {
        await probe.markStarted()
        do {
            try await Task.sleep(for: delay)
        } catch is CancellationError {
            await probe.markCancelled()
            return .unavailable(ip: ip)
        } catch {
            return .unavailable(ip: ip)
        }
        return result
    }
}
