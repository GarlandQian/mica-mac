import Foundation
import GRPCCore
import GRPCInProcessTransport
import SwiftProtobuf
import XCTest
@testable import MicaCore

final class SingBoxGRPCClientTests: XCTestCase {
    func testInvalidProfileFailsBeforeGRPCTransportCreation() {
        let profile = RouterProfile(
            displayName: "Invalid sing-box",
            host: "controller.local",
            port: 0,
            controllerKind: .singBoxCompatible
        )

        XCTAssertThrowsError(
            try SingBoxGRPCClient(profile: profile, credential: nil)
        ) { error in
            XCTAssertEqual(error as? RouterProfileEndpointError, .invalidPort(0))
        }
    }

    func testAuthorizationMetadataUsesBearerScheme() {
        let metadata = SingBoxGRPCMetadata.make(credential: "fixture-secret")
        XCTAssertEqual(
            Array(metadata[stringValues: "authorization"]),
            ["Bearer fixture-secret"]
        )
        XCTAssertTrue(SingBoxGRPCMetadata.make(credential: nil).isEmpty)
        XCTAssertTrue(SingBoxGRPCMetadata.make(credential: "").isEmpty)
    }

    func testUnaryVersionAndStatusStreamRoundTrip() async throws {
        let recorder = SingBoxFixtureRecorder()
        let service = SingBoxFixtureService(recorder: recorder)

        try await withFixtureClient(service: service) { adapter in
            let version = try await adapter.version()
            XCTAssertEqual(version, SingBoxVersion(version: "1.14.0-alpha.31", apiVersion: 7))

            let stream = try adapter.statusStream(intervalMilliseconds: 250)
            var snapshots: [SingBoxStatusSnapshot] = []
            for try await snapshot in stream {
                snapshots.append(snapshot)
            }

            XCTAssertEqual(snapshots.count, 2)
            XCTAssertEqual(snapshots[0].memoryBytes, 1_048_576)
            XCTAssertEqual(snapshots[0].goroutines, 42)
            XCTAssertEqual(snapshots[0].connectionsIn, 3)
            XCTAssertEqual(snapshots[0].connectionsOut, 5)
            XCTAssertTrue(snapshots[0].trafficAvailable)
            XCTAssertEqual(snapshots[0].uplinkBytesPerSecond, 1_024)
            XCTAssertEqual(snapshots[0].downlinkBytesPerSecond, 2_048)
            XCTAssertEqual(snapshots[0].uplinkTotalBytes, 4_096)
            XCTAssertEqual(snapshots[0].downlinkTotalBytes, 8_192)
        }

        let values = await recorder.values()
        XCTAssertEqual(values["status-interval"], "250000000")
    }

    func testUnaryActionPayloadsRoundTrip() async throws {
        let recorder = SingBoxFixtureRecorder()
        let service = SingBoxFixtureService(recorder: recorder)

        try await withFixtureClient(service: service) { adapter in
            try await adapter.setClashMode("rule")
            try await adapter.runURLTest(outboundTag: "Proxy")
            try await adapter.selectOutbound(groupTag: "Proxy", outboundTag: "Node A")
            try await adapter.closeConnection(id: "connection-42")
            try await adapter.closeAllConnections()
            try await adapter.setTailscaleExitNode(endpointTag: "ts-main", stableID: "peer-7")
            try await adapter.tailscaleLogout(endpointTag: "ts-main")
            try await adapter.clearLogs()
        }

        let values = await recorder.values()
        XCTAssertEqual(values["mode"], "rule")
        XCTAssertEqual(values["url-test"], "Proxy")
        XCTAssertEqual(values["select-outbound"], "Proxy|Node A")
        XCTAssertEqual(values["close-connection"], "connection-42")
        XCTAssertEqual(values["close-all"], "true")
        XCTAssertEqual(values["tailscale-exit-node"], "ts-main|peer-7")
        XCTAssertEqual(values["tailscale-logout"], "ts-main")
        XCTAssertEqual(values["clear-logs"], "true")
    }

