import Foundation

public struct VersionResponse: Codable, Equatable, Sendable {
    public var version: String
    public var premium: Bool?

    public init(version: String, premium: Bool? = nil) {
        self.version = version
        self.premium = premium
    }
}

public struct ClashCompatibleRootResponse: Codable, Equatable, Sendable {
    public var appVersion: String?
    public var hello: String?
}

public struct ConfigResponse: Codable, Equatable, Sendable {
    public var mode: String?
    public var modeOptions: [String]?
    public var allowLan: Bool?
    public var logLevel: String?
    public var port: Int?
    public var socksPort: Int?
    public var redirPort: Int?
    public var mixedPort: Int?
    public var ipv6: Bool?
    public var tcpConcurrent: Bool?
    public var tun: TunConfig?

    enum CodingKeys: String, CodingKey {
        case mode
        case modeOptions = "mode-options"
        case allowLan = "allow-lan"
        case logLevel = "log-level"
        case port
        case socksPort = "socks-port"
        case redirPort = "redir-port"
        case mixedPort = "mixed-port"
        case ipv6
        case tcpConcurrent = "tcp-concurrent"
        case tun
    }
}

public struct TunConfig: Codable, Equatable, Sendable {
    public var enable: Bool?

    public init(enable: Bool? = nil) {
        self.enable = enable
    }
}

public struct MihomoConfigPatch: Encodable, Equatable, Sendable {
    public var mode: String?
    public var logLevel: String?
    public var allowLan: Bool?
    public var ipv6: Bool?
    public var tcpConcurrent: Bool?
    public var tun: TunConfig?
    public var port: Int?
    public var socksPort: Int?
    public var redirPort: Int?
    public var mixedPort: Int?

    public init(
        mode: String? = nil,
        logLevel: String? = nil,
        allowLan: Bool? = nil,
        ipv6: Bool? = nil,
        tcpConcurrent: Bool? = nil,
        tunEnabled: Bool? = nil,
        port: Int? = nil,
        socksPort: Int? = nil,
        redirPort: Int? = nil,
        mixedPort: Int? = nil
    ) {
        self.mode = mode
        self.logLevel = logLevel
        self.allowLan = allowLan
        self.ipv6 = ipv6
        self.tcpConcurrent = tcpConcurrent
        self.tun = tunEnabled.map { TunConfig(enable: $0) }
        self.port = port
        self.socksPort = socksPort
        self.redirPort = redirPort
        self.mixedPort = mixedPort
    }

    enum CodingKeys: String, CodingKey {
        case mode
        case logLevel = "log-level"
        case allowLan = "allow-lan"
        case ipv6
        case tcpConcurrent = "tcp-concurrent"
        case tun
        case port
        case socksPort = "socks-port"
        case redirPort = "redir-port"
        case mixedPort = "mixed-port"
    }
}

public struct ProxiesResponse: Decodable, Equatable, Sendable {
    public var proxies: [String: ProxySnapshot]
    public var proxyOrder: [String]

    public var policyGroups: [ProxySnapshot] {
        var seen: Set<String> = []
        var orderedGroups = proxyOrder.compactMap { name -> ProxySnapshot? in
            guard seen.insert(name).inserted,
                  let proxy = proxies[name],
                  !proxy.all.isEmpty else {
                return nil
            }

            return proxy
        }

        let remainingGroups = proxyOrder.isEmpty
            ? proxies.values.filter { !seen.contains($0.name) && !$0.all.isEmpty }
            : []
        if !remainingGroups.isEmpty {
            orderedGroups.append(contentsOf: remainingGroups)
        }

        return orderedGroups
    }

    public init(proxies: [String: ProxySnapshot], proxyOrder: [String]? = nil) {
        self.proxies = proxies
        self.proxyOrder = proxyOrder ?? proxies.keys.sorted()
    }

    public static func decodePreservingProxyOrder(
        from data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> ProxiesResponse {
        var response = try decoder.decode(ProxiesResponse.self, from: data)
        let sourceOrder = JSONKeyOrderScanner.objectKeyOrder(for: "proxies", in: data)
        if !sourceOrder.isEmpty {
            response.proxyOrder = sourceOrder
        }
        return response
    }

    public init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: CodingKeys.self)
        let container = try root.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .proxies)
        var decoded: [String: ProxySnapshot] = [:]
        var order: [String] = []

        for key in container.allKeys {
            let raw = try container.decode(RawProxySnapshot.self, forKey: key)
            decoded[key.stringValue] = ProxySnapshot(name: key.stringValue, raw: raw)
            order.append(key.stringValue)
        }

        proxies = decoded
        proxyOrder = order
    }

    enum CodingKeys: String, CodingKey {
        case proxies
    }

}

public struct SmartNodeRankSnapshot: Codable, Equatable, Sendable {
    public var name: String
    public var rank: String

    public init(name: String, rank: String) {
        self.name = name
        self.rank = rank
    }

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case rank = "Rank"
    }
}

public struct SmartWeightsResponse: Codable, Equatable, Sendable {
    public var message: String?
    public var weights: [String: [SmartNodeRankSnapshot]]

    public init(
        message: String? = nil,
        weights: [String: [SmartNodeRankSnapshot]]
    ) {
        self.message = message
        self.weights = weights
    }
}

public struct SmartGroupWeightsResponse: Codable, Equatable, Sendable {
    public var message: String?
    public var weights: [SmartNodeRankSnapshot]

    public init(message: String? = nil, weights: [SmartNodeRankSnapshot]) {
        self.message = message
        self.weights = weights
    }
}

private struct JSONKeyOrderScanner {
    private let bytes: [UInt8]
    private var index = 0
    private let decoder = JSONDecoder()

