import Darwin
import Foundation

/// Minimal, bounds-checked MaxMind DB v2 reader for Mica's offline GeoIP card.
/// It implements the search tree and value types used by GeoLite2 City/ASN.
struct MaxMindDatabase: Sendable {
    indirect enum Value: Equatable, Sendable {
        case string(String)
        case map([String: Value])
        case array([Value])
        case bytes([UInt8])
        case unsigned(UInt64)
        case unsigned128([UInt8])
        case signed(Int32)
        case double(Double)
        case float(Float)
        case boolean(Bool)

        var mapValue: [String: Value]? {
            guard case let .map(value) = self else { return nil }
            return value
        }

        var stringValue: String? {
            guard case let .string(value) = self else { return nil }
            return value
        }

        var unsignedValue: UInt64? {
            switch self {
            case let .unsigned(value):
                return value
            case let .unsigned128(bytes) where bytes.count <= MemoryLayout<UInt64>.size:
                return bytes.reduce(0) { ($0 << 8) | UInt64($1) }
            default:
                return nil
            }
        }

        func value(at path: String...) -> Value? {
            var current: Value = self
            for component in path {
                guard case let .map(map) = current, let next = map[component] else { return nil }
                current = next
            }
            return current
        }
    }

    enum DatabaseError: Error, Equatable {
        case unreadable
        case missingMetadata
        case invalidMetadata
        case unsupportedFormat
        case corruptData
        case invalidAddress
    }

    let databaseType: String

    private let bytes: Data
    private let recordSize: Int
    private let nodeCount: Int
    private let ipVersion: Int
    private let searchTreeSize: Int
    private let dataSectionStart: Int
    private let ipv4StartNode: Int?

