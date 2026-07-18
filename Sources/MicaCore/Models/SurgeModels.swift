import Foundation

public struct SurgeEventsResponse: Codable, Equatable, Sendable {
    public var events: [SurgeEvent]

    public init(events: [SurgeEvent] = []) {
        self.events = events
    }
}

public struct SurgeEvent: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var type: String?
    public var message: String?
    public var date: String?

    public init(id: String, type: String? = nil, message: String? = nil, date: String? = nil) {
        self.id = id
        self.type = type
        self.message = message
        self.date = date
    }
}

public struct SurgeOutboundResponse: Codable, Equatable, Sendable {
    public var mode: String

    public init(mode: String) {
        self.mode = mode
    }
}

public struct SurgePoliciesResponse: Codable, Equatable, Sendable {
    public var policies: [SurgePolicy]

    public init(policies: [SurgePolicy]) {
        self.policies = policies
    }
}

public struct SurgePolicy: Codable, Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var type: String?

    public init(name: String, type: String? = nil) {
        self.name = name
        self.type = type
    }
}

public struct SurgePolicyGroupsResponse: Codable, Equatable, Sendable {
    public var groups: [SurgePolicyGroup]

    public init(groups: [SurgePolicyGroup]) {
        self.groups = groups
    }
}

public struct SurgePolicyGroup: Codable, Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var type: String?
    public var selected: String?
    public var policies: [String]
    public var latency: [String: Int]?

    public init(
        name: String,
        type: String? = nil,
        selected: String? = nil,
        policies: [String] = [],
        latency: [String: Int]? = nil
    ) {
        self.name = name
        self.type = type
        self.selected = selected
        self.policies = policies
        self.latency = latency
    }
}

public struct SurgePolicyGroupTestResponse: Codable, Equatable, Sendable {
    public var delay: [String: Int]

    public init(delay: [String: Int]) {
        self.delay = delay
    }
}

public struct SurgeActiveRequestsResponse: Codable, Equatable, Sendable {
    public var requests: [SurgeActiveRequest]

    public init(requests: [SurgeActiveRequest]) {
        self.requests = requests
    }

    public init(from decoder: Decoder) throws {
        let value = try ControllerJSONValue(from: decoder)
        let items: [ControllerJSONValue]
        switch value {
        case .array(let values):
            items = values
        case .object(let object):
            items = ["requests", "active", "data"].lazy
                .compactMap { object[$0]?.surgeArrayValue }
                .first ?? []
        case .string, .number, .bool, .null:
            items = []
        }

        requests = items.compactMap { value in
            guard let fields = value.surgeObjectValue else { return nil }
            return SurgeActiveRequest(fields: fields)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SurgeDynamicCodingKey.self)
        try container.encode(requests, forKey: SurgeDynamicCodingKey(stringValue: "requests"))
    }
}