    static func objectKeyOrder(for key: String, in data: Data) -> [String] {
        // The response has already passed JSONDecoder validation. Walk UTF-8
        // punctuation without decoding strings inside values a second time.
        var scanner = JSONKeyOrderScanner(bytes: Array(data))
        scanner.skipWhitespace()
        guard scanner.consume(123) else {
            return []
        }

        while !scanner.isAtEnd {
            scanner.skipWhitespace()
            if scanner.consume(125) {
                return []
            }
            guard let rootKey = scanner.readString() else {
                return []
            }
            scanner.skipWhitespace()
            guard scanner.consume(58) else {
                return []
            }
            scanner.skipWhitespace()
            if rootKey == key {
                return scanner.readObjectKeys()
            }
            scanner.skipValue()
            scanner.skipWhitespace()
            _ = scanner.consume(44)
        }

        return []
    }

    private var isAtEnd: Bool {
        index >= bytes.count
    }

    private mutating func skipWhitespace() {
        while !isAtEnd {
            switch bytes[index] {
            case 9, 10, 13, 32: index += 1
            default: return
            }
        }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard !isAtEnd, bytes[index] == byte else {
            return false
        }

        index += 1
        return true
    }

    private mutating func readObjectKeys() -> [String] {
        guard consume(123) else {
            return []
        }

        var keys: [String] = []
        while !isAtEnd {
            skipWhitespace()
            if consume(125) {
                return keys
            }
            guard let key = readString() else {
                return keys
            }
            keys.append(key)
            skipWhitespace()
            guard consume(58) else {
                return keys
            }
            skipValue()
            skipWhitespace()
            if consume(44) {
                continue
            }
            if consume(125) {
                return keys
            }
        }

        return keys
    }

    private mutating func skipValue() {
        skipWhitespace()
        guard !isAtEnd else {
            return
        }

        var depth = 0
        while !isAtEnd {
            switch bytes[index] {
            case 34:
                _ = stringToken()
                if depth == 0 { return }
            case 123, 91:
                depth += 1
                index += 1
            case 125, 93:
                guard depth > 0 else { return }
                depth -= 1
                index += 1
                if depth == 0 { return }
            case 44 where depth == 0:
                return
            default:
                index += 1
            }
        }
    }

    private mutating func readString() -> String? {
        guard let token = stringToken() else { return nil }
        if !token.escaped {
            return String(decoding: bytes[(token.range.lowerBound + 1)..<(token.range.upperBound - 1)], as: UTF8.self)
        }
        return try? decoder.decode(String.self, from: Data(bytes[token.range]))
    }

    private mutating func stringToken() -> (range: Range<Int>, escaped: Bool)? {
        guard consume(34) else { return nil }
        let tokenStart = index - 1
        var escaped = false
        while !isAtEnd {
            let byte = bytes[index]
            index += 1
            if byte == 92 {
                escaped = true
                guard !isAtEnd else { return nil }
                index += 1
            } else if byte == 34 {
                return (tokenStart..<index, escaped)
            }
        }

        return nil
    }
}

public struct ProxySnapshot: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var type: String
    public var now: String?
    public var all: [String]
    public var alive: Bool?
    public var history: [ProxyDelayHistorySnapshot]
    public var icon: String?
    public var testURL: String?
    public var providerName: String?
    public var fixed: String?
    public var interfaceName: String?
    public var udp: Bool?
    public var uot: Bool?
    public var xudp: Bool?
    public var tfo: Bool?
    public var mptcp: Bool?
    public var smux: Bool?
    public var hidden: Bool?
    public var metadata: [String: MihomoJSONValue]

    public init(
        name: String,
        type: String,
        now: String? = nil,
        all: [String] = [],
        alive: Bool? = nil,
        history: [ProxyDelayHistorySnapshot] = [],
        icon: String? = nil,
        testURL: String? = nil,
        providerName: String? = nil,
        fixed: String? = nil,
        interfaceName: String? = nil,
        udp: Bool? = nil,
        uot: Bool? = nil,
        xudp: Bool? = nil,
        tfo: Bool? = nil,
        mptcp: Bool? = nil,
        smux: Bool? = nil,
        hidden: Bool? = nil,
        metadata: [String: MihomoJSONValue] = [:]
    ) {
        self.name = name
        self.type = type
        self.now = now
        self.all = all
        self.alive = alive
        self.history = history
        self.icon = icon
        self.testURL = testURL
        self.providerName = providerName
        self.fixed = fixed
        self.interfaceName = interfaceName
        self.udp = udp
        self.uot = uot
        self.xudp = xudp
        self.tfo = tfo
        self.mptcp = mptcp
        self.smux = smux
        self.hidden = hidden
        self.metadata = metadata
    }

    fileprivate init(name: String, raw: RawProxySnapshot) {
        self.init(
            name: name,
            type: raw.type,
            now: raw.now,
            all: raw.all,
            alive: raw.alive,
            history: raw.history,
            icon: raw.icon,
            testURL: raw.testURL,
            providerName: raw.providerName,
            fixed: raw.fixed,
            interfaceName: raw.interfaceName,
            udp: raw.udp,
            uot: raw.uot,
            xudp: raw.xudp,
            tfo: raw.tfo,
            mptcp: raw.mptcp,
            smux: raw.smux,
            hidden: raw.hidden,
            metadata: raw.metadata
        )
    }

    public var latestDelay: Int? {
        history.last(where: { $0.delay != nil })?.delay
    }

    public var enabledTransportNames: [String] {
        [
            udp == true ? "UDP" : nil,
            uot == true ? "UOT" : nil,
            xudp == true ? "XUDP" : nil,
            tfo == true ? "TFO" : nil,
            mptcp == true ? "MPTCP" : nil,
            smux == true ? "SMUX" : nil,
        ].compactMap { $0 }
    }
}