    func testPolicyConnectionLogModeAndTailscaleStreamsPreserveFields() async throws {
        let recorder = SingBoxFixtureRecorder()
        let service = SingBoxFixtureService(recorder: recorder)

        try await withFixtureClient(service: service) { adapter in
            var logBatches: [SingBoxLogBatch] = []
            for try await batch in adapter.logStream() {
                logBatches.append(batch)
            }
            XCTAssertEqual(
                logBatches,
                [
                    SingBoxLogBatch(
                        messages: [
                            SingBoxLogMessage(level: .warning, message: "controller warning"),
                            SingBoxLogMessage(level: .debug, message: "controller debug"),
                        ],
                        reset: true
                    ),
                ]
            )

            var catalogs: [SingBoxPolicyCatalog] = []
            for try await catalog in adapter.groupStream() {
                catalogs.append(catalog)
            }
            XCTAssertEqual(catalogs.count, 1)
            XCTAssertEqual(catalogs[0].groups.map(\.tag), ["Proxy", "GLOBAL"])
            XCTAssertEqual(catalogs[0].groups[0].items.map(\.tag), ["Node A", "Node B"])
            XCTAssertEqual(catalogs[0].groups[0].items[0].urlTestTimestamp, 1_720_000_000)
            XCTAssertEqual(catalogs[0].groups[0].items[0].urlTestDelayMilliseconds, 86)
            XCTAssertFalse(catalogs[0].groups[1].selectable)

            let modeStatus = try await adapter.clashModeStatus()
            XCTAssertEqual(
                modeStatus,
                SingBoxClashModeStatus(availableModes: ["rule", "global"], currentMode: "rule")
            )
            var modes: [String] = []
            for try await mode in adapter.clashModeStream() {
                modes.append(mode)
            }
            XCTAssertEqual(modes, ["global"])

            let connectionStream = try adapter.connectionStream(intervalMilliseconds: 500)
            var connectionBatches: [SingBoxConnectionEventBatch] = []
            for try await batch in connectionStream {
                connectionBatches.append(batch)
            }
            let connectionBatch = try XCTUnwrap(connectionBatches.first)
            let event = try XCTUnwrap(connectionBatch.events.first)
            let connection = try XCTUnwrap(event.connection)
            XCTAssertTrue(connectionBatch.reset)
            XCTAssertEqual(event.id, "connection-42")
            XCTAssertEqual(event.type, .new)
            XCTAssertEqual(event.uplinkDeltaBytes, 31)
            XCTAssertEqual(event.downlinkDeltaBytes, 47)
            XCTAssertEqual(connection.source, "127.0.0.1:50123")
            XCTAssertEqual(connection.destination, "1.1.1.1:443")
            XCTAssertEqual(connection.domain, "example.com")
            XCTAssertEqual(connection.chain, ["Proxy", "Node A"])
            XCTAssertEqual(connection.process?.processID, 321)
            XCTAssertEqual(connection.process?.processPath, "/Applications/Example.app/Contents/MacOS/Example")
            XCTAssertEqual(connection.process?.packageNames, ["com.example.app"])

            var tailscaleStatuses: [SingBoxTailscaleStatus] = []
            for try await status in adapter.tailscaleStatusStream() {
                tailscaleStatuses.append(status)
            }
            let endpoint = try XCTUnwrap(tailscaleStatuses.first?.endpoints.first)
            XCTAssertEqual(endpoint.endpointTag, "ts-main")
            XCTAssertEqual(endpoint.backendState, "Running")
            XCTAssertEqual(endpoint.authenticationURL, "https://login.tailscale.com/a/fixture")
            XCTAssertEqual(endpoint.magicDNSSuffix, "tailnet.ts.net")
            XCTAssertEqual(endpoint.selfPeer?.stableID, "self-1")
            XCTAssertEqual(endpoint.userGroups.first?.userID, 7)
            XCTAssertEqual(endpoint.userGroups.first?.peers.first?.stableID, "peer-7")
            XCTAssertEqual(endpoint.exitNode?.stableID, "peer-7")
            XCTAssertTrue(endpoint.usesKeyAuthentication)
        }

        let values = await recorder.values()
        XCTAssertEqual(values["connections-interval"], "500000000")
    }

