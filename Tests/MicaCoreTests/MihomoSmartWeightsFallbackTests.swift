import Foundation
import XCTest
@testable import MicaCore

final class MihomoSmartWeightsFallbackTests: XCTestCase {
    private let groups = (0 ..< 100).map { "Smart-\($0)" }

    func testAggregateFailuresDoNotFanOutToLegacyEndpoints() async throws {
        for status in [400, 401, 403, 405, 429, 500, 503] {
            let fixture = SmartWeightsCountingController(aggregateStatuses: [status])
            let client = makeClient(fixture)

            do {
                _ = try await client.smartWeights(forGroups: groups)
                XCTFail("Expected aggregate HTTP \(status) to propagate")
            } catch {
                assertHTTPError(error, status: status)
            }

            let counts = await fixture.counts()
            XCTAssertEqual(counts.total, 1, "HTTP \(status) must not amplify requests")
            XCTAssertEqual(counts.legacy, 0)
            XCTAssertEqual(counts.active, 0)
        }
    }

    func testLegacySweepBoundsConcurrencyAndCachesOnlyWithinOneClient() async throws {
        let fixture = SmartWeightsCountingController(legacyDelay: .milliseconds(5))
        let client = makeClient(fixture)

        let first = try await client.smartWeights(forGroups: groups)
        let firstCounts = await fixture.counts()
        XCTAssertEqual(first.weights.count, 100)
        XCTAssertEqual(firstCounts.total, 101)
        XCTAssertEqual(firstCounts.aggregate, 1)
        XCTAssertEqual(firstCounts.legacy, 100)
        XCTAssertLessThanOrEqual(firstCounts.peak, 8)
        XCTAssertEqual(firstCounts.active, 0)

        let second = try await client.smartWeights(forGroups: groups)
        let secondCounts = await fixture.counts()
        XCTAssertEqual(second.weights, first.weights)
        XCTAssertEqual(secondCounts.total, 201)
        XCTAssertEqual(secondCounts.aggregate, 1, "A proven legacy controller should skip aggregate probing")
        XCTAssertLessThanOrEqual(secondCounts.peak, 8)

        let newClient = makeClient(fixture)
        _ = try await newClient.smartWeights(forGroups: groups)
        let newClientCounts = await fixture.counts()
        XCTAssertEqual(newClientCounts.total, 302)
        XCTAssertEqual(newClientCounts.aggregate, 2, "A new controller session must probe its own capabilities")
        XCTAssertEqual(newClientCounts.active, 0)
    }

    func testTemporaryAggregateFailureCanRecoverOnTheNextCall() async throws {
        let fixture = SmartWeightsCountingController(aggregateStatuses: [503, 200])
        let client = makeClient(fixture)

        do {
            _ = try await client.smartWeights(forGroups: groups)
            XCTFail("Expected the temporary aggregate failure")
        } catch {
            assertHTTPError(error, status: 503)
        }

        let response = try await client.smartWeights(forGroups: groups)
        let counts = await fixture.counts()
        XCTAssertEqual(response.weights["Aggregate"], [SmartNodeRankSnapshot(name: "Node A", rank: "MostUsed")])
        XCTAssertEqual(counts.total, 2)
        XCTAssertEqual(counts.aggregate, 2)
        XCTAssertEqual(counts.legacy, 0)
    }

    func testCachedLegacyCapabilityRecoversWhenControllerAddsAggregateAndRemovesLegacy() async throws {
        let fixture = SmartWeightsCountingController(aggregateStatuses: [404, 200])
        let client = makeClient(fixture)
        _ = try await client.smartWeights(forGroups: groups)

        await fixture.setLegacyOutcome(.status(404))
        let upgraded = try await client.smartWeights(forGroups: groups)
        XCTAssertNotNil(upgraded.weights["Aggregate"])
        _ = try await client.smartWeights(forGroups: groups)

        let counts = await fixture.counts()
        XCTAssertEqual(counts.aggregate, 3)
        XCTAssertEqual(counts.legacy, 200, "A disappeared legacy API must not trigger a second sweep")
        XCTAssertEqual(counts.total, 203)
    }