public struct SurgeActiveRequest: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var method: String?
    public var url: String?
    public var rule: String?
    public var ruleType: String?
    public var rulePayload: String?
    public var policy: String?
    public var originalPolicy: String?
    public var upload: Int?
    public var download: Int?
    public var uploadSpeed: Int?
    public var downloadSpeed: Int?
    public var sourceAddress: String?
    public var sourcePort: String?
    public var destinationAddress: String?
    public var destinationPort: String?
    public var localAddress: String?
    public var interfaceName: String?
    public var process: String?
    public var processPath: String?
    public var uid: Int?
    public var notes: [String]?
    public var status: String?
    public var start: String?
    public var fields: [String: ControllerJSONValue]

    public init(
        id: String,
        method: String? = nil,
        url: String? = nil,
        rule: String? = nil,
        ruleType: String? = nil,
        rulePayload: String? = nil,
        policy: String? = nil,
        originalPolicy: String? = nil,
        upload: Int? = nil,
        download: Int? = nil,
        uploadSpeed: Int? = nil,
        downloadSpeed: Int? = nil,
        sourceAddress: String? = nil,
        sourcePort: String? = nil,
        destinationAddress: String? = nil,
        destinationPort: String? = nil,
        localAddress: String? = nil,
        interfaceName: String? = nil,
        process: String? = nil,
        processPath: String? = nil,
        uid: Int? = nil,
        notes: [String]? = nil,
        status: String? = nil,
        start: String? = nil,
        fields: [String: ControllerJSONValue] = [:]
    ) {
        self.id = id
        self.method = method
        self.url = url
        self.rule = rule
        self.ruleType = ruleType
        self.rulePayload = rulePayload
        self.policy = policy
        self.originalPolicy = originalPolicy
        self.upload = upload
        self.download = download
        self.uploadSpeed = uploadSpeed
        self.downloadSpeed = downloadSpeed
        self.sourceAddress = sourceAddress
        self.sourcePort = sourcePort
        self.destinationAddress = destinationAddress
        self.destinationPort = destinationPort
        self.localAddress = localAddress
        self.interfaceName = interfaceName
        self.process = process
        self.processPath = processPath
        self.uid = uid
        self.notes = notes
        self.status = status
        self.start = start
        self.fields = fields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SurgeDynamicCodingKey.self)
        let fields = try container.allKeys.reduce(into: [String: ControllerJSONValue]()) { values, key in
            values[key.stringValue] = try container.decode(ControllerJSONValue.self, forKey: key)
        }
        self.init(fields: fields)
    }

    fileprivate init(fields: [String: ControllerJSONValue]) {
        self.fields = fields
        id = Self.firstString(fields, keys: ["id", "requestId"]) ?? ""
        method = Self.firstString(fields, keys: ["method", "protocol"])
        url = Self.firstString(fields, keys: ["URL", "url", "remoteHost", "host"])

        let rawRule = Self.firstString(fields, keys: ["rule", "ruleName"])
        let explicitRulePayload = Self.firstString(fields, keys: ["rulePayload", "ruleValue"])
        let splitRule = Self.splitRule(rawRule ?? explicitRulePayload)
        rule = rawRule ?? explicitRulePayload
        ruleType = splitRule.type
        rulePayload = explicitRulePayload ?? splitRule.payload

        policy = Self.firstString(fields, keys: ["policyName", "policy", "rulePolicy"])
        originalPolicy = Self.firstString(fields, keys: ["originalPolicyName"])
        upload = Self.firstCounter(fields, keys: ["outBytes", "upload", "uploadTotal"])
        download = Self.firstCounter(fields, keys: ["inBytes", "download", "downloadTotal"])
        uploadSpeed = Self.firstCounter(fields, keys: ["outCurrentSpeed", "uploadSpeed"])
        downloadSpeed = Self.firstCounter(fields, keys: ["inCurrentSpeed", "downloadSpeed"])
        sourceAddress = Self.firstString(
            fields,
            keys: ["sourceAddress", "sourceIP", "sourceIp", "clientIP", "clientAddress"]
        )
        sourcePort = Self.firstString(fields, keys: ["sourcePort", "clientPort"])
        destinationAddress = Self.firstString(
            fields,
            keys: ["remoteAddress", "destinationIP", "destinationIp"]
        )
        destinationPort = Self.firstString(fields, keys: ["destinationPort", "remotePort"])
        localAddress = Self.firstString(fields, keys: ["localAddress"])
        interfaceName = Self.firstString(fields, keys: ["interface"])
        process = Self.firstString(fields, keys: ["process", "processName", "application"])
        processPath = Self.firstString(fields, keys: ["processPath", "applicationPath"])
        uid = Self.firstCounter(fields, keys: ["uid", "pid"])
        notes = ["notes"].lazy.compactMap { fields[$0]?.surgeScalarStringArrayValue }.first
        status = Self.firstString(fields, keys: ["status", "remark"])
        start = Self.firstString(fields, keys: ["start", "startTime", "createdAt", "startDate"])
    }

    public func encode(to encoder: Encoder) throws {
        var values = fields
        values["id"] = .string(id)
        if let method { values["method"] = .string(method) }
        if let url { values["URL"] = .string(url) }
        if let rule { values["rule"] = .string(rule) }
        if let rulePayload { values["rulePayload"] = .string(rulePayload) }
        if let policy { values["policyName"] = .string(policy) }
        if let originalPolicy { values["originalPolicyName"] = .string(originalPolicy) }
        if let upload { values["outBytes"] = .number(Double(upload)) }
        if let download { values["inBytes"] = .number(Double(download)) }
        if let uploadSpeed { values["outCurrentSpeed"] = .number(Double(uploadSpeed)) }
        if let downloadSpeed { values["inCurrentSpeed"] = .number(Double(downloadSpeed)) }
        if let sourceAddress { values["sourceAddress"] = .string(sourceAddress) }
        if let sourcePort { values["sourcePort"] = .string(sourcePort) }
        if let destinationAddress { values["remoteAddress"] = .string(destinationAddress) }
        if let destinationPort { values["destinationPort"] = .string(destinationPort) }
        if let localAddress { values["localAddress"] = .string(localAddress) }
        if let interfaceName { values["interface"] = .string(interfaceName) }
        if let process { values["process"] = .string(process) }
        if let processPath { values["processPath"] = .string(processPath) }
        if let uid { values["uid"] = .number(Double(uid)) }
        if let notes { values["notes"] = .array(notes.map(ControllerJSONValue.string)) }
        if let status { values["status"] = .string(status) }
        if let start { values["start"] = .string(start) }

        var container = encoder.container(keyedBy: SurgeDynamicCodingKey.self)
        for (key, value) in values {
            try container.encode(value, forKey: SurgeDynamicCodingKey(stringValue: key))
        }
    }

    public var additionalFields: [String: ControllerJSONValue] {
        let knownKeys: Set<String> = [
            "id", "requestId", "method", "protocol", "URL", "url", "remoteHost", "host",
            "rule", "ruleName", "rulePayload", "ruleValue", "policyName", "policy",
            "rulePolicy", "originalPolicyName", "outBytes", "upload", "uploadTotal",
            "inBytes", "download", "downloadTotal", "outCurrentSpeed", "uploadSpeed",
            "inCurrentSpeed", "downloadSpeed", "sourceAddress", "sourceIP", "sourceIp",
            "clientIP", "clientAddress", "sourcePort", "clientPort", "remoteAddress",
            "destinationIP", "destinationIp", "destinationPort", "remotePort", "localAddress",
            "interface", "process", "processName", "application", "processPath",
            "applicationPath", "uid", "pid", "notes", "status", "remark", "start",
            "startTime", "createdAt", "startDate",
        ]
        return fields.filter { !knownKeys.contains($0.key) }
    }

    private static func firstString(
        _ fields: [String: ControllerJSONValue],
        keys: [String]
    ) -> String? {
        keys.lazy.compactMap { fields[$0]?.surgeScalarStringValue }.first
    }

    private static func firstCounter(
        _ fields: [String: ControllerJSONValue],
        keys: [String]
    ) -> Int? {
        keys.lazy.compactMap { fields[$0]?.surgeCounterValue }.first
    }

    private static func splitRule(_ raw: String?) -> (type: String?, payload: String?) {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return (nil, nil)
        }

        for delimiter in [" ", ","] {
            if let range = raw.range(of: delimiter) {
                let type = String(raw[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let payload = String(raw[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return (type.isEmpty ? nil : type, payload.isEmpty ? nil : payload)
            }
        }

        if let range = raw.range(of: "(") {
            let type = String(raw[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let payload = String(raw[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (type.isEmpty ? nil : type, payload.isEmpty ? nil : payload)
        }

        return (raw, nil)
    }
}

private extension ControllerJSONValue {
    var surgeObjectValue: [String: ControllerJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var surgeArrayValue: [ControllerJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var surgeScalarStringValue: String? {
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

    var surgeScalarStringArrayValue: [String]? {
        surgeArrayValue?.compactMap(\.surgeScalarStringValue)
    }

    var surgeCounterValue: Int? {
        switch self {
        case .number(let value):
            guard value.isFinite,
                  value >= Double(Int.min),
                  value <= Double(Int.max) else {
                return nil
            }
            return Int(value.rounded())
        case .string(let value):
            return Int(value)
        case .object(let object):
            return object["total"]?.surgeCounterValue
        case .bool, .array, .null:
            return nil
        }
    }
}

private struct SurgeDynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

public struct SurgeRulesResponse: Codable, Equatable, Sendable {
    public var rules: [SurgeRule]

    public init(rules: [SurgeRule]) {
        self.rules = rules
    }
}

public struct SurgeRule: Codable, Identifiable, Equatable, Sendable {
    public var id: String {
        "\(type ?? "RULE"):\(policy ?? "POLICY"):\(payloadHash)"
    }

    public var type: String?
    public var payload: String?
    public var policy: String?
    public var size: Int?

    public init(type: String? = nil, payload: String? = nil, policy: String? = nil, size: Int? = nil) {
        self.type = type
        self.payload = payload
        self.policy = policy
        self.size = size
    }

    private var payloadHash: String {
        guard let payload else {
            return "none"
        }

        let value = payload.utf8.reduce(UInt32(2_166_136_261)) { hash, byte in
            (hash ^ UInt32(byte)) &* 16_777_619
        }
        return String(value, radix: 16)
    }
}

public struct SurgeTrafficResponse: Codable, Equatable, Sendable {
    public var upload: Int
    public var download: Int

    public init(upload: Int, download: Int) {
        self.upload = upload
        self.download = download
    }
}

public struct SurgeDNSCacheResponse: Codable, Equatable, Sendable {
    public var entryCount: Int?

    public init(entryCount: Int? = nil) {
        self.entryCount = entryCount
    }

    public init(from decoder: Decoder) throws {
        let value = try SurgeJSONValue(from: decoder)
        self.entryCount = Self.countEntries(in: value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(entryCount, forKey: .entryCount)
    }

    private enum CodingKeys: String, CodingKey {
        case entryCount
    }

    private static func countEntries(in value: SurgeJSONValue) -> Int? {
        switch value {
        case .array(let values):
            return values.count
        case .object(let object):
            for key in ["records", "items", "entries", "dns", "cache"] {
                if case .array(let values)? = object[key] {
                    return values.count
                }
                if case .object(let values)? = object[key] {
                    return values.isEmpty ? nil : values.count
                }
            }

            return object.isEmpty ? nil : object.count
        case .string, .number, .bool, .null:
            return nil
        }
    }
}

private enum SurgeJSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: SurgeJSONValue])
    case array([SurgeJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SurgeJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: SurgeJSONValue].self))
        }
    }
}

public struct SurgeControlSnapshot: Codable, Equatable, Sendable {
    public var platform: SurgeControllerPlatform
    public var events: [SurgeEvent]
    public var outboundMode: String
    public var policies: [SurgePolicy]
    public var policyGroups: [SurgePolicyGroup]
    public var activeRequests: [SurgeActiveRequest]
    public var recentRequests: [SurgeActiveRequest]
    public var rules: [SurgeRule]
    public var traffic: SurgeTrafficResponse
    public var dnsCacheEntryCount: Int?
    public var checkedAt: Date?

    public init(
        platform: SurgeControllerPlatform = .remoteMac,
        events: SurgeEventsResponse = SurgeEventsResponse(),
        outbound: SurgeOutboundResponse = SurgeOutboundResponse(mode: "rule"),
        policies: SurgePoliciesResponse = SurgePoliciesResponse(policies: []),
        policyGroups: SurgePolicyGroupsResponse = SurgePolicyGroupsResponse(groups: []),
        activeRequests: SurgeActiveRequestsResponse = SurgeActiveRequestsResponse(requests: []),
        recentRequests: SurgeActiveRequestsResponse = SurgeActiveRequestsResponse(requests: []),
        rules: SurgeRulesResponse = SurgeRulesResponse(rules: []),
        traffic: SurgeTrafficResponse = SurgeTrafficResponse(upload: 0, download: 0),
        dnsCache: SurgeDNSCacheResponse = SurgeDNSCacheResponse(),
        checkedAt: Date? = Date()
    ) {
        self.platform = platform
        self.events = events.events
        self.outboundMode = outbound.mode
        self.policies = policies.policies
        self.policyGroups = policyGroups.groups
        self.activeRequests = activeRequests.requests
        self.recentRequests = recentRequests.requests
        self.rules = rules.rules
        self.traffic = traffic
        self.dnsCacheEntryCount = dnsCache.entryCount
        self.checkedAt = checkedAt
    }

    public static let empty = SurgeControlSnapshot(checkedAt: nil)

    public var reportedAggregateFieldCount: Int {
        guard checkedAt != nil else {
            return 0
        }

        return [
            outboundMode.isEmpty ? nil : outboundMode,
            policies.isEmpty ? nil : "\(policies.count)",
            policyGroups.isEmpty ? nil : "\(policyGroups.count)",
            activeRequests.isEmpty ? nil : "\(activeRequests.count)",
            recentRequests.isEmpty ? nil : "\(recentRequests.count)",
            rules.isEmpty ? nil : "\(rules.count)",
            traffic.upload == 0 ? nil : "\(traffic.upload)",
            traffic.download == 0 ? nil : "\(traffic.download)",
            dnsCacheEntryCount.map { "\($0)" },
        ].compactMap(\.self).count
    }

    public var isEmpty: Bool {
        checkedAt == nil
            && events.isEmpty
            && policies.isEmpty
            && policyGroups.isEmpty
            && activeRequests.isEmpty
            && recentRequests.isEmpty
            && rules.isEmpty
            && traffic.upload == 0
            && traffic.download == 0
            && dnsCacheEntryCount == nil
    }
}
