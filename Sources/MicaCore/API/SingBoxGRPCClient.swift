import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2TransportServices
import SwiftProtobuf

nonisolated public struct SingBoxGRPCStream<Value: Sendable>: AsyncSequence, Sendable {
    public typealias Element = Value

    public struct AsyncIterator: AsyncIteratorProtocol {
        private var base: AsyncThrowingStream<Value, Error>.Iterator
        private let cancelOperation: @Sendable () -> Void

        fileprivate init(
            base: AsyncThrowingStream<Value, Error>.Iterator,
            cancelOperation: @Sendable @escaping () -> Void
        ) {
            self.base = base
            self.cancelOperation = cancelOperation
        }

        public mutating func next(
            isolation actor: isolated (any Actor)? = #isolation
        ) async throws -> Value? {
            if Task.isCancelled {
                cancelOperation()
                throw CancellationError()
            }
            let cancelOperation = cancelOperation
            return try await withTaskCancellationHandler {
                try await base.next(isolation: actor)
            } onCancel: {
                cancelOperation()
            }
        }
    }

    private let base: AsyncThrowingStream<Value, Error>
    private let cancelOperation: @Sendable () -> Void
    private let isTerminatedOperation: @Sendable () -> Bool

    fileprivate init(
        base: AsyncThrowingStream<Value, Error>,
        cancelOperation: @Sendable @escaping () -> Void,
        isTerminatedOperation: @Sendable @escaping () -> Bool
    ) {
        self.base = base
        self.cancelOperation = cancelOperation
        self.isTerminatedOperation = isTerminatedOperation
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base.makeAsyncIterator(), cancelOperation: cancelOperation)
    }

    public func cancel() {
        cancelOperation()
    }

    var isTerminated: Bool {
        isTerminatedOperation()
    }
}

public protocol SingBoxGRPCClientProtocol: Sendable {
    func runConnections() async throws
    func beginGracefulShutdown()
    func version() async throws -> SingBoxVersion
    func defaultLogLevel() async throws -> SingBoxLogLevel
    func clearLogs() async throws
    func statusStream(intervalMilliseconds: Int64) throws -> SingBoxGRPCStream<SingBoxStatusSnapshot>
    func logStream() -> SingBoxGRPCStream<SingBoxLogBatch>
    func groupStream() -> SingBoxGRPCStream<SingBoxPolicyCatalog>
    func clashModeStatus() async throws -> SingBoxClashModeStatus
    func clashModeStream() -> SingBoxGRPCStream<String>
    func setClashMode(_ mode: String) async throws
    func runURLTest(outboundTag: String) async throws
    func selectOutbound(groupTag: String, outboundTag: String) async throws
    func connectionStream(intervalMilliseconds: Int64) throws -> SingBoxGRPCStream<SingBoxConnectionEventBatch>
    func closeConnection(id: String) async throws
    func closeAllConnections() async throws
    func tailscaleStatusStream() -> SingBoxGRPCStream<SingBoxTailscaleStatus>
    func setTailscaleExitNode(endpointTag: String, stableID: String) async throws
    func tailscaleLogout(endpointTag: String) async throws
}

public final class SingBoxGRPCClient: SingBoxGRPCClientProtocol, Sendable {
    private typealias Transport = HTTP2ClientTransport.TransportServices
    private typealias GeneratedClient = Daemon_StartedService.Client<Transport>

    private let grpcClient: GRPCClient<Transport>
    private let service: SingBoxStartedServiceAdapter<GeneratedClient>

    public init(profile: RouterProfile, credential: String?) throws {
        let transport = try Transport(
            target: .dns(host: profile.host, port: profile.port),
            transportSecurity: Self.transportSecurity(for: profile)
        )
        let grpcClient = GRPCClient(transport: transport)
        self.grpcClient = grpcClient
        self.service = SingBoxStartedServiceAdapter(
            client: GeneratedClient(wrapping: grpcClient),
            credential: credential
        )
    }