    func testInvalidStreamIntervalFailsBeforeRPC() async throws {
        let recorder = SingBoxFixtureRecorder()
        let service = SingBoxFixtureService(recorder: recorder)

        try await withFixtureClient(service: service) { adapter in
            // Avoid GRPCCore treating this fixture as an empty client body. The
            // invalid stream calls below must still fail before a stream RPC.
            _ = try await adapter.version()
            XCTAssertThrowsError(try adapter.statusStream(intervalMilliseconds: 0)) { error in
                XCTAssertEqual(error as? SingBoxGRPCError, .invalidIntervalMilliseconds(0))
            }
            XCTAssertThrowsError(try adapter.connectionStream(intervalMilliseconds: -1)) { error in
                XCTAssertEqual(error as? SingBoxGRPCError, .invalidIntervalMilliseconds(-1))
            }
        }

        let values = await recorder.values()
        XCTAssertNil(values["status-interval"])
    }

    func testConsumerCancellationStopsServerStream() async throws {
        let recorder = SingBoxFixtureRecorder()
        let probe = SingBoxCancellationProbe()
        let service = SingBoxFixtureService(
            recorder: recorder,
            holdStatusStreamOpen: true,
            cancellationProbe: probe
        )

        try await withFixtureClient(service: service) { adapter in
            let stream = try adapter.statusStream(intervalMilliseconds: 100)
            let consumer = Task {
                var iterator = stream.makeAsyncIterator()
                if try await iterator.next() != nil {
                    probe.markConsumerReceivedFrame()
                }
                while try await iterator.next() != nil {}
            }

            let receivedFrame = try await waitUntil { probe.consumerReceivedFrame }
            XCTAssertTrue(receivedFrame)
            consumer.cancel()
            _ = try? await consumer.value
            let clientStreamEnded = try await waitUntil { stream.isTerminated }
            XCTAssertTrue(clientStreamEnded)
        }

        // GRPCInProcessTransport publishes server-context cancellation during
        // transport/server shutdown, after the client response handler returns.
        XCTAssertTrue(probe.serverStreamEnded)
    }

    func testSlowConnectionConsumerPreservesNewUpdateClosedAndResetBatches() async throws {
        let recorder = SingBoxFixtureRecorder()
        let frames = (0 ..< 192).map { index in
            Daemon_ConnectionEvents.with {
                $0.reset = index == 0 || index == 96
                $0.events = [Daemon_ConnectionEvent.with {
                    $0.id = "connection-\(index / 3)"
                    $0.type = [.connectionEventNew, .connectionEventUpdate, .connectionEventClosed][index % 3]
                    $0.uplinkDelta = Int64(index)
                    $0.downlinkDelta = Int64(index * 2)
                    if index % 3 == 0 {
                        $0.connection = Daemon_Connection.with { $0.id = "connection-\(index / 3)" }
                    }
                }]
            }
        }
        let service = SingBoxFixtureService(recorder: recorder, connectionFrames: frames)

        try await withFixtureClient(service: service) { adapter in
            let stream = try adapter.connectionStream(intervalMilliseconds: 1)
            defer { stream.cancel() }
            // Let the server produce more than the previous 64-batch buffer
            // before consumption begins, then keep the consumer deliberately slow.
            try await recorder.waitForWrites("connections-written", minimum: 65)
            XCTAssertFalse(stream.isTerminated, "A full incremental buffer must backpressure its finite producer")
            var received: [SingBoxConnectionEventBatch] = []
            for try await batch in stream {
                received.append(batch)
                try await Task.sleep(for: .milliseconds(1))
            }

            XCTAssertEqual(received.count, frames.count)
            XCTAssertEqual(received.flatMap(\.events).map(\.uplinkDeltaBytes), (0 ..< 192).map { Int64($0) })
            XCTAssertEqual(received.flatMap(\.events).map { $0.type.rawValue }, (0 ..< 192).map { $0 % 3 })
            XCTAssertEqual(received.enumerated().filter { $0.element.reset }.map(\.offset), [0, 96])
        }
    }