private struct RawProxySnapshot: Decodable {
    var type: String
    var now: String?
    var all: [String]
    var alive: Bool?
    var history: [ProxyDelayHistorySnapshot]
    var icon: String?
    var testURL: String?
    var providerName: String?
    var fixed: String?
    var interfaceName: String?
    var udp: Bool?
    var uot: Bool?
    var xudp: Bool?
    var tfo: Bool?
    var mptcp: Bool?
    var smux: Bool?
    var hidden: Bool?
    var metadata: [String: MihomoJSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var decodedType: String?
        var decodedNow: String?
        var decodedAll: [String]?
        var decodedAlive: Bool?
        var decodedHistory: [ProxyDelayHistorySnapshot]?
        var decodedIcon: String?
        var decodedTestURL: String?
        var decodedTester: String?
        var decodedProviderName: String?
        var decodedFixed: String?
        var decodedInterfaceName: String?
        var decodedUDP: Bool?
        var decodedUOT: Bool?
        var decodedXUDP: Bool?
        var decodedTFO: Bool?
        var decodedMPTCP: Bool?
        var decodedSMUX: Bool?
        var decodedHidden: Bool?
        var metadata: [String: MihomoJSONValue] = [:]
        metadata.reserveCapacity(container.allKeys.count)

        for key in container.allKeys {
            let fieldName = key.stringValue
            switch fieldName {
            case "type":
                let field = try container.decodeProxyString(forKey: key)
                decodedType = field.value
                metadata[fieldName] = field.rawValue
            case "now":
                let field = try container.decodeProxyString(forKey: key)
                decodedNow = field.value
                metadata[fieldName] = field.rawValue
            case "all":
                let field = try container.decodeProxyStringArray(forKey: key)
                decodedAll = field.value
                metadata[fieldName] = field.rawValue
            case "alive":
                let field = try container.decodeProxyBool(forKey: key)
                decodedAlive = field.value
                metadata[fieldName] = field.rawValue
            case "history":
                let field = try container.decodeProxyHistory(forKey: key)
                decodedHistory = field.value
                metadata[fieldName] = field.rawValue
            case "icon":
                let field = try container.decodeProxyString(forKey: key)
                decodedIcon = field.value
                metadata[fieldName] = field.rawValue
            case "testUrl":
                let field = try container.decodeProxyString(forKey: key)
                decodedTestURL = field.value
                metadata[fieldName] = field.rawValue
            case "tester":
                let field = try container.decodeProxyString(forKey: key)
                decodedTester = field.value
                metadata[fieldName] = field.rawValue
            case "provider-name":
                let field = try container.decodeProxyString(forKey: key)
                decodedProviderName = field.value
                metadata[fieldName] = field.rawValue
            case "fixed":
                let field = try container.decodeProxyString(forKey: key)
                decodedFixed = field.value
                metadata[fieldName] = field.rawValue
            case "interface":
                let field = try container.decodeProxyString(forKey: key)
                decodedInterfaceName = field.value
                metadata[fieldName] = field.rawValue
            case "udp":
                let field = try container.decodeProxyBool(forKey: key)
                decodedUDP = field.value
                metadata[fieldName] = field.rawValue
            case "uot":
                let field = try container.decodeProxyBool(forKey: key)
                decodedUOT = field.value
                metadata[fieldName] = field.rawValue
            case "xudp":
                let field = try container.decodeProxyBool(forKey: key)
                decodedXUDP = field.value
                metadata[fieldName] = field.rawValue
            case "tfo":
                let field = try container.decodeProxyBool(forKey: key)
                decodedTFO = field.value
                metadata[fieldName] = field.rawValue
            case "mptcp":
                let field = try container.decodeProxyBool(forKey: key)
                decodedMPTCP = field.value
                metadata[fieldName] = field.rawValue
            case "smux":
                let field = try container.decodeProxyBool(forKey: key)
                decodedSMUX = field.value
                metadata[fieldName] = field.rawValue
            case "hidden":
                let field = try container.decodeProxyBool(forKey: key)
                decodedHidden = field.value
                metadata[fieldName] = field.rawValue
            default:
                metadata[fieldName] = try container.decode(
                    MihomoJSONValue.self,
                    forKey: key
                )
            }
        }

        type = decodedType ?? ""
        now = decodedNow
        all = decodedAll ?? []
        alive = decodedAlive
        history = decodedHistory ?? []
        icon = decodedIcon
        testURL = decodedTestURL ?? decodedTester
        providerName = decodedProviderName
        fixed = decodedFixed
        interfaceName = decodedInterfaceName
        udp = decodedUDP
        uot = decodedUOT
        xudp = decodedXUDP
        tfo = decodedTFO
        mptcp = decodedMPTCP
        smux = decodedSMUX
        hidden = decodedHidden
        self.metadata = metadata
    }
}

private struct RawProxyDecodedField<Value> {
    var value: Value?
    var rawValue: MihomoJSONValue
}

private struct RawProxyHistoryEntry: Decodable {
    var snapshot: ProxyDelayHistorySnapshot
    var rawValue: MihomoJSONValue

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var decodedTime: String?
        var decodedDelay: Int?
        var decodedMeanDelay: Int?
        var decodedLegacyMeanDelay: Int?
        var metadata: [String: MihomoJSONValue] = [:]
        metadata.reserveCapacity(container.allKeys.count)

        for key in container.allKeys {
            let fieldName = key.stringValue
            switch fieldName {
            case "time":
                let field = try container.decodeProxyString(forKey: key)
                decodedTime = field.value
                metadata[fieldName] = field.rawValue
            case "delay":
                let field = try container.decodeProxyInt(forKey: key)
                decodedDelay = field.value
                metadata[fieldName] = field.rawValue
            case "meanDelay":
                let field = try container.decodeProxyInt(forKey: key)
                decodedMeanDelay = field.value
                metadata[fieldName] = field.rawValue
            case "mean-delay":
                let field = try container.decodeProxyInt(forKey: key)
                decodedLegacyMeanDelay = field.value
                metadata[fieldName] = field.rawValue
            default:
                metadata[fieldName] = try container.decode(
                    MihomoJSONValue.self,
                    forKey: key
                )
            }
        }

        snapshot = ProxyDelayHistorySnapshot(
            time: decodedTime,
            delay: decodedDelay,
            meanDelay: decodedMeanDelay ?? decodedLegacyMeanDelay
        )
        rawValue = .object(metadata)
    }
}