    public static func withConnectedClient<Result: Sendable>(
        profile: RouterProfile,
        credential: String?,
        operation: @Sendable (SingBoxGRPCClient) async throws -> Result
    ) async throws -> Result {
        let client = try SingBoxGRPCClient(profile: profile, credential: credential)
        return try await withThrowingTaskGroup(of: Void.self, returning: Result.self) { group in
            group.addTask {
                try await client.runConnections()
            }

            do {
                let result = try await operation(client)
                client.beginGracefulShutdown()
                group.cancelAll()
                return result
            } catch {
                client.beginGracefulShutdown()
                group.cancelAll()
                throw error
            }
        }
    }

    public func runConnections() async throws {
        try await grpcClient.runConnections()
    }

    public func beginGracefulShutdown() {
        grpcClient.beginGracefulShutdown()
    }

    public func version() async throws -> SingBoxVersion {
        try await service.version()
    }

    public func defaultLogLevel() async throws -> SingBoxLogLevel {
        try await service.defaultLogLevel()
    }

    public func clearLogs() async throws {
        try await service.clearLogs()
    }

    public func statusStream(
        intervalMilliseconds: Int64
    ) throws -> SingBoxGRPCStream<SingBoxStatusSnapshot> {
        try service.statusStream(intervalMilliseconds: intervalMilliseconds)
    }

    public func logStream() -> SingBoxGRPCStream<SingBoxLogBatch> {
        service.logStream()
    }

    public func groupStream() -> SingBoxGRPCStream<SingBoxPolicyCatalog> {
        service.groupStream()
    }

    public func clashModeStatus() async throws -> SingBoxClashModeStatus {
        try await service.clashModeStatus()
    }

    public func clashModeStream() -> SingBoxGRPCStream<String> {
        service.clashModeStream()
    }

    public func setClashMode(_ mode: String) async throws {
        try await service.setClashMode(mode)
    }

    public func runURLTest(outboundTag: String) async throws {
        try await service.runURLTest(outboundTag: outboundTag)
    }

    public func selectOutbound(groupTag: String, outboundTag: String) async throws {
        try await service.selectOutbound(groupTag: groupTag, outboundTag: outboundTag)
    }

    public func connectionStream(
        intervalMilliseconds: Int64
    ) throws -> SingBoxGRPCStream<SingBoxConnectionEventBatch> {
        try service.connectionStream(intervalMilliseconds: intervalMilliseconds)
    }

    public func closeConnection(id: String) async throws {
        try await service.closeConnection(id: id)
    }

    public func closeAllConnections() async throws {
        try await service.closeAllConnections()
    }

    public func tailscaleStatusStream() -> SingBoxGRPCStream<SingBoxTailscaleStatus> {
        service.tailscaleStatusStream()
    }

    public func setTailscaleExitNode(endpointTag: String, stableID: String) async throws {
        try await service.setTailscaleExitNode(endpointTag: endpointTag, stableID: stableID)
    }

    public func tailscaleLogout(endpointTag: String) async throws {
        try await service.tailscaleLogout(endpointTag: endpointTag)
    }

    private static func transportSecurity(
        for profile: RouterProfile
    ) -> HTTP2ClientTransport.TransportServices.TransportSecurity {
        switch profile.scheme {
        case .http:
            return .plaintext
        case .https:
            switch profile.tlsPolicy {
            case .system:
                return .tls
            case .allowSelfSigned:
                return .tls { configuration in
                    configuration.serverCertificateVerification = .noVerification
                }
            }
        }
    }
}

struct SingBoxStartedServiceAdapter<Client: Daemon_StartedService.ClientProtocol>: Sendable {
    private let client: Client
    private let metadata: Metadata

    init(client: Client, credential: String?) {
        self.client = client
        self.metadata = SingBoxGRPCMetadata.make(credential: credential)
    }