    func testSlowLogConsumerPreservesEveryBatchAndResetInOrder() async throws {
        let recorder = SingBoxFixtureRecorder()
        let frames = (0 ..< 96).map { index in
            Daemon_Log.with {
                $0.reset = index == 0 || index == 48
                $0.messages = [Daemon_Log.Message.with {
                    $0.level = .info
                    $0.message = "log-\(index)"
                }]
            }
        }
        let service = SingBoxFixtureService(recorder: recorder, logFrames: frames)

        try await withFixtureClient(service: service) { adapter in
            let stream = adapter.logStream()
            defer { stream.cancel() }
            try await recorder.waitForWrites("logs-written", minimum: 33)
            var received: [SingBoxLogBatch] = []
            for try await batch in stream {
                received.append(batch)
                try await Task.sleep(for: .milliseconds(1))
            }

            XCTAssertEqual(received.flatMap(\.messages).map(\.message), (0 ..< 96).map { "log-\($0)" })
            XCTAssertEqual(received.enumerated().filter { $0.element.reset }.map(\.offset), [0, 48])
        }
    }

    func testCancellingFullIncrementalStreamStopsProducerWithoutAConsumer() async throws {
        let recorder = SingBoxFixtureRecorder()
        let service = SingBoxFixtureService(
            recorder: recorder,
            connectionFrames: (0 ..< 192).map { index in
                Daemon_ConnectionEvents.with {
                    $0.events = [Daemon_ConnectionEvent.with { $0.id = "connection-\(index)" }]
                }
            }
        )

        try await withFixtureClient(service: service) { adapter in
            let stream = try adapter.connectionStream(intervalMilliseconds: 1)
            try await recorder.waitForWrites("connections-written", minimum: 65)
            stream.cancel()
            let ended = try await waitUntil { stream.isTerminated }
            XCTAssertTrue(ended, "Cancelling a full buffer must release its suspended producer")
        }
    }

    func testIncrementalConsumerCancellationStopsAnOpenRPC() async throws {
        let recorder = SingBoxFixtureRecorder()
        let service = SingBoxFixtureService(
            recorder: recorder,
            holdLogStreamOpen: true,
            logFrames: [Daemon_Log.with { $0.reset = true }]
        )
        try await withFixtureClient(service: service) { adapter in
            let stream = adapter.logStream()
            let received = expectation(description: "Received first log batch")
            let finished = expectation(description: "Consumer cancelled")
            let consumer = Task {
                defer { finished.fulfill() }
                do {
                    var iterator = stream.makeAsyncIterator()
                    _ = try await iterator.next()
                    received.fulfill()
                    _ = try await iterator.next()
                } catch is CancellationError {
                    // Cancellation may end the iterator or throw.
                } catch {
                    XCTFail("Unexpected cancellation error: \(error)")
                }
            }
            await fulfillment(of: [received], timeout: 2)
            consumer.cancel()
            await fulfillment(of: [finished], timeout: 2)
            let ended = try await waitUntil { stream.isTerminated }
            XCTAssertTrue(ended)
        }
    }

    func testCancellingBackpressuredProducerResumesCapacityWait() async throws {
        let backpressure = SingBoxStreamBackpressure(capacity: 1)
        try await backpressure.acquire()
        let finished = expectation(description: "Suspended producer cancelled")
        let producer = Task {
            defer { finished.fulfill() }
            do {
                try await backpressure.acquire()
                XCTFail("A full buffer cannot admit another batch")
            } catch is CancellationError {
            } catch {
                XCTFail("Unexpected capacity error: \(error)")
            }
        }
        await Task.yield()
        producer.cancel()
        await fulfillment(of: [finished], timeout: 2)
        backpressure.release()
        do {
            try await backpressure.acquire()
            XCTFail("A cancelled producer must not accept more batches")
        } catch is CancellationError {
        }
    }