    func testLegacyGroupNotFoundAndBadRequestPreserveOtherGroups() async throws {
        let fixture = SmartWeightsCountingController(groupOutcomes: [
            "Missing": .status(404),
            "Unsupported": .status(400),
        ])
        let client = makeClient(fixture)

        let response = try await client.smartWeights(forGroups: ["Present", "Missing", "Unsupported"])
        let counts = await fixture.counts()
        XCTAssertEqual(response.weights, ["Present": [SmartNodeRankSnapshot(name: "Node A", rank: "MostUsed")]])
        XCTAssertEqual(counts.total, 4)
        XCTAssertEqual(counts.active, 0)
    }

    func testUnprovenLegacyEndpointsDoNotCacheTheControllerShape() async throws {
        let fixture = SmartWeightsCountingController(defaultLegacyOutcome: .status(404))
        let client = makeClient(fixture)

        for _ in 0 ..< 2 {
            do {
                _ = try await client.smartWeights(forGroups: ["Missing"])
                XCTFail("No successful endpoint can establish legacy support")
            } catch {
                assertHTTPError(error, status: 404)
            }
        }

        let counts = await fixture.counts()
        XCTAssertEqual(counts.aggregate, 2)
        XCTAssertEqual(counts.legacy, 2)
    }

    func testFatalLegacyFailuresStopSchedulingTheRemainingGroups() async throws {
        for status in [401, 403, 429, 500, 503] {
            let fixture = SmartWeightsCountingController(
                defaultLegacyOutcome: .status(status),
                legacyDelay: .milliseconds(10)
            )
            let client = makeClient(fixture)

            do {
                _ = try await client.smartWeights(forGroups: groups)
                XCTFail("Expected legacy HTTP \(status) to propagate")
            } catch {
                assertHTTPError(error, status: status)
            }

            let counts = await fixture.counts()
            XCTAssertGreaterThan(counts.legacy, 0)
            XCTAssertLessThanOrEqual(counts.legacy, 8, "A fatal first wave must not schedule the remaining groups")
            XCTAssertLessThanOrEqual(counts.peak, 8)
            XCTAssertEqual(counts.active, 0)
        }
    }

    func testLegacyTransportFailurePropagatesAndStopsTheSweep() async throws {
        let fixture = SmartWeightsCountingController(
            defaultLegacyOutcome: .transportFailure,
            legacyDelay: .milliseconds(10)
        )
        let client = makeClient(fixture)

        do {
            _ = try await client.smartWeights(forGroups: groups)
            XCTFail("Expected the legacy transport failure")
        } catch let error as MihomoClientError {
            guard case .connectionFailure = error else {
                return XCTFail("Unexpected transport error: \(error)")
            }
        }

        let counts = await fixture.counts()
        XCTAssertGreaterThan(counts.legacy, 0)
        XCTAssertLessThanOrEqual(counts.legacy, 8)
        XCTAssertLessThanOrEqual(counts.peak, 8)
        XCTAssertEqual(counts.active, 0)
    }

    func testCancellingLegacySweepCancelsActiveRequestsAndStartsNoMore() async throws {
        let fixture = SmartWeightsCountingController(legacyDelay: .seconds(30))
        let client = makeClient(fixture)
        let groupNames = groups
        let sweep = Task { try await client.smartWeights(forGroups: groupNames) }
        defer { sweep.cancel() }

        do {
            // Wait for the complete first wave; all eight requests remain
            // cancellably blocked and cannot free a slot before cancellation.
            try await fixture.waitForActiveRequests(minimum: 8)
        } catch {
            sweep.cancel()
            _ = try? await sweep.value
            throw error
        }
        let beforeCancellation = await fixture.counts()
        XCTAssertGreaterThan(beforeCancellation.active, 0)
        XCTAssertLessThanOrEqual(beforeCancellation.legacy, 8)

        sweep.cancel()
        do {
            _ = try await sweep.value
            XCTFail("Expected cancellation to propagate from the sweep")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }

        let afterCancellation = await fixture.counts()
        XCTAssertEqual(afterCancellation.legacy, beforeCancellation.legacy)
        XCTAssertEqual(afterCancellation.active, 0)
        XCTAssertEqual(afterCancellation.cancelled, beforeCancellation.active)
        XCTAssertLessThanOrEqual(afterCancellation.peak, 8)
    }