private extension KeyedDecodingContainer where Key == DynamicCodingKey {
    func decodeProxyString(forKey key: Key) throws -> RawProxyDecodedField<String> {
        if try decodeNil(forKey: key) {
            return RawProxyDecodedField(value: nil, rawValue: .null)
        }
        if let value = try? decode(String.self, forKey: key) {
            return RawProxyDecodedField(value: value, rawValue: .string(value))
        }

        let rawValue = try decode(MihomoJSONValue.self, forKey: key)
        return RawProxyDecodedField(value: rawValue.stringValue, rawValue: rawValue)
    }

    func decodeProxyBool(forKey key: Key) throws -> RawProxyDecodedField<Bool> {
        if try decodeNil(forKey: key) {
            return RawProxyDecodedField(value: nil, rawValue: .null)
        }
        if let value = try? decode(Bool.self, forKey: key) {
            return RawProxyDecodedField(value: value, rawValue: .bool(value))
        }

        let rawValue = try decode(MihomoJSONValue.self, forKey: key)
        return RawProxyDecodedField(value: rawValue.boolValue, rawValue: rawValue)
    }

    func decodeProxyInt(forKey key: Key) throws -> RawProxyDecodedField<Int> {
        if try decodeNil(forKey: key) {
            return RawProxyDecodedField(value: nil, rawValue: .null)
        }
        if let value = try? decode(Double.self, forKey: key) {
            let rawValue = MihomoJSONValue.number(value)
            return RawProxyDecodedField(value: rawValue.intValue, rawValue: rawValue)
        }
        if let value = try? decode(String.self, forKey: key) {
            return RawProxyDecodedField(value: Int(value), rawValue: .string(value))
        }

        let rawValue = try decode(MihomoJSONValue.self, forKey: key)
        return RawProxyDecodedField(value: rawValue.intValue, rawValue: rawValue)
    }

    func decodeProxyStringArray(
        forKey key: Key
    ) throws -> RawProxyDecodedField<[String]> {
        if try decodeNil(forKey: key) {
            return RawProxyDecodedField(value: nil, rawValue: .null)
        }
        if let value = try? decode([String].self, forKey: key) {
            return RawProxyDecodedField(
                value: value,
                rawValue: .array(value.map(MihomoJSONValue.string))
            )
        }

        let rawValue = try decode(MihomoJSONValue.self, forKey: key)
        return RawProxyDecodedField(
            value: rawValue.stringArrayValue,
            rawValue: rawValue
        )
    }

    func decodeProxyHistory(
        forKey key: Key
    ) throws -> RawProxyDecodedField<[ProxyDelayHistorySnapshot]> {
        if try decodeNil(forKey: key) {
            return RawProxyDecodedField(value: nil, rawValue: .null)
        }
        if let value = try? decode([RawProxyHistoryEntry].self, forKey: key) {
            return RawProxyDecodedField(
                value: value.map(\.snapshot),
                rawValue: .array(value.map(\.rawValue))
            )
        }

        let rawValue = try decode(MihomoJSONValue.self, forKey: key)
        return RawProxyDecodedField(
            value: rawValue.arrayValue?.compactMap(
                ProxyDelayHistorySnapshot.init(rawValue:)
            ),
            rawValue: rawValue
        )
    }
}

public struct ProxyDelayHistorySnapshot: Codable, Equatable, Sendable {
    public var time: String?
    public var delay: Int?
    public var meanDelay: Int?

    public init(time: String? = nil, delay: Int? = nil, meanDelay: Int? = nil) {
        self.time = time
        self.delay = delay
        self.meanDelay = meanDelay
    }

    fileprivate init?(rawValue: MihomoJSONValue) {
        guard let object = rawValue.objectValue else { return nil }
        time = object["time"]?.stringValue
        delay = object["delay"]?.intValue
        meanDelay = object["meanDelay"]?.intValue ?? object["mean-delay"]?.intValue
    }
}

public struct TrafficSnapshot: Codable, Equatable, Sendable {
    public var upload: Int
    public var download: Int

    public init(upload: Int, download: Int) {
        self.upload = upload
        self.download = download
    }
}

public struct LiveTrafficEvent: Codable, Equatable, Sendable {
    public var upload: Int
    public var download: Int

    public init(upload: Int, download: Int) {
        self.upload = upload
        self.download = download
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let upload = try container.decodeIfPresent(Int.self, forKey: .upload)
            ?? container.decodeIfPresent(Int.self, forKey: .up)
            ?? 0
        let download = try container.decodeIfPresent(Int.self, forKey: .download)
            ?? container.decodeIfPresent(Int.self, forKey: .down)
            ?? 0
        self.init(upload: upload, download: download)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(upload, forKey: .upload)
        try container.encode(download, forKey: .download)
    }

    enum CodingKeys: String, CodingKey {
        case upload
        case download
        case up
        case down
    }
}

