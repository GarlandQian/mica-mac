import Foundation

public struct SingBoxVersion: Codable, Equatable, Sendable {
    public var version: String
    public var apiVersion: Int32

    public init(version: String, apiVersion: Int32) {
        self.version = version
        self.apiVersion = apiVersion
    }
}

public struct SingBoxLogLevel: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let panic = SingBoxLogLevel(rawValue: 0)
    public static let fatal = SingBoxLogLevel(rawValue: 1)
    public static let error = SingBoxLogLevel(rawValue: 2)
    public static let warning = SingBoxLogLevel(rawValue: 3)
    public static let info = SingBoxLogLevel(rawValue: 4)
    public static let debug = SingBoxLogLevel(rawValue: 5)
    public static let trace = SingBoxLogLevel(rawValue: 6)
}

public struct SingBoxLogMessage: Codable, Equatable, Sendable {
    public var level: SingBoxLogLevel
    public var message: String

    public init(level: SingBoxLogLevel, message: String) {
        self.level = level
        self.message = message
    }
}

public struct SingBoxLogBatch: Codable, Equatable, Sendable {
    public var messages: [SingBoxLogMessage]
    public var reset: Bool

    public init(messages: [SingBoxLogMessage], reset: Bool) {
        self.messages = messages
        self.reset = reset
    }
}

public struct SingBoxStatusSnapshot: Codable, Equatable, Sendable {
    public var memoryBytes: UInt64
    public var goroutines: Int32
    public var connectionsIn: Int32
    public var connectionsOut: Int32
    public var trafficAvailable: Bool
    public var uplinkBytesPerSecond: Int64
    public var downlinkBytesPerSecond: Int64
    public var uplinkTotalBytes: Int64
    public var downlinkTotalBytes: Int64

    public init(
        memoryBytes: UInt64,
        goroutines: Int32,
        connectionsIn: Int32,
        connectionsOut: Int32,
        trafficAvailable: Bool,
        uplinkBytesPerSecond: Int64,
        downlinkBytesPerSecond: Int64,
        uplinkTotalBytes: Int64,
        downlinkTotalBytes: Int64
    ) {
        self.memoryBytes = memoryBytes
        self.goroutines = goroutines
        self.connectionsIn = connectionsIn
        self.connectionsOut = connectionsOut
        self.trafficAvailable = trafficAvailable
        self.uplinkBytesPerSecond = uplinkBytesPerSecond
        self.downlinkBytesPerSecond = downlinkBytesPerSecond
        self.uplinkTotalBytes = uplinkTotalBytes
        self.downlinkTotalBytes = downlinkTotalBytes
    }
}

public struct SingBoxPolicyCatalog: Codable, Equatable, Sendable {
    public var groups: [SingBoxPolicyGroup]

    public init(groups: [SingBoxPolicyGroup]) {
        self.groups = groups
    }
}

public struct SingBoxPolicyGroup: Codable, Equatable, Sendable, Identifiable {
    public var id: String { tag }
    public var tag: String
    public var type: String
    public var selectable: Bool
    public var selected: String
    public var isExpandedByController: Bool
    public var items: [SingBoxPolicyNode]

    public init(
        tag: String,
        type: String,
        selectable: Bool,
        selected: String,
        isExpandedByController: Bool,
        items: [SingBoxPolicyNode]
    ) {
        self.tag = tag
        self.type = type
        self.selectable = selectable
        self.selected = selected
        self.isExpandedByController = isExpandedByController
        self.items = items
    }
}

public struct SingBoxPolicyNode: Codable, Equatable, Sendable, Identifiable {
    public var id: String { tag }
    public var tag: String
    public var type: String
    public var urlTestTimestamp: Int64
    public var urlTestDelayMilliseconds: Int32

    public init(
        tag: String,
        type: String,
        urlTestTimestamp: Int64,
        urlTestDelayMilliseconds: Int32
    ) {
        self.tag = tag
        self.type = type
        self.urlTestTimestamp = urlTestTimestamp
        self.urlTestDelayMilliseconds = urlTestDelayMilliseconds
    }
}