    func version() async throws -> SingBoxVersion {
        try await mapped {
            let response = try await client.getVersion(
                Google_Protobuf_Empty(),
                metadata: metadata,
                options: unaryOptions
            )
            return SingBoxVersion(response)
        }
    }

    func defaultLogLevel() async throws -> SingBoxLogLevel {
        try await mapped {
            let response = try await client.getDefaultLogLevel(
                Google_Protobuf_Empty(),
                metadata: metadata,
                options: unaryOptions
            )
            return SingBoxLogLevel(rawValue: response.level.rawValue)
        }
    }

    func clearLogs() async throws {
        try await mapped {
            _ = try await client.clearLogs(
                Google_Protobuf_Empty(),
                metadata: metadata,
                options: unaryOptions
            )
        }
    }

    func statusStream(
        intervalMilliseconds: Int64
    ) throws -> SingBoxGRPCStream<SingBoxStatusSnapshot> {
        let interval = try Self.nanoseconds(forMilliseconds: intervalMilliseconds)
        let request = Daemon_SubscribeStatusRequest.with { $0.interval = interval }

        return makeStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            try await client.subscribeStatus(
                request,
                metadata: metadata,
                options: streamOptions
            ) { response in
                try await Self.consume(
                    response.messages,
                    into: continuation,
                    transform: SingBoxStatusSnapshot.init
                )
            }
        }
    }

    func logStream() -> SingBoxGRPCStream<SingBoxLogBatch> {
        makeStream(bufferingPolicy: .bufferingNewest(32)) { continuation in
            try await client.subscribeLog(
                Google_Protobuf_Empty(),
                metadata: metadata,
                options: streamOptions
            ) { response in
                try await Self.consume(
                    response.messages,
                    into: continuation,
                    transform: SingBoxLogBatch.init
                )
            }
        }
    }

    func groupStream() -> SingBoxGRPCStream<SingBoxPolicyCatalog> {
        makeStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            try await client.subscribeGroups(
                Google_Protobuf_Empty(),
                metadata: metadata,
                options: streamOptions
            ) { response in
                try await Self.consume(
                    response.messages,
                    into: continuation,
                    transform: SingBoxPolicyCatalog.init
                )
            }
        }
    }

    func clashModeStatus() async throws -> SingBoxClashModeStatus {
        try await mapped {
            let response = try await client.getClashModeStatus(
                Google_Protobuf_Empty(),
                metadata: metadata,
                options: unaryOptions
            )
            return SingBoxClashModeStatus(response)
        }
    }

    func clashModeStream() -> SingBoxGRPCStream<String> {
        makeStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            try await client.subscribeClashMode(
                Google_Protobuf_Empty(),
                metadata: metadata,
                options: streamOptions
            ) { response in
                try await Self.consume(
                    response.messages,
                    into: continuation,
                    transform: { $0.mode }
                )
            }
        }
    }

    func setClashMode(_ mode: String) async throws {
        let request = Daemon_ClashMode.with { $0.mode = mode }
        try await mapped {
            _ = try await client.setClashMode(
                request,
                metadata: metadata,
                options: unaryOptions
            )
        }
    }

    func runURLTest(outboundTag: String) async throws {
        let request = Daemon_URLTestRequest.with { $0.outboundTag = outboundTag }
        try await mapped {
            _ = try await client.urlTest(
                request,
                metadata: metadata,
                options: unaryOptions
            )
        }
    }

    func selectOutbound(groupTag: String, outboundTag: String) async throws {
        let request = Daemon_SelectOutboundRequest.with {
            $0.groupTag = groupTag
            $0.outboundTag = outboundTag
        }
        try await mapped {
            _ = try await client.selectOutbound(
                request,
                metadata: metadata,
                options: unaryOptions
            )
        }
    }

    func connectionStream(
        intervalMilliseconds: Int64
    ) throws -> SingBoxGRPCStream<SingBoxConnectionEventBatch> {
        let interval = try Self.nanoseconds(forMilliseconds: intervalMilliseconds)
        let request = Daemon_SubscribeConnectionsRequest.with { $0.interval = interval }

        return makeStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            try await client.subscribeConnections(
                request,
                metadata: metadata,
                options: streamOptions
            ) { response in
                try await Self.consume(
                    response.messages,
                    into: continuation,
                    transform: SingBoxConnectionEventBatch.init
                )
            }
        }
    }

    func closeConnection(id: String) async throws {
        let request = Daemon_CloseConnectionRequest.with { $0.id = id }
        try await mapped {
            _ = try await client.closeConnection(
                request,
                metadata: metadata,
                options: unaryOptions
            )
        }
    }

    func closeAllConnections() async throws {
        try await mapped {
            _ = try await client.closeAllConnections(
                Google_Protobuf_Empty(),
                metadata: metadata,
                options: unaryOptions
            )
        }
    }

    func tailscaleStatusStream() -> SingBoxGRPCStream<SingBoxTailscaleStatus> {
        makeStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            try await client.subscribeTailscaleStatus(
                Google_Protobuf_Empty(),
                metadata: metadata,
                options: streamOptions
            ) { response in
                try await Self.consume(
                    response.messages,
                    into: continuation,
                    transform: SingBoxTailscaleStatus.init
                )
            }
        }
    }

    func setTailscaleExitNode(endpointTag: String, stableID: String) async throws {
        let request = Daemon_SetTailscaleExitNodeRequest.with {
            $0.endpointTag = endpointTag
            $0.stableID = stableID
        }
        try await mapped {
            _ = try await client.setTailscaleExitNode(
                request,
                metadata: metadata,
                options: unaryOptions
            )
        }
    }

    func tailscaleLogout(endpointTag: String) async throws {
        let request = Daemon_TailscaleLogoutRequest.with { $0.endpointTag = endpointTag }
        try await mapped {
            _ = try await client.tailscaleLogout(
                request,
                metadata: metadata,
                options: unaryOptions
            )
        }
    }

    private var unaryOptions: CallOptions {
        var options = CallOptions.defaults
        options.timeout = .seconds(20)
        options.waitForReady = true
        return options
    }

    private var streamOptions: CallOptions {
        var options = CallOptions.defaults
        options.waitForReady = true
        return options
    }

    private func mapped<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        do {
            return try await operation()
        } catch {
            throw Self.map(error)
        }
    }

    private func makeStream<Value: Sendable>(
        bufferingPolicy: AsyncThrowingStream<Value, Error>.Continuation.BufferingPolicy,
        operation: @Sendable @escaping (
            AsyncThrowingStream<Value, Error>.Continuation
        ) async throws -> Void
    ) -> SingBoxGRPCStream<Value> {
        let cancellation = SingBoxStreamCancellation()
        let base = AsyncThrowingStream(bufferingPolicy: bufferingPolicy) { continuation in
            let task = Task {
                defer { cancellation.markTerminated() }
                do {
                    try await operation(continuation)
                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: Self.map(error))
                    }
                }
            }
            cancellation.install(task)
            continuation.onTermination = { @Sendable _ in
                cancellation.cancel()
            }
        }
        return SingBoxGRPCStream(
            base: base,
            cancelOperation: { cancellation.cancel() },
            isTerminatedOperation: { cancellation.isTerminated }
        )
    }

    private static func nanoseconds(forMilliseconds value: Int64) throws -> Int64 {
        guard value > 0 else {
            throw SingBoxGRPCError.invalidIntervalMilliseconds(value)
        }
        let result = value.multipliedReportingOverflow(by: 1_000_000)
        guard !result.overflow else {
            throw SingBoxGRPCError.invalidIntervalMilliseconds(value)
        }
        return result.partialValue
    }

    private static func consume<Message: Sendable, Value: Sendable>(
        _ messages: RPCAsyncSequence<Message, any Error>,
        into continuation: AsyncThrowingStream<Value, Error>.Continuation,
        transform: @Sendable @escaping (Message) -> Value
    ) async throws {
        let completion = AsyncThrowingStream<Void, Error>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let consumer = Task {
            do {
                for try await message in messages {
                    continuation.yield(transform(message))
                }
                completion.continuation.finish()
            } catch {
                completion.continuation.finish(throwing: error)
            }
        }

        do {
            try await withTaskCancellationHandler {
                var iterator = completion.stream.makeAsyncIterator()
                _ = try await iterator.next()
            } onCancel: {
                consumer.cancel()
                completion.continuation.finish(throwing: CancellationError())
            }
        } catch {
            consumer.cancel()
            throw error
        }
    }

    private static func map(_ error: Error) -> Error {
        if let error = error as? SingBoxGRPCError {
            return error
        }
        if error is CancellationError {
            return CancellationError()
        }
        if let error = error as? RPCError {
            if error.code == .cancelled, Task.isCancelled {
                return CancellationError()
            }
            return SingBoxGRPCError.rpc(code: error.code.rawValue, message: error.message)
        }
        return SingBoxGRPCError.transport(String(describing: error))
    }
}