    func testAlreadyCancelledProducerDoesNotWaitForCapacity() async throws {
        let backpressure = SingBoxStreamBackpressure(capacity: 1)
        try await backpressure.acquire()
        let finished = expectation(description: "Already cancelled producer finished")
        let producer = Task {
            defer { finished.fulfill() }
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await backpressure.acquire()
                XCTFail("An already cancelled producer must not acquire capacity")
            } catch is CancellationError {
            } catch {
                XCTFail("Unexpected capacity error: \(error)")
            }
        }
        await fulfillment(of: [finished], timeout: 2)
        producer.cancel()
    }

    private func withFixtureClient<Result: Sendable>(
        service: SingBoxFixtureService,
        operation: (
            SingBoxStartedServiceAdapter<Daemon_StartedService.Client<InProcessTransport.Client>>
        ) async throws -> Result
    ) async throws -> Result {
        let transport = InProcessTransport()
        return try await withGRPCServer(transport: transport.server, services: [service]) { _ in
            try await withGRPCClient(transport: transport.client) { client in
                let adapter = SingBoxStartedServiceAdapter(
                    client: Daemon_StartedService.Client(wrapping: client),
                    credential: "fixture-secret"
                )
                return try await operation(adapter)
            }
        }
    }

    private func waitUntil(
        _ condition: @Sendable () -> Bool
    ) async throws -> Bool {
        for _ in 0 ..< 200 {
            if condition() {
                return true
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

private actor SingBoxFixtureRecorder {
    private var storage: [String: String] = [:]

    func record(_ key: String, value: String) {
        storage[key] = value
    }

    func values() -> [String: String] {
        storage
    }

    func waitForWrites(_ key: String, minimum: Int) async throws {
        for _ in 0 ..< 200 {
            if (Int(storage[key] ?? "0") ?? 0) >= minimum {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw SingBoxGRPCError.transport("Fixture did not produce \(minimum) batches")
    }
}

private final class SingBoxCancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var _consumerReceivedFrame = false
    private var _serverStreamEnded = false

    var consumerReceivedFrame: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _consumerReceivedFrame
    }

    var serverStreamEnded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _serverStreamEnded
    }

    func markConsumerReceivedFrame() {
        lock.lock()
        _consumerReceivedFrame = true
        lock.unlock()
    }

    func markServerStreamEnded() {
        lock.lock()
        _serverStreamEnded = true
        lock.unlock()
    }
}

private struct SingBoxFixtureService: SingBoxFixtureServiceDefaults {
    let recorder: SingBoxFixtureRecorder
    var holdStatusStreamOpen = false
    var cancellationProbe: SingBoxCancellationProbe?
    var holdLogStreamOpen = false
    var connectionFrames: [Daemon_ConnectionEvents]?
    var logFrames: [Daemon_Log]?

    func getVersion(
        request: Google_Protobuf_Empty,
        context: ServerContext
    ) async throws -> Daemon_Version {
        Daemon_Version.with {
            $0.version = "1.14.0-alpha.31"
            $0.apiVersion = 7
        }
    }

    func clearLogs(
        request: Google_Protobuf_Empty,
        context: ServerContext
    ) async throws -> Google_Protobuf_Empty {
        await recorder.record("clear-logs", value: "true")
        return Google_Protobuf_Empty()
    }

    func subscribeStatus(
        request: Daemon_SubscribeStatusRequest,
        response: RPCWriter<Daemon_Status>,
        context: ServerContext
    ) async throws {
        await recorder.record("status-interval", value: String(request.interval))
        try await response.write(
            Daemon_Status.with {
                $0.memory = 1_048_576
                $0.goroutines = 42
                $0.connectionsIn = 3
                $0.connectionsOut = 5
                $0.trafficAvailable = true
                $0.uplink = 1_024
                $0.downlink = 2_048
                $0.uplinkTotal = 4_096
                $0.downlinkTotal = 8_192
            }
        )

        if holdStatusStreamOpen {
            defer { cancellationProbe?.markServerStreamEnded() }
            try await context.cancellation.cancelled
        } else {
            try await response.write(Daemon_Status.with { $0.memory = 2_097_152 })
        }
    }

    func subscribeLog(
        request: Google_Protobuf_Empty,
        response: RPCWriter<Daemon_Log>,
        context: ServerContext
    ) async throws {
        if let logFrames {
            for (index, frame) in logFrames.enumerated() {
                try await response.write(frame)
                await recorder.record("logs-written", value: String(index + 1))
            }
            if holdLogStreamOpen {
                try await context.cancellation.cancelled
            }
            return
        }
        try await response.write(
            Daemon_Log.with {
                $0.reset = true
                $0.messages = [
                    Daemon_Log.Message.with {
                        $0.level = .warn
                        $0.message = "controller warning"
                    },
                    Daemon_Log.Message.with {
                        $0.level = .debug
                        $0.message = "controller debug"
                    },
                ]
            }
        )
    }

    func subscribeGroups(
        request: Google_Protobuf_Empty,
        response: RPCWriter<Daemon_Groups>,
        context: ServerContext
    ) async throws {
        try await response.write(
            Daemon_Groups.with {
                $0.group = [
                    Daemon_Group.with {
                        $0.tag = "Proxy"
                        $0.type = "selector"
                        $0.selectable = true
                        $0.selected = "Node A"
                        $0.isExpand = true
                        $0.items = [
                            Daemon_GroupItem.with {
                                $0.tag = "Node A"
                                $0.type = "shadowsocks"
                                $0.urlTestTime = 1_720_000_000
                                $0.urlTestDelay = 86
                            },
                            Daemon_GroupItem.with {
                                $0.tag = "Node B"
                                $0.type = "direct"
                            },
                        ]
                    },
                    Daemon_Group.with {
                        $0.tag = "GLOBAL"
                        $0.type = "selector"
                        $0.selectable = false
                        $0.selected = "Proxy"
                        $0.items = [Daemon_GroupItem.with { $0.tag = "Proxy" }]
                    },
                ]
            }
        )
    }

    func getClashModeStatus(
        request: Google_Protobuf_Empty,
        context: ServerContext
    ) async throws -> Daemon_ClashModeStatus {
        Daemon_ClashModeStatus.with {
            $0.modeList = ["rule", "global"]
            $0.currentMode = "rule"
        }
    }

    func subscribeClashMode(
        request: Google_Protobuf_Empty,
        response: RPCWriter<Daemon_ClashMode>,
        context: ServerContext
    ) async throws {
        try await response.write(Daemon_ClashMode.with { $0.mode = "global" })
    }

    func subscribeConnections(
        request: Daemon_SubscribeConnectionsRequest,
        response: RPCWriter<Daemon_ConnectionEvents>,
        context: ServerContext
    ) async throws {
        await recorder.record("connections-interval", value: String(request.interval))
        if let connectionFrames {
            for (index, frame) in connectionFrames.enumerated() {
                try await response.write(frame)
                await recorder.record("connections-written", value: String(index + 1))
            }
            return
        }
        let connection = Daemon_Connection.with {
            $0.id = "connection-42"
            $0.inbound = "mixed-in"
            $0.inboundType = "mixed"
            $0.ipVersion = 4
            $0.network = "tcp"
            $0.source = "127.0.0.1:50123"
            $0.destination = "1.1.1.1:443"
            $0.domain = "example.com"
            $0.protocol = "tls"
            $0.user = "fixture-user"
            $0.fromOutbound = "Proxy"
            $0.createdAt = 1_720_000_001
            $0.uplink = 31
            $0.downlink = 47
            $0.uplinkTotal = 1_024
            $0.downlinkTotal = 2_048
            $0.rule = "domain_suffix=example.com"
            $0.outbound = "Node A"
            $0.outboundType = "shadowsocks"
            $0.chainList = ["Proxy", "Node A"]
            $0.processInfo = Daemon_ProcessInfo.with {
                $0.processID = 321
                $0.userID = 501
                $0.userName = "fixture"
                $0.processPath = "/Applications/Example.app/Contents/MacOS/Example"
                $0.packageNames = ["com.example.app"]
            }
        }
        try await response.write(
            Daemon_ConnectionEvents.with {
                $0.reset = true
                $0.events = [
                    Daemon_ConnectionEvent.with {
                        $0.type = .connectionEventNew
                        $0.id = "connection-42"
                        $0.connection = connection
                        $0.uplinkDelta = 31
                        $0.downlinkDelta = 47
                    },
                ]
            }
        )
    }

    func subscribeTailscaleStatus(
        request: Google_Protobuf_Empty,
        response: RPCWriter<Daemon_TailscaleStatusUpdate>,
        context: ServerContext
    ) async throws {
        let selfPeer = Daemon_TailscalePeer.with {
            $0.hostName = "mica-mac"
            $0.dnsName = "mica-mac.tailnet.ts.net"
            $0.os = "macOS"
            $0.tailscaleIps = ["100.64.0.1"]
            $0.online = true
            $0.active = true
            $0.rxBytes = 1_024
            $0.txBytes = 2_048
            $0.stableID = "self-1"
            $0.sshHostKeys = ["ssh-ed25519 fixture"]
            $0.lastSeen = 1_720_000_010
        }
        let exitPeer = Daemon_TailscalePeer.with {
            $0.hostName = "exit-node"
            $0.dnsName = "exit-node.tailnet.ts.net"
            $0.os = "linux"
            $0.tailscaleIps = ["100.64.0.7"]
            $0.online = true
            $0.exitNode = true
            $0.exitNodeOption = true
            $0.active = true
            $0.stableID = "peer-7"
            $0.shareeNode = true
            $0.lastSeen = 1_720_000_020
        }
        try await response.write(
            Daemon_TailscaleStatusUpdate.with {
                $0.endpoints = [
                    Daemon_TailscaleEndpointStatus.with {
                        $0.endpointTag = "ts-main"
                        $0.backendState = "Running"
                        $0.authURL = "https://login.tailscale.com/a/fixture"
                        $0.networkName = "fixture-tailnet"
                        $0.magicDnssuffix = "tailnet.ts.net"
                        $0.self_p = selfPeer
                        $0.userGroups = [
                            Daemon_TailscaleUserGroup.with {
                                $0.userID = 7
                                $0.loginName = "fixture@example.com"
                                $0.displayName = "Fixture User"
                                $0.profilePicURL = "https://example.com/avatar.png"
                                $0.peers = [exitPeer]
                            },
                        ]
                        $0.exitNode = exitPeer
                        $0.keyAuth = true
                    },
                ]
            }
        )
    }

    func setClashMode(
        request: Daemon_ClashMode,
        context: ServerContext
    ) async throws -> Google_Protobuf_Empty {
        await recorder.record("mode", value: request.mode)
        return Google_Protobuf_Empty()
    }

    func urlTest(
        request: Daemon_URLTestRequest,
        context: ServerContext
    ) async throws -> Google_Protobuf_Empty {
        await recorder.record("url-test", value: request.outboundTag)
        return Google_Protobuf_Empty()
    }

    func selectOutbound(
        request: Daemon_SelectOutboundRequest,
        context: ServerContext
    ) async throws -> Google_Protobuf_Empty {
        await recorder.record(
            "select-outbound",
            value: "\(request.groupTag)|\(request.outboundTag)"
        )
        return Google_Protobuf_Empty()
    }

    func closeConnection(
        request: Daemon_CloseConnectionRequest,
        context: ServerContext
    ) async throws -> Google_Protobuf_Empty {
        await recorder.record("close-connection", value: request.id)
        return Google_Protobuf_Empty()
    }

    func closeAllConnections(
        request: Google_Protobuf_Empty,
        context: ServerContext
    ) async throws -> Google_Protobuf_Empty {
        await recorder.record("close-all", value: "true")
        return Google_Protobuf_Empty()
    }

    func setTailscaleExitNode(
        request: Daemon_SetTailscaleExitNodeRequest,
        context: ServerContext
    ) async throws -> Google_Protobuf_Empty {
        await recorder.record(
            "tailscale-exit-node",
            value: "\(request.endpointTag)|\(request.stableID)"
        )
        return Google_Protobuf_Empty()
    }

    func tailscaleLogout(
        request: Daemon_TailscaleLogoutRequest,
        context: ServerContext
    ) async throws -> Google_Protobuf_Empty {
        await recorder.record("tailscale-logout", value: request.endpointTag)
        return Google_Protobuf_Empty()
    }
}

private protocol SingBoxFixtureServiceDefaults: Daemon_StartedService.SimpleServiceProtocol {}

private extension SingBoxFixtureServiceDefaults {
    func getVersion(
        request: Google_Protobuf_Empty,
        context: ServerContext
    ) async throws -> Daemon_Version {
        Daemon_Version()
    }

    func subscribeLog(
        request: Google_Protobuf_Empty,
        response: RPCWriter<Daemon_Log>,
        context: ServerContext
    ) async throws {}

    func getDefaultLogLevel(
        request: Google_Protobuf_Empty,
        context: ServerContext
    ) async throws -> Daemon_DefaultLogLevel {
        Daemon_DefaultLogLevel.with { $0.level = .info }
    }

    func clearLogs(
        request: Google_Protobuf_Empty,
        context: ServerContext
    ) async throws -> Google_Protobuf_Empty {
        Google_Protobuf_Empty()
    }

    func subscribeStatus(
        request: Daemon_SubscribeStatusRequest,
        response: RPCWriter<Daemon_Status>,
        context: ServerContext
    ) async throws {}

    func subscribeGroups(
        request: Google_Protobuf_Empty,
        response: RPCWriter<Daemon_Groups>,
        context: ServerContext
    ) async throws {}

    func getClashModeStatus(
        request: Google_Protobuf_Empty,
        context: ServerContext
    ) async throws -> Daemon_ClashModeStatus {
        Daemon_ClashModeStatus()
    }

    func subscribeClashMode(
        request: Google_Protobuf_Empty,
        response: RPCWriter<Daemon_ClashMode>,
        context: ServerContext
    ) async throws {}

    func setClashMode(
        request: Daemon_ClashMode,
        context: ServerContext
    ) async throws -> Google_Protobuf_Empty {
        Google_Protobuf_Empty()
    }

    func urlTest(
        request: Daemon_URLTestRequest,
        context: ServerContext
    ) async throws -> Google_Protobuf_Empty {
        Google_Protobuf_Empty()
    }

    func selectOutbound(
        request: Daemon_SelectOutboundRequest,
        context: ServerContext
    ) async throws -> Google_Protobuf_Empty {
        Google_Protobuf_Empty()
    }

    func subscribeConnections(
        request: Daemon_SubscribeConnectionsRequest,
        response: RPCWriter<Daemon_ConnectionEvents>,
        context: ServerContext
    ) async throws {}

    func closeConnection(
        request: Daemon_CloseConnectionRequest,
        context: ServerContext
    ) async throws -> Google_Protobuf_Empty {
        Google_Protobuf_Empty()
    }

    func closeAllConnections(
        request: Google_Protobuf_Empty,
        context: ServerContext
    ) async throws -> Google_Protobuf_Empty {
        Google_Protobuf_Empty()
    }

    func subscribeTailscaleStatus(
        request: Google_Protobuf_Empty,
        response: RPCWriter<Daemon_TailscaleStatusUpdate>,
        context: ServerContext
    ) async throws {}

    func setTailscaleExitNode(
        request: Daemon_SetTailscaleExitNodeRequest,
        context: ServerContext
    ) async throws -> Google_Protobuf_Empty {
        Google_Protobuf_Empty()
    }

    func tailscaleLogout(
        request: Daemon_TailscaleLogoutRequest,
        context: ServerContext
    ) async throws -> Google_Protobuf_Empty {
        Google_Protobuf_Empty()
    }
}