public indirect enum MihomoJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: MihomoJSONValue])
    case array([MihomoJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([MihomoJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: MihomoJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public typealias ControllerJSONValue = MihomoJSONValue

private extension MihomoJSONValue {
    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        switch self {
        case .number(let value):
            guard value.isFinite else { return nil }
            return Int(value.rounded())
        case .string(let value):
            return Int(value)
        default:
            return nil
        }
    }

    var objectValue: [String: MihomoJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [MihomoJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var stringArrayValue: [String]? {
        arrayValue?.compactMap(\.stringValue)
    }

    var scalarStringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            guard value.isFinite else { return nil }
            if value.rounded() == value,
               value >= Double(Int.min),
               value <= Double(Int.max) {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return String(value)
        case .object, .array, .null:
            return nil
        }
    }

    var scalarStringArrayValue: [String]? {
        arrayValue?.compactMap(\.scalarStringValue)
    }

    var counterValue: Int? {
        intValue ?? objectValue?["total"]?.intValue
    }
}

public struct LogMessage: Codable, Equatable, Sendable {
    public var type: String
    public var payload: String
    public var time: String?
    public var level: String?
    public var message: String?
    public var fields: MihomoJSONValue?

    public init(
        type: String,
        payload: String,
        time: String? = nil,
        level: String? = nil,
        message: String? = nil,
        fields: MihomoJSONValue? = nil
    ) {
        self.type = type
        self.payload = payload
        self.time = time
        self.level = level
        self.message = message
        self.fields = fields
    }

    enum CodingKeys: String, CodingKey {
        case type
        case payload
        case time
        case level
        case message
        case fields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedType = try container.decodeIfPresent(String.self, forKey: .type)
        let decodedLevel = try container.decodeIfPresent(String.self, forKey: .level)
        let decodedPayload = try container.decodeIfPresent(String.self, forKey: .payload)
        let decodedMessage = try container.decodeIfPresent(String.self, forKey: .message)

        type = decodedType ?? decodedLevel ?? "info"
        payload = decodedPayload ?? decodedMessage ?? ""
        time = try container.decodeIfPresent(String.self, forKey: .time)
        level = decodedLevel
        message = decodedMessage
        fields = try container.decodeIfPresent(MihomoJSONValue.self, forKey: .fields)
    }
}

public struct MemoryResponse: Codable, Equatable, Sendable {
    public var inuse: Int?
    public var oslimit: Int?

    public init(inuse: Int? = nil, oslimit: Int? = nil) {
        self.inuse = inuse
        self.oslimit = oslimit
    }
}

public struct ConnectionsResponse: Codable, Equatable, Sendable {
    public var uploadTotal: Int?
    public var downloadTotal: Int?
    public var memory: Int?
    public var connections: [ConnectionSnapshot]

    public init(uploadTotal: Int? = nil, downloadTotal: Int? = nil, memory: Int? = nil, connections: [ConnectionSnapshot]) {
        self.uploadTotal = uploadTotal
        self.downloadTotal = downloadTotal
        self.memory = memory
        self.connections = connections
    }

    enum CodingKeys: String, CodingKey {
        case uploadTotal = "uploadTotal"
        case downloadTotal = "downloadTotal"
        case memory
        case connections
    }
}

public struct GroupDelayResponse: Codable, Equatable, Sendable {
    public var delay: [String: Int]

    public init(delay: [String: Int]) {
        self.delay = delay
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        delay = try container.decode([String: Int].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(delay)
    }
}

public struct ProxyDelayResponse: Codable, Equatable, Sendable {
    public var delay: Int

    public init(delay: Int) {
        self.delay = delay
    }
}

public struct RulesResponse: Codable, Equatable, Sendable {
    public var rules: [RuleSnapshot]

    public init(rules: [RuleSnapshot]) {
        self.rules = rules
    }
}

public struct RuleSnapshot: Codable, Identifiable, Equatable, Sendable {
    public var id: String {
        [index.map(String.init), type, payload, proxy]
            .compactMap { $0 }
            .joined(separator: ":")
    }

    public var index: Int?
    public var type: String
    public var payload: String
    public var proxy: String
    public var size: Int?
    public var extra: RuleExtraSnapshot?
    public var metadata: [String: MihomoJSONValue]

    public init(
        index: Int? = nil,
        type: String,
        payload: String,
        proxy: String,
        size: Int? = nil,
        extra: RuleExtraSnapshot? = nil,
        metadata: [String: MihomoJSONValue] = [:]
    ) {
        self.index = index
        self.type = type
        self.payload = payload
        self.proxy = proxy
        self.size = size
        self.extra = extra
        self.metadata = metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        metadata = try container.allKeys.reduce(into: [:]) { values, key in
            values[key.stringValue] = try container.decode(MihomoJSONValue.self, forKey: key)
        }

        index = metadata["index"]?.intValue
        type = metadata["type"]?.stringValue ?? ""
        payload = metadata["payload"]?.stringValue ?? ""
        proxy = metadata["proxy"]?.stringValue ?? ""
        size = metadata["size"]?.intValue
        extra = metadata["extra"].flatMap(RuleExtraSnapshot.init(rawValue:))
    }

    public func encode(to encoder: Encoder) throws {
        var values = metadata
        if let index { values["index"] = .number(Double(index)) }
        values["type"] = .string(type)
        values["payload"] = .string(payload)
        values["proxy"] = .string(proxy)
        if let size { values["size"] = .number(Double(size)) }
        if let extra { values["extra"] = extra.rawValue }

        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in values {
            try container.encode(value, forKey: DynamicCodingKey(stringValue: key))
        }
    }

    public var disabled: Bool? { extra?.disabled }
    public var hitCount: Int? { extra?.hitCount }
    public var hitAt: String? { extra?.hitAt }
    public var missCount: Int? { extra?.missCount }
    public var missAt: String? { extra?.missAt }
    public var hasMutableExtra: Bool { extra != nil }

    public var additionalMetadata: [String: MihomoJSONValue] {
        metadata.filter { !["index", "type", "payload", "proxy", "size", "extra"].contains($0.key) }
    }
}

public struct RuleExtraSnapshot: Codable, Equatable, Sendable {
    public var disabled: Bool?
    public var hitCount: Int?
    public var hitAt: String?
    public var missCount: Int?
    public var missAt: String?
    public var metadata: [String: MihomoJSONValue]

    public init(
        disabled: Bool? = nil,
        hitCount: Int? = nil,
        hitAt: String? = nil,
        missCount: Int? = nil,
        missAt: String? = nil,
        metadata: [String: MihomoJSONValue] = [:]
    ) {
        self.disabled = disabled
        self.hitCount = hitCount
        self.hitAt = hitAt
        self.missCount = missCount
        self.missAt = missAt
        self.metadata = metadata
    }

    fileprivate init?(rawValue: MihomoJSONValue) {
        guard let object = rawValue.objectValue else { return nil }
        disabled = object["disabled"]?.boolValue
        hitCount = object["hitCount"]?.intValue
        hitAt = object["hitAt"]?.stringValue
        missCount = object["missCount"]?.intValue
        missAt = object["missAt"]?.stringValue
        metadata = object
    }

    fileprivate var rawValue: MihomoJSONValue {
        var values = metadata
        if let disabled { values["disabled"] = .bool(disabled) }
        if let hitCount { values["hitCount"] = .number(Double(hitCount)) }
        if let hitAt { values["hitAt"] = .string(hitAt) }
        if let missCount { values["missCount"] = .number(Double(missCount)) }
        if let missAt { values["missAt"] = .string(missAt) }
        return .object(values)
    }
}

public struct ProxyProvidersResponse: Decodable, Equatable, Sendable {
    public var providers: [String: ProxyProviderSnapshot]
    public var providerOrder: [String]

    public var providerList: [ProxyProviderSnapshot] {
        providerOrder.compactMap { providers[$0] }
    }

    public init(providers: [String: ProxyProviderSnapshot], providerOrder: [String]? = nil) {
        self.providers = providers
        self.providerOrder = providerOrder ?? providers.keys.sorted()
    }

    public static func decodePreservingProviderOrder(
        from data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> ProxyProvidersResponse {
        var response = try decoder.decode(ProxyProvidersResponse.self, from: data)
        let sourceOrder = JSONKeyOrderScanner.objectKeyOrder(for: "providers", in: data)
        if !sourceOrder.isEmpty {
            response.providerOrder = sourceOrder
        }
        return response
    }

    public init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: CodingKeys.self)
        let container = try root.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .providers)
        var decoded: [String: ProxyProviderSnapshot] = [:]

        for key in container.allKeys {
            let raw = try container.decode(RawProxyProviderSnapshot.self, forKey: key)
            decoded[key.stringValue] = ProxyProviderSnapshot(name: key.stringValue, raw: raw)
        }

        providers = decoded
        providerOrder = container.allKeys.map(\.stringValue)
    }

    enum CodingKeys: String, CodingKey {
        case providers
    }
}

public struct ProxyProviderSnapshot: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var type: String
    public var vehicleType: String?
    public var format: String?
    public var testURL: String?
    public var updatedAt: String?
    public var healthCheck: MihomoJSONValue?
    public var subscriptionInfo: MihomoJSONValue?
    public var updatable: Bool
    public var proxyCount: Int

    public init(
        name: String,
        type: String,
        vehicleType: String? = nil,
        format: String? = nil,
        testURL: String? = nil,
        updatedAt: String? = nil,
        healthCheck: MihomoJSONValue? = nil,
        subscriptionInfo: MihomoJSONValue? = nil,
        updatable: Bool? = nil,
        proxyCount: Int = 0
    ) {
        self.name = name
        self.type = type
        self.vehicleType = vehicleType
        self.format = format
        self.testURL = testURL
        self.updatedAt = updatedAt
        self.healthCheck = healthCheck
        self.subscriptionInfo = subscriptionInfo
        self.updatable = updatable ?? Self.defaultUpdatable(vehicleType: vehicleType)
        self.proxyCount = proxyCount
    }

    fileprivate init(name: String, raw: RawProxyProviderSnapshot) {
        self.init(
            name: raw.name ?? name,
            type: raw.type,
            vehicleType: raw.vehicleType,
            format: raw.format,
            testURL: raw.testURL,
            updatedAt: raw.updatedAt,
            healthCheck: raw.healthCheck,
            subscriptionInfo: raw.subscriptionInfo,
            updatable: raw.updatable,
            proxyCount: raw.proxies?.count ?? 0
        )
    }

    private static func defaultUpdatable(vehicleType: String?) -> Bool {
        vehicleType?.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("HTTP") == .orderedSame
    }
}

private struct RawProxyProviderSnapshot: Decodable {
    var name: String?
    var type: String
    var vehicleType: String?
    var format: String?
    var testURL: String?
    var updatedAt: String?
    var healthCheck: MihomoJSONValue?
    var subscriptionInfo: MihomoJSONValue?
    var updatable: Bool?
    var proxies: [RawProviderProxySnapshot]?

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case vehicleType
        case format
        case testURL = "testUrl"
        case updatedAt
        case healthCheck
        case subscriptionInfo
        case updatable
        case proxies
    }
}

private struct RawProviderProxySnapshot: Decodable {
    var name: String?
    var type: String?
}

public enum ProviderKind: String, Codable, Equatable, Sendable {
    case proxy
    case rule
}

public struct RuleProvidersResponse: Decodable, Equatable, Sendable {
    public var providers: [String: RuleProviderSnapshot]
    public var providerOrder: [String]

    public var providerList: [RuleProviderSnapshot] {
        providerOrder.compactMap { providers[$0] }
    }

    public init(providers: [String: RuleProviderSnapshot], providerOrder: [String]? = nil) {
        self.providers = providers
        self.providerOrder = providerOrder ?? providers.keys.sorted()
    }

    public static func decodePreservingProviderOrder(
        from data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> RuleProvidersResponse {
        var response = try decoder.decode(RuleProvidersResponse.self, from: data)
        let sourceOrder = JSONKeyOrderScanner.objectKeyOrder(for: "providers", in: data)
        if !sourceOrder.isEmpty {
            response.providerOrder = sourceOrder
        }
        return response
    }

    public init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: CodingKeys.self)
        let container = try root.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .providers)
        var decoded: [String: RuleProviderSnapshot] = [:]

        for key in container.allKeys {
            let raw = try container.decode(RawRuleProviderSnapshot.self, forKey: key)
            decoded[key.stringValue] = RuleProviderSnapshot(name: key.stringValue, raw: raw)
        }

        providers = decoded
        providerOrder = container.allKeys.map(\.stringValue)
    }

    enum CodingKeys: String, CodingKey {
        case providers
    }
}