    private func makeClient(_ fixture: SmartWeightsCountingController) -> MihomoClient {
        let profile = RouterProfile(
            displayName: "Smart Weights Fixture",
            host: "controller.example",
            controllerKind: .mihomoCompatible
        )
        return MihomoClient(profile: profile) { request in
            try await fixture.load(request)
        }
    }

    private func assertHTTPError(
        _ error: any Error,
        status: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let error = error as? MihomoClientError else {
            return XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
        switch error {
        case .unauthorized where status == 401 || status == 403:
            break
        case .unexpectedStatus(let received):
            XCTAssertEqual(received, status, file: file, line: line)
        default:
            XCTFail("Expected HTTP \(status), received \(error)", file: file, line: line)
        }
    }
}

private actor SmartWeightsCountingController {
    enum Outcome: Sendable {
        case status(Int)
        case transportFailure
    }

    struct Counts: Sendable {
        var aggregate = 0
        var legacy = 0
        var active = 0
        var peak = 0
        var cancelled = 0
        var total: Int { aggregate + legacy }
    }

    private let aggregateStatuses: [Int]
    private var defaultLegacyOutcome: Outcome
    private let groupOutcomes: [String: Outcome]
    private let legacyDelay: Duration
    private var recorded = Counts()

    init(
        aggregateStatuses: [Int] = [404],
        defaultLegacyOutcome: Outcome = .status(200),
        groupOutcomes: [String: Outcome] = [:],
        legacyDelay: Duration = .zero
    ) {
        precondition(!aggregateStatuses.isEmpty)
        self.aggregateStatuses = aggregateStatuses
        self.defaultLegacyOutcome = defaultLegacyOutcome
        self.groupOutcomes = groupOutcomes
        self.legacyDelay = legacyDelay
    }

    func counts() -> Counts { recorded }

    func setLegacyOutcome(_ outcome: Outcome) {
        defaultLegacyOutcome = outcome
    }

    func waitForActiveRequests(minimum: Int) async throws {
        for _ in 0 ..< 2_000 {
            if recorded.active >= minimum { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw URLError(.timedOut)
    }

    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else { throw URLError(.badURL) }
        if url.path == "/group/weights" {
            let status = aggregateStatuses[min(recorded.aggregate, aggregateStatuses.count - 1)]
            recorded.aggregate += 1
            return response(
                url: url,
                status: status,
                body: #"{"weights":{"Aggregate":[{"Name":"Node A","Rank":"MostUsed"}]}}"#
            )
        }
        let components = url.path.split(separator: "/")
        guard components.count == 3, components[0] == "group", components[2] == "weights" else {
            throw URLError(.badURL)
        }

        recorded.legacy += 1
        recorded.active += 1
        recorded.peak = max(recorded.peak, recorded.active)
        defer { recorded.active -= 1 }
        do {
            try await Task.sleep(for: legacyDelay)
            try Task.checkCancellation()
        } catch is CancellationError {
            recorded.cancelled += 1
            throw CancellationError()
        }

        switch groupOutcomes[String(components[1])] ?? defaultLegacyOutcome {
        case .status(let status):
            return response(
                url: url,
                status: status,
                body: #"{"weights":[{"Name":"Node A","Rank":"MostUsed"}]}"#
            )
        case .transportFailure:
            throw URLError(.cannotConnectToHost)
        }
    }

    private func response(url: URL, status: Int, body: String) -> (Data, URLResponse) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(body.utf8), response)
    }
}