private final class SingBoxStreamCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var isCancelled = false
    private var terminated = false

    var isTerminated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return terminated
    }

    func install(_ task: Task<Void, Never>) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            task.cancel()
        } else {
            self.task = task
            lock.unlock()
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }

    func markTerminated() {
        lock.lock()
        terminated = true
        task = nil
        lock.unlock()
    }
}

enum SingBoxGRPCMetadata {
    static func make(credential: String?) -> Metadata {
        var metadata = Metadata()
        if let credential, !credential.isEmpty {
            metadata.addString("Bearer \(credential)", forKey: "authorization")
        }
        return metadata
    }
}

private extension SingBoxVersion {
    init(_ message: Daemon_Version) {
        self.init(version: message.version, apiVersion: message.apiVersion)
    }
}

private extension SingBoxLogBatch {
    init(_ message: Daemon_Log) {
        self.init(
            messages: message.messages.map {
                SingBoxLogMessage(
                    level: SingBoxLogLevel(rawValue: $0.level.rawValue),
                    message: $0.message
                )
            },
            reset: message.reset
        )
    }
}

private extension SingBoxStatusSnapshot {
    init(_ message: Daemon_Status) {
        self.init(
            memoryBytes: message.memory,
            goroutines: message.goroutines,
            connectionsIn: message.connectionsIn,
            connectionsOut: message.connectionsOut,
            trafficAvailable: message.trafficAvailable,
            uplinkBytesPerSecond: message.uplink,
            downlinkBytesPerSecond: message.downlink,
            uplinkTotalBytes: message.uplinkTotal,
            downlinkTotalBytes: message.downlinkTotal
        )
    }
}