public struct RuleProviderSnapshot: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var type: String
    public var behavior: String?
    public var format: String?
    public var vehicleType: String?
    public var updatedAt: String?
    public var healthCheck: MihomoJSONValue?
    public var updatable: Bool
    public var ruleCount: Int

    public init(
        name: String,
        type: String,
        behavior: String? = nil,
        format: String? = nil,
        vehicleType: String? = nil,
        updatedAt: String? = nil,
        healthCheck: MihomoJSONValue? = nil,
        updatable: Bool? = nil,
        ruleCount: Int = 0
    ) {
        self.name = name
        self.type = type
        self.behavior = behavior
        self.format = format
        self.vehicleType = vehicleType
        self.updatedAt = updatedAt
        self.healthCheck = healthCheck
        self.updatable = updatable ?? Self.defaultUpdatable(vehicleType: vehicleType)
        self.ruleCount = ruleCount
    }

    fileprivate init(name: String, raw: RawRuleProviderSnapshot) {
        self.init(
            name: raw.name ?? name,
            type: raw.type,
            behavior: raw.behavior,
            format: raw.format,
            vehicleType: raw.vehicleType,
            updatedAt: raw.updatedAt,
            healthCheck: raw.healthCheck,
            updatable: raw.updatable,
            ruleCount: raw.ruleCount ?? raw.rules?.count ?? 0
        )
    }

    private static func defaultUpdatable(vehicleType: String?) -> Bool {
        vehicleType?.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("HTTP") == .orderedSame
    }
}