public struct SingBoxClashModeStatus: Codable, Equatable, Sendable {
    public var availableModes: [String]
    public var currentMode: String

    public init(availableModes: [String], currentMode: String) {
        self.availableModes = availableModes
        self.currentMode = currentMode
    }
}

public struct SingBoxConnectionEventType: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let new = SingBoxConnectionEventType(rawValue: 0)
    public static let update = SingBoxConnectionEventType(rawValue: 1)
    public static let closed = SingBoxConnectionEventType(rawValue: 2)
}

public struct SingBoxConnectionEventBatch: Codable, Equatable, Sendable {
    public var events: [SingBoxConnectionEvent]
    public var reset: Bool

    public init(events: [SingBoxConnectionEvent], reset: Bool) {
        self.events = events
        self.reset = reset
    }
}

public struct SingBoxConnectionEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var type: SingBoxConnectionEventType
    public var connection: SingBoxConnection?
    public var uplinkDeltaBytes: Int64
    public var downlinkDeltaBytes: Int64
    public var closedAt: Int64

    public init(
        id: String,
        type: SingBoxConnectionEventType,
        connection: SingBoxConnection?,
        uplinkDeltaBytes: Int64,
        downlinkDeltaBytes: Int64,
        closedAt: Int64
    ) {
        self.id = id
        self.type = type
        self.connection = connection
        self.uplinkDeltaBytes = uplinkDeltaBytes
        self.downlinkDeltaBytes = downlinkDeltaBytes
        self.closedAt = closedAt
    }
}

public struct SingBoxConnection: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var inbound: String
    public var inboundType: String
    public var ipVersion: Int32
    public var network: String
    public var source: String
    public var destination: String
    public var domain: String
    public var protocolName: String
    public var user: String
    public var fromOutbound: String
    public var createdAt: Int64
    public var closedAt: Int64
    public var uplinkBytesPerSecond: Int64
    public var downlinkBytesPerSecond: Int64
    public var uplinkTotalBytes: Int64
    public var downlinkTotalBytes: Int64
    public var rule: String
    public var outbound: String
    public var outboundType: String
    public var chain: [String]
    public var process: SingBoxProcessInfo?

    public init(
        id: String,
        inbound: String,
        inboundType: String,
        ipVersion: Int32,
        network: String,
        source: String,
        destination: String,
        domain: String,
        protocolName: String,
        user: String,
        fromOutbound: String,
        createdAt: Int64,
        closedAt: Int64,
        uplinkBytesPerSecond: Int64,
        downlinkBytesPerSecond: Int64,
        uplinkTotalBytes: Int64,
        downlinkTotalBytes: Int64,
        rule: String,
        outbound: String,
        outboundType: String,
        chain: [String],
        process: SingBoxProcessInfo?
    ) {
        self.id = id
        self.inbound = inbound
        self.inboundType = inboundType
        self.ipVersion = ipVersion
        self.network = network
        self.source = source
        self.destination = destination
        self.domain = domain
        self.protocolName = protocolName
        self.user = user
        self.fromOutbound = fromOutbound
        self.createdAt = createdAt
        self.closedAt = closedAt
        self.uplinkBytesPerSecond = uplinkBytesPerSecond
        self.downlinkBytesPerSecond = downlinkBytesPerSecond
        self.uplinkTotalBytes = uplinkTotalBytes
        self.downlinkTotalBytes = downlinkTotalBytes
        self.rule = rule
        self.outbound = outbound
        self.outboundType = outboundType
        self.chain = chain
        self.process = process
    }
}

public struct SingBoxProcessInfo: Codable, Equatable, Sendable {
    public var processID: UInt32
    public var userID: Int32
    public var userName: String
    public var processPath: String
    public var packageNames: [String]

    public init(
        processID: UInt32,
        userID: Int32,
        userName: String,
        processPath: String,
        packageNames: [String]
    ) {
        self.processID = processID
        self.userID = userID
        self.userName = userName
        self.processPath = processPath
        self.packageNames = packageNames
    }
}

public struct SingBoxTailscaleStatus: Codable, Equatable, Sendable {
    public var endpoints: [SingBoxTailscaleEndpoint]