    init(contentsOf url: URL) throws {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            throw DatabaseError.unreadable
        }
        try self.init(data: data)
    }

    init(data: Data) throws {
        let bytes = data
        guard let markerStart = Self.metadataMarkerStart(in: bytes) else {
            throw DatabaseError.missingMetadata
        }
        let metadataStart = markerStart + Self.metadataMarker.count
        var decoder = Decoder(bytes: bytes)
        var metadataOffset = metadataStart
        guard case let .map(metadata) = try decoder.decode(
            at: &metadataOffset,
            pointerBase: metadataStart,
            depth: 0
        ) else {
            throw DatabaseError.invalidMetadata
        }

        guard let major = metadata["binary_format_major_version"]?.unsignedValue,
              let recordSize = metadata["record_size"]?.unsignedValue,
              let nodeCount = metadata["node_count"]?.unsignedValue,
              let ipVersion = metadata["ip_version"]?.unsignedValue,
              let databaseType = metadata["database_type"]?.stringValue,
              major == 2,
              [24, 28, 32].contains(Int(recordSize)),
              [4, 6].contains(Int(ipVersion)),
              nodeCount <= UInt64(Int.max) else {
            throw DatabaseError.unsupportedFormat
        }

        let bytesPerNode = Int(recordSize) * 2 / 8
        let (treeSize, overflow) = Int(nodeCount).multipliedReportingOverflow(by: bytesPerNode)
        guard !overflow, treeSize + 16 <= markerStart else {
            throw DatabaseError.invalidMetadata
        }

        self.bytes = bytes
        self.recordSize = Int(recordSize)
        self.nodeCount = Int(nodeCount)
        self.ipVersion = Int(ipVersion)
        self.databaseType = databaseType
        searchTreeSize = treeSize
        dataSectionStart = treeSize + 16

        if ipVersion == 6 {
            ipv4StartNode = try Self.walkZeroPrefix(
                bits: 96,
                nodeCount: Int(nodeCount),
                recordSize: Int(recordSize),
                bytes: bytes
            )
        } else {
            ipv4StartNode = 0
        }
    }

    func lookup(_ address: String) throws -> Value? {
        let parsed = try Self.parseAddress(address)
        if parsed.family == AF_INET6, ipVersion == 4 { return nil }

        let startNode: Int
        if parsed.family == AF_INET {
            guard let ipv4StartNode else { return nil }
            startNode = ipv4StartNode
        } else {
            startNode = 0
        }

        var node = startNode
        for byte in parsed.bytes {
            for bitIndex in 0..<8 {
                let bit = Int((byte >> (7 - bitIndex)) & 1)
                node = try child(of: node, bit: bit)
                if node == nodeCount { return nil }
                if node > nodeCount {
                    let relativeOffset = node - nodeCount - 16
                    guard relativeOffset >= 0 else { throw DatabaseError.corruptData }
                    var offset = dataSectionStart + relativeOffset
                    var decoder = Decoder(bytes: bytes)
                    return try decoder.decode(at: &offset, pointerBase: dataSectionStart, depth: 0)
                }
            }
        }
        return nil
    }

    private func child(of node: Int, bit: Int) throws -> Int {
        guard node >= 0, node < nodeCount, bit == 0 || bit == 1 else {
            throw DatabaseError.corruptData
        }
        let base = node * (recordSize * 2 / 8)
        switch recordSize {
        case 24:
            let offset = base + bit * 3
            return try readInteger(at: offset, byteCount: 3)
        case 28:
            guard base + 6 < bytes.count else { throw DatabaseError.corruptData }
            if bit == 0 {
                return Int(bytes[base + 3] >> 4) << 24
                    | Int(bytes[base]) << 16
                    | Int(bytes[base + 1]) << 8
                    | Int(bytes[base + 2])
            }
            return Int(bytes[base + 3] & 0x0F) << 24
                | Int(bytes[base + 4]) << 16
                | Int(bytes[base + 5]) << 8
                | Int(bytes[base + 6])
        case 32:
            return try readInteger(at: base + bit * 4, byteCount: 4)
        default:
            throw DatabaseError.unsupportedFormat
        }
    }

    private func readInteger(at offset: Int, byteCount: Int) throws -> Int {
        guard offset >= 0, byteCount > 0, offset + byteCount <= bytes.count else {
            throw DatabaseError.corruptData
        }
        return bytes[offset..<(offset + byteCount)].reduce(0) { ($0 << 8) | Int($1) }
    }

    private static let metadataMarker: [UInt8] = [
        0xAB, 0xCD, 0xEF, 0x4D, 0x61, 0x78, 0x4D, 0x69,
        0x6E, 0x64, 0x2E, 0x63, 0x6F, 0x6D,
    ]

    private static func metadataMarkerStart(in bytes: Data) -> Int? {
        guard bytes.count >= metadataMarker.count else { return nil }
        let lowerBound = max(0, bytes.count - 131_072)
        for index in stride(from: bytes.count - metadataMarker.count, through: lowerBound, by: -1) {
            if bytes[index] == metadataMarker[0],
               bytes[index..<(index + metadataMarker.count)].elementsEqual(metadataMarker) {
                return index
            }
        }
        return nil
    }

    private static func walkZeroPrefix(
        bits: Int,
        nodeCount: Int,
        recordSize: Int,
        bytes: Data
    ) throws -> Int? {
        let database = SearchTreeReader(bytes: bytes, recordSize: recordSize, nodeCount: nodeCount)
        var node = 0
        for _ in 0..<bits {
            node = try database.child(of: node, bit: 0)
            if node == nodeCount { return nil }
            if node > nodeCount { return nil }
        }
        return node
    }

    private static func parseAddress(_ raw: String) throws -> (family: Int32, bytes: [UInt8]) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var ipv4 = in_addr()
        if value.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            return (AF_INET, withUnsafeBytes(of: &ipv4) { Array($0) })
        }

        var ipv6 = in6_addr()
        if value.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 {
            return (AF_INET6, withUnsafeBytes(of: &ipv6) { Array($0) })
        }
        throw DatabaseError.invalidAddress
    }

    private struct SearchTreeReader {
        var bytes: Data
        var recordSize: Int
        var nodeCount: Int

        func child(of node: Int, bit: Int) throws -> Int {
            guard node >= 0, node < nodeCount else { throw DatabaseError.corruptData }
            let base = node * (recordSize * 2 / 8)
            switch recordSize {
            case 24:
                return try integer(at: base + bit * 3, count: 3)
            case 28:
                guard base + 6 < bytes.count else { throw DatabaseError.corruptData }
                if bit == 0 {
                    return Int(bytes[base + 3] >> 4) << 24
                        | Int(bytes[base]) << 16
                        | Int(bytes[base + 1]) << 8
                        | Int(bytes[base + 2])
                }
                return Int(bytes[base + 3] & 0x0F) << 24
                    | Int(bytes[base + 4]) << 16
                    | Int(bytes[base + 5]) << 8
                    | Int(bytes[base + 6])
            case 32:
                return try integer(at: base + bit * 4, count: 4)
            default:
                throw DatabaseError.unsupportedFormat
            }
        }

        private func integer(at offset: Int, count: Int) throws -> Int {
            guard offset >= 0, offset + count <= bytes.count else { throw DatabaseError.corruptData }
            return bytes[offset..<(offset + count)].reduce(0) { ($0 << 8) | Int($1) }
        }
    }

    private struct Decoder {
        var bytes: Data

        mutating func decode(at offset: inout Int, pointerBase: Int, depth: Int) throws -> Value {
            guard depth < 64, offset >= 0, offset < bytes.count else { throw DatabaseError.corruptData }
            let control = bytes[offset]
            offset += 1

            let initialType = control >> 5
            let sizeCode = Int(control & 0x1F)
            let type: Int
            if initialType == 0 {
                guard offset < bytes.count else { throw DatabaseError.corruptData }
                type = Int(bytes[offset]) + 7
                offset += 1
            } else {
                type = Int(initialType)
            }

            if type == 1 {
                let pointer = try decodePointer(sizeCode: sizeCode, offset: &offset)
                var target = pointerBase + pointer
                return try decode(at: &target, pointerBase: pointerBase, depth: depth + 1)
            }

            let size = try decodeSize(sizeCode, offset: &offset)
            switch type {
            case 2:
                return .string(try readString(at: &offset, count: size))
            case 3:
                guard size == 8 else { throw DatabaseError.corruptData }
                return .double(Double(bitPattern: try readUnsigned(at: &offset, count: size)))
            case 4:
                return .bytes(try readBytes(at: &offset, count: size))
            case 5, 6, 9:
                return .unsigned(try readUnsigned(at: &offset, count: size))
            case 10:
                guard size <= 16 else { throw DatabaseError.corruptData }
                return .unsigned128(try readBytes(at: &offset, count: size))
            case 7:
                var result: [String: Value] = [:]
                result.reserveCapacity(size)
                for _ in 0..<size {
                    let keyValue = try decode(at: &offset, pointerBase: pointerBase, depth: depth + 1)
                    guard case let .string(key) = keyValue else { throw DatabaseError.corruptData }
                    result[key] = try decode(at: &offset, pointerBase: pointerBase, depth: depth + 1)
                }
                return .map(result)
            case 8:
                guard size <= 4 else { throw DatabaseError.corruptData }
                return .signed(Int32(bitPattern: UInt32(try readUnsigned(at: &offset, count: size))))
            case 11:
                var result: [Value] = []
                result.reserveCapacity(size)
                for _ in 0..<size {
                    result.append(try decode(at: &offset, pointerBase: pointerBase, depth: depth + 1))
                }
                return .array(result)
            case 14:
                return .boolean(size != 0)
            case 15:
                guard size == 4 else { throw DatabaseError.corruptData }
                return .float(Float(bitPattern: UInt32(try readUnsigned(at: &offset, count: size))))
            default:
                throw DatabaseError.unsupportedFormat
            }
        }

        private mutating func decodePointer(sizeCode: Int, offset: inout Int) throws -> Int {
            let prefix = sizeCode & 0x07
            let pointerSize = (sizeCode >> 3) & 0x03
            switch pointerSize {
            case 0:
                return (prefix << 8) | Int(try readByte(at: &offset))
            case 1:
                return 2_048
                    + (prefix << 16)
                    + (Int(try readByte(at: &offset)) << 8)
                    + Int(try readByte(at: &offset))
            case 2:
                return 526_336
                    + (prefix << 24)
                    + (Int(try readByte(at: &offset)) << 16)
                    + (Int(try readByte(at: &offset)) << 8)
                    + Int(try readByte(at: &offset))
            case 3:
                return Int(try readUnsigned(at: &offset, count: 4))
            default:
                throw DatabaseError.corruptData
            }
        }

        private mutating func decodeSize(_ sizeCode: Int, offset: inout Int) throws -> Int {
            switch sizeCode {
            case 0...28:
                return sizeCode
            case 29:
                return 29 + Int(try readByte(at: &offset))
            case 30:
                return 285 + Int(try readUnsigned(at: &offset, count: 2))
            case 31:
                return 65_821 + Int(try readUnsigned(at: &offset, count: 3))
            default:
                throw DatabaseError.corruptData
            }
        }

        private mutating func readByte(at offset: inout Int) throws -> UInt8 {
            guard offset >= 0, offset < bytes.count else { throw DatabaseError.corruptData }
            defer { offset += 1 }
            return bytes[offset]
        }

        private mutating func readBytes(at offset: inout Int, count: Int) throws -> [UInt8] {
            guard count >= 0, offset >= 0, offset + count <= bytes.count else {
                throw DatabaseError.corruptData
            }
            defer { offset += count }
            return Array(bytes[offset..<(offset + count)])
        }

        private mutating func readString(at offset: inout Int, count: Int) throws -> String {
            let value = try readBytes(at: &offset, count: count)
            guard let string = String(bytes: value, encoding: .utf8) else {
                throw DatabaseError.corruptData
            }
            return string
        }

        private mutating func readUnsigned(at offset: inout Int, count: Int) throws -> UInt64 {
            guard (0...8).contains(count) else { throw DatabaseError.unsupportedFormat }
            let value = try readBytes(at: &offset, count: count)
            return value.reduce(0) { ($0 << 8) | UInt64($1) }
        }
    }
}