private struct RawRuleProviderSnapshot: Decodable {
    var name: String?
    var type: String
    var behavior: String?
    var format: String?
    var vehicleType: String?
    var updatedAt: String?
    var healthCheck: MihomoJSONValue?
    var updatable: Bool?
    var ruleCount: Int?
    var rules: [RawRuleProviderRuleSnapshot]?

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case behavior
        case format
        case vehicleType
        case updatedAt
        case healthCheck
        case updatable
        case ruleCount
        case ruleCountKebab = "rule-count"
        case rules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        behavior = try container.decodeIfPresent(String.self, forKey: .behavior)
        format = try container.decodeIfPresent(String.self, forKey: .format)
        vehicleType = try container.decodeIfPresent(String.self, forKey: .vehicleType)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        healthCheck = try container.decodeIfPresent(MihomoJSONValue.self, forKey: .healthCheck)
        updatable = try container.decodeIfPresent(Bool.self, forKey: .updatable)
        ruleCount = try container.decodeIfPresent(Int.self, forKey: .ruleCount)
            ?? container.decodeIfPresent(Int.self, forKey: .ruleCountKebab)
        rules = try container.decodeIfPresent([RawRuleProviderRuleSnapshot].self, forKey: .rules)
    }
}

private struct RawRuleProviderRuleSnapshot: Decodable {
    var type: String?
    var payload: String?
    var proxy: String?
}

public struct ConnectionSnapshot: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var upload: Int?
    public var download: Int?
    public var uploadSpeed: Int?
    public var downloadSpeed: Int?
    public var start: String?
    public var chains: [String]?
    public var providerChains: [String]?
    public var rule: String?
    public var rulePayload: String?
    public var metadata: ConnectionMetadataSnapshot?
    public var fields: [String: MihomoJSONValue]

    public init(
        id: String,
        upload: Int? = nil,
        download: Int? = nil,
        uploadSpeed: Int? = nil,
        downloadSpeed: Int? = nil,
        start: String? = nil,
        chains: [String]? = nil,
        providerChains: [String]? = nil,
        rule: String? = nil,
        rulePayload: String? = nil,
        metadata: ConnectionMetadataSnapshot? = nil,
        fields: [String: MihomoJSONValue] = [:]
    ) {
        self.id = id
        self.upload = upload
        self.download = download
        self.uploadSpeed = uploadSpeed
        self.downloadSpeed = downloadSpeed
        self.start = start
        self.chains = chains
        self.providerChains = providerChains
        self.rule = rule
        self.rulePayload = rulePayload
        self.metadata = metadata
        self.fields = fields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        fields = try container.allKeys.reduce(into: [:]) { values, key in
            values[key.stringValue] = try container.decode(MihomoJSONValue.self, forKey: key)
        }

        id = fields["id"]?.scalarStringValue ?? ""
        upload = fields["upload"]?.counterValue
        download = fields["download"]?.counterValue
        uploadSpeed = fields["uploadSpeed"]?.counterValue
            ?? fields["upload-speed"]?.counterValue
        downloadSpeed = fields["downloadSpeed"]?.counterValue
            ?? fields["download-speed"]?.counterValue
        start = fields["start"]?.scalarStringValue
        chains = fields["chains"]?.scalarStringArrayValue
        providerChains = fields["providerChains"]?.scalarStringArrayValue
            ?? fields["provider-chains"]?.scalarStringArrayValue
        rule = fields["rule"]?.scalarStringValue
        rulePayload = fields["rulePayload"]?.scalarStringValue
            ?? fields["rule-payload"]?.scalarStringValue
        metadata = fields["metadata"].flatMap(ConnectionMetadataSnapshot.init(rawValue:))
    }

    public func encode(to encoder: Encoder) throws {
        var values = fields
        values["id"] = .string(id)
        if let upload { values["upload"] = .number(Double(upload)) }
        if let download { values["download"] = .number(Double(download)) }
        if let uploadSpeed { values["uploadSpeed"] = .number(Double(uploadSpeed)) }
        if let downloadSpeed { values["downloadSpeed"] = .number(Double(downloadSpeed)) }
        if let start { values["start"] = .string(start) }
        if let chains { values["chains"] = .array(chains.map(MihomoJSONValue.string)) }
        if let providerChains { values["providerChains"] = .array(providerChains.map(MihomoJSONValue.string)) }
        if let rule { values["rule"] = .string(rule) }
        if let rulePayload { values["rulePayload"] = .string(rulePayload) }
        if let metadata { values["metadata"] = metadata.rawValue }

        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in values {
            try container.encode(value, forKey: DynamicCodingKey(stringValue: key))
        }
    }

    public var additionalFields: [String: MihomoJSONValue] {
        let knownKeys: Set<String> = [
            "id", "upload", "download", "uploadSpeed", "upload-speed",
            "downloadSpeed", "download-speed", "start", "chains",
            "providerChains", "provider-chains", "rule", "rulePayload",
            "rule-payload", "metadata",
        ]
        return fields.filter { !knownKeys.contains($0.key) }
    }
}