private extension SingBoxPolicyCatalog {
    init(_ message: Daemon_Groups) {
        self.init(groups: message.group.map(SingBoxPolicyGroup.init))
    }
}

private extension SingBoxPolicyGroup {
    init(_ message: Daemon_Group) {
        self.init(
            tag: message.tag,
            type: message.type,
            selectable: message.selectable,
            selected: message.selected,
            isExpandedByController: message.isExpand,
            items: message.items.map(SingBoxPolicyNode.init)
        )
    }
}

private extension SingBoxPolicyNode {
    init(_ message: Daemon_GroupItem) {
        self.init(
            tag: message.tag,
            type: message.type,
            urlTestTimestamp: message.urlTestTime,
            urlTestDelayMilliseconds: message.urlTestDelay
        )
    }
}

private extension SingBoxClashModeStatus {
    init(_ message: Daemon_ClashModeStatus) {
        self.init(availableModes: message.modeList, currentMode: message.currentMode)
    }
}

private extension SingBoxConnectionEventBatch {
    init(_ message: Daemon_ConnectionEvents) {
        self.init(events: message.events.map(SingBoxConnectionEvent.init), reset: message.reset)
    }
}

private extension SingBoxConnectionEvent {
    init(_ message: Daemon_ConnectionEvent) {
        self.init(
            id: message.id,
            type: SingBoxConnectionEventType(rawValue: message.type.rawValue),
            connection: message.hasConnection ? SingBoxConnection(message.connection) : nil,
            uplinkDeltaBytes: message.uplinkDelta,
            downlinkDeltaBytes: message.downlinkDelta,
            closedAt: message.closedAt
        )
    }
}