struct MaxMindGeoRecord: Equatable, Sendable {
    var country: String?
    var city: String?
    var asn: String?
    var organization: String?

    init(
        country: String? = nil,
        city: String? = nil,
        asn: String? = nil,
        organization: String? = nil
    ) {
        self.country = country
        self.city = city
        self.asn = asn
        self.organization = organization
    }

    init(
        value: MaxMindDatabase.Value,
        language: AppLanguage = .english
    ) {
        country = value.value(at: "country", "iso_code")?.stringValue
            ?? value.value(at: "registered_country", "iso_code")?.stringValue
        city = Self.localizedCityName(in: value, language: language)

        if let number = value.value(at: "autonomous_system_number")?.unsignedValue
            ?? value.value(at: "traits", "autonomous_system_number")?.unsignedValue {
            asn = "AS\(number)"
        } else {
            asn = nil
        }

        organization = value.value(at: "autonomous_system_organization")?.stringValue
            ?? value.value(at: "traits", "autonomous_system_organization")?.stringValue
            ?? value.value(at: "traits", "organization")?.stringValue
            ?? value.value(at: "traits", "isp")?.stringValue
    }

    private static func localizedCityName(
        in value: MaxMindDatabase.Value,
        language: AppLanguage
    ) -> String? {
        guard let names = value.value(at: "city", "names")?.mapValue else { return nil }
        let preferredKeys: [String]
        if MicaStrings.resolvedLanguageCode(for: language) == AppLanguage.simplifiedChinese.rawValue {
            preferredKeys = ["zh-CN", "zh", "en"]
        } else {
            preferredKeys = ["en", "zh-CN", "zh"]
        }
        return preferredKeys.lazy.compactMap { names[$0]?.stringValue }.first
    }

    var isEmpty: Bool {
        country == nil && city == nil && asn == nil && organization == nil
    }

    mutating func merge(_ other: MaxMindGeoRecord) {
        country = country ?? other.country
        city = city ?? other.city
        asn = asn ?? other.asn
        organization = organization ?? other.organization
    }
}