    public init(endpoints: [SingBoxTailscaleEndpoint]) {
        self.endpoints = endpoints
    }
}

public struct SingBoxTailscaleEndpoint: Codable, Equatable, Sendable, Identifiable {
    public var id: String { endpointTag }
    public var endpointTag: String
    public var backendState: String
    public var authenticationURL: String
    public var networkName: String
    public var magicDNSSuffix: String
    public var selfPeer: SingBoxTailscalePeer?
    public var userGroups: [SingBoxTailscaleUserGroup]
    public var exitNode: SingBoxTailscalePeer?
    public var usesKeyAuthentication: Bool

    public init(
        endpointTag: String,
        backendState: String,
        authenticationURL: String,
        networkName: String,
        magicDNSSuffix: String,
        selfPeer: SingBoxTailscalePeer?,
        userGroups: [SingBoxTailscaleUserGroup],
        exitNode: SingBoxTailscalePeer?,
        usesKeyAuthentication: Bool
    ) {
        self.endpointTag = endpointTag
        self.backendState = backendState
        self.authenticationURL = authenticationURL
        self.networkName = networkName
        self.magicDNSSuffix = magicDNSSuffix
        self.selfPeer = selfPeer
        self.userGroups = userGroups
        self.exitNode = exitNode
        self.usesKeyAuthentication = usesKeyAuthentication
    }
}

public struct SingBoxTailscaleUserGroup: Codable, Equatable, Sendable, Identifiable {
    public var id: Int64 { userID }
    public var userID: Int64
    public var loginName: String
    public var displayName: String
    public var profilePictureURL: String
    public var peers: [SingBoxTailscalePeer]

    public init(
        userID: Int64,
        loginName: String,
        displayName: String,
        profilePictureURL: String,
        peers: [SingBoxTailscalePeer]
    ) {
        self.userID = userID
        self.loginName = loginName
        self.displayName = displayName
        self.profilePictureURL = profilePictureURL
        self.peers = peers
    }
}

public struct SingBoxTailscalePeer: Codable, Equatable, Sendable, Identifiable {
    public var id: String { stableID }
    public var hostName: String
    public var dnsName: String
    public var operatingSystem: String
    public var ipAddresses: [String]
    public var online: Bool
    public var isExitNode: Bool
    public var canBeExitNode: Bool
    public var active: Bool
    public var receivedBytes: Int64
    public var transmittedBytes: Int64
    public var keyExpiry: Int64
    public var stableID: String
    public var expired: Bool
    public var sshHostKeys: [String]
    public var isShareeNode: Bool
    public var lastSeen: Int64

    public init(
        hostName: String,
        dnsName: String,
        operatingSystem: String,
        ipAddresses: [String],
        online: Bool,
        isExitNode: Bool,
        canBeExitNode: Bool,
        active: Bool,
        receivedBytes: Int64,
        transmittedBytes: Int64,
        keyExpiry: Int64,
        stableID: String,
        expired: Bool,
        sshHostKeys: [String],
        isShareeNode: Bool,
        lastSeen: Int64
    ) {
        self.hostName = hostName
        self.dnsName = dnsName
        self.operatingSystem = operatingSystem
        self.ipAddresses = ipAddresses
        self.online = online
        self.isExitNode = isExitNode
        self.canBeExitNode = canBeExitNode
        self.active = active
        self.receivedBytes = receivedBytes
        self.transmittedBytes = transmittedBytes
        self.keyExpiry = keyExpiry
        self.stableID = stableID
        self.expired = expired
        self.sshHostKeys = sshHostKeys
        self.isShareeNode = isShareeNode
        self.lastSeen = lastSeen
    }
}

public enum SingBoxGRPCError: Error, Equatable, Sendable {
    case invalidIntervalMilliseconds(Int64)
    case rpc(code: Int, message: String)
    case transport(String)
}

extension SingBoxGRPCError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidIntervalMilliseconds(let value):
            return "Invalid sing-box stream interval: \(value) ms"
        case .rpc(let code, let message):
            return "sing-box RPC failed (\(code)): \(message)"
        case .transport(let message):
            return "sing-box transport failed: \(message)"
        }
    }
}