public struct ConnectionMetadataSnapshot: Codable, Equatable, Sendable {
    public var host: String?
    public var network: String?
    public var type: String?
    public var sourceIP: String?
    public var destinationIP: String?
    public var sourcePort: String?
    public var destinationPort: String?
    public var process: String?
    public var processPath: String?
    public var inboundIP: String?
    public var inboundPort: String?
    public var inboundName: String?
    public var dnsMode: String?
    public var sniffHost: String?
    public var specialProxy: String?
    public var specialRules: String?
    public var remoteDestination: String?
    public var connectionLogs: [String]?
    public var uid: Int?
    public var fields: [String: MihomoJSONValue]

    public init(
        host: String? = nil,
        network: String? = nil,
        type: String? = nil,
        sourceIP: String? = nil,
        destinationIP: String? = nil,
        sourcePort: String? = nil,
        destinationPort: String? = nil,
        process: String? = nil,
        processPath: String? = nil,
        inboundIP: String? = nil,
        inboundPort: String? = nil,
        inboundName: String? = nil,
        dnsMode: String? = nil,
        sniffHost: String? = nil,
        specialProxy: String? = nil,
        specialRules: String? = nil,
        remoteDestination: String? = nil,
        connectionLogs: [String]? = nil,
        uid: Int? = nil,
        fields: [String: MihomoJSONValue] = [:]
    ) {
        self.host = host
        self.network = network
        self.type = type
        self.sourceIP = sourceIP
        self.destinationIP = destinationIP
        self.sourcePort = sourcePort
        self.destinationPort = destinationPort
        self.process = process
        self.processPath = processPath
        self.inboundIP = inboundIP
        self.inboundPort = inboundPort
        self.inboundName = inboundName
        self.dnsMode = dnsMode
        self.sniffHost = sniffHost
        self.specialProxy = specialProxy
        self.specialRules = specialRules
        self.remoteDestination = remoteDestination
        self.connectionLogs = connectionLogs
        self.uid = uid
        self.fields = fields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let fields = try container.allKeys.reduce(into: [String: MihomoJSONValue]()) { values, key in
            values[key.stringValue] = try container.decode(MihomoJSONValue.self, forKey: key)
        }
        self.init(fields: fields)
    }

    fileprivate init?(rawValue: MihomoJSONValue) {
        guard let fields = rawValue.objectValue else { return nil }
        self.init(fields: fields)
    }

    private init(fields: [String: MihomoJSONValue]) {
        self.fields = fields
        host = fields["host"]?.scalarStringValue
        network = fields["network"]?.scalarStringValue
        type = fields["type"]?.scalarStringValue ?? fields["inbound"]?.scalarStringValue
        sourceIP = fields["sourceIP"]?.scalarStringValue
        destinationIP = fields["destinationIP"]?.scalarStringValue
        sourcePort = fields["sourcePort"]?.scalarStringValue
        destinationPort = fields["destinationPort"]?.scalarStringValue
        process = fields["process"]?.scalarStringValue
        processPath = fields["processPath"]?.scalarStringValue
        inboundIP = fields["inboundIP"]?.scalarStringValue
        inboundPort = fields["inboundPort"]?.scalarStringValue
        inboundName = fields["inboundName"]?.scalarStringValue
        dnsMode = fields["dnsMode"]?.scalarStringValue
        sniffHost = fields["sniffHost"]?.scalarStringValue
        specialProxy = fields["specialProxy"]?.scalarStringValue
        specialRules = fields["specialRules"]?.scalarStringValue
        remoteDestination = fields["remoteDestination"]?.scalarStringValue
        connectionLogs = fields["log"]?.scalarStringArrayValue
        uid = fields["uid"]?.intValue
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in normalizedFields {
            try container.encode(value, forKey: DynamicCodingKey(stringValue: key))
        }
    }

    fileprivate var rawValue: MihomoJSONValue {
        .object(normalizedFields)
    }

    public var additionalFields: [String: MihomoJSONValue] {
        let knownKeys: Set<String> = [
            "host", "network", "type", "inbound", "sourceIP", "destinationIP",
            "sourcePort", "destinationPort", "process", "processPath", "inboundIP",
            "inboundPort", "inboundName", "dnsMode", "sniffHost", "specialProxy",
            "specialRules", "remoteDestination", "log", "uid",
        ]
        return fields.filter { !knownKeys.contains($0.key) }
    }

    private var normalizedFields: [String: MihomoJSONValue] {
        var values = fields
        if let host { values["host"] = .string(host) }
        if let network { values["network"] = .string(network) }
        if let type { values["type"] = .string(type) }
        if let sourceIP { values["sourceIP"] = .string(sourceIP) }
        if let destinationIP { values["destinationIP"] = .string(destinationIP) }
        if let sourcePort { values["sourcePort"] = .string(sourcePort) }
        if let destinationPort { values["destinationPort"] = .string(destinationPort) }
        if let process { values["process"] = .string(process) }
        if let processPath { values["processPath"] = .string(processPath) }
        if let inboundIP { values["inboundIP"] = .string(inboundIP) }
        if let inboundPort { values["inboundPort"] = .string(inboundPort) }
        if let inboundName { values["inboundName"] = .string(inboundName) }
        if let dnsMode { values["dnsMode"] = .string(dnsMode) }
        if let sniffHost { values["sniffHost"] = .string(sniffHost) }
        if let specialProxy { values["specialProxy"] = .string(specialProxy) }
        if let specialRules { values["specialRules"] = .string(specialRules) }
        if let remoteDestination { values["remoteDestination"] = .string(remoteDestination) }
        if let connectionLogs { values["log"] = .array(connectionLogs.map(MihomoJSONValue.string)) }
        if let uid { values["uid"] = .number(Double(uid)) }
        return values
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