private extension SingBoxConnection {
    init(_ message: Daemon_Connection) {
        self.init(
            id: message.id,
            inbound: message.inbound,
            inboundType: message.inboundType,
            ipVersion: message.ipVersion,
            network: message.network,
            source: message.source,
            destination: message.destination,
            domain: message.domain,
            protocolName: message.protocol,
            user: message.user,
            fromOutbound: message.fromOutbound,
            createdAt: message.createdAt,
            closedAt: message.closedAt,
            uplinkBytesPerSecond: message.uplink,
            downlinkBytesPerSecond: message.downlink,
            uplinkTotalBytes: message.uplinkTotal,
            downlinkTotalBytes: message.downlinkTotal,
            rule: message.rule,
            outbound: message.outbound,
            outboundType: message.outboundType,
            chain: message.chainList,
            process: message.hasProcessInfo ? SingBoxProcessInfo(message.processInfo) : nil
        )
    }
}

private extension SingBoxProcessInfo {
    init(_ message: Daemon_ProcessInfo) {
        self.init(
            processID: message.processID,
            userID: message.userID,
            userName: message.userName,
            processPath: message.processPath,
            packageNames: message.packageNames
        )
    }
}

private extension SingBoxTailscaleStatus {
    init(_ message: Daemon_TailscaleStatusUpdate) {
        self.init(endpoints: message.endpoints.map(SingBoxTailscaleEndpoint.init))
    }
}

private extension SingBoxTailscaleEndpoint {
    init(_ message: Daemon_TailscaleEndpointStatus) {
        self.init(
            endpointTag: message.endpointTag,
            backendState: message.backendState,
            authenticationURL: message.authURL,
            networkName: message.networkName,
            magicDNSSuffix: message.magicDnssuffix,
            selfPeer: message.hasSelf_p ? SingBoxTailscalePeer(message.self_p) : nil,
            userGroups: message.userGroups.map(SingBoxTailscaleUserGroup.init),
            exitNode: message.hasExitNode ? SingBoxTailscalePeer(message.exitNode) : nil,
            usesKeyAuthentication: message.keyAuth
        )
    }
}

private extension SingBoxTailscaleUserGroup {
    init(_ message: Daemon_TailscaleUserGroup) {
        self.init(
            userID: message.userID,
            loginName: message.loginName,
            displayName: message.displayName,
            profilePictureURL: message.profilePicURL,
            peers: message.peers.map(SingBoxTailscalePeer.init)
        )
    }
}

private extension SingBoxTailscalePeer {
    init(_ message: Daemon_TailscalePeer) {
        self.init(
            hostName: message.hostName,
            dnsName: message.dnsName,
            operatingSystem: message.os,
            ipAddresses: message.tailscaleIps,
            online: message.online,
            isExitNode: message.exitNode,
            canBeExitNode: message.exitNodeOption,
            active: message.active,
            receivedBytes: message.rxBytes,
            transmittedBytes: message.txBytes,
            keyExpiry: message.keyExpiry,
            stableID: message.stableID,
            expired: message.expired,
            sshHostKeys: message.sshHostKeys,
            isShareeNode: message.shareeNode,
            lastSeen: message.lastSeen
        )
    }
}
