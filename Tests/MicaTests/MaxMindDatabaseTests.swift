import Foundation
import Testing
@testable import Mica

struct MaxMindDatabaseTests {
    @Test func uint128ValuesUpToSixteenBytesDoNotAbortValidRecords() throws {
        for byteCount in [9, 16] {
            let database = try MaxMindDatabase(data: databaseData(uint128ByteCount: byteCount))
            #expect(database.databaseType == "Test")
            let value = try #require(try database.lookup("1.1.1.1"))
            #expect(MaxMindGeoRecord(value: value).city == "Test City")

            guard case let .unsigned128(bytes) = value.value(at: "uint128_value") else {
                Issue.record("Expected a parsed uint128 value")
                continue
            }
            #expect(bytes.count == byteCount)
        }
    }

    @Test func cityNameSelectionUsesRequestedLanguageWithDeterministicFallback() {
        let value = MaxMindDatabase.Value.map([
            "city": .map([
                "names": .map([
                    "en": .string("Shanghai"),
                    "zh-CN": .string("上海"),
                ]),
            ]),
        ])

        #expect(MaxMindGeoRecord(value: value, language: .english).city == "Shanghai")
        #expect(MaxMindGeoRecord(value: value, language: .simplifiedChinese).city == "上海")

        let englishOnly = MaxMindDatabase.Value.map([
            "city": .map(["names": .map(["en": .string("London")])]),
        ])
        #expect(MaxMindGeoRecord(value: englishOnly, language: .simplifiedChinese).city == "London")
    }

    private func databaseData(uint128ByteCount: Int) -> Data {
        var record: [UInt8] = [0xE2]
        record += encodedString("city")
        record += [0xE1]
        record += encodedString("names")
        record += [0xE1]
        record += encodedString("en")
        record += encodedString("Test City")
        record += encodedString("uint128_value")
        record += [UInt8(uint128ByteCount), 3]
        record += Array(repeating: 0xA5, count: uint128ByteCount)

        var metadata: [UInt8] = [0xE5]
        metadata += encodedString("binary_format_major_version")
        metadata += encodedUnsigned(type: 5, bytes: [2])
        metadata += encodedString("record_size")
        metadata += encodedUnsigned(type: 5, bytes: [24])
        metadata += encodedString("node_count")
        metadata += encodedUnsigned(type: 6, bytes: [1])
        metadata += encodedString("ip_version")
        metadata += encodedUnsigned(type: 5, bytes: [4])
        metadata += encodedString("database_type")
        metadata += encodedString("Test")

        let marker: [UInt8] = [
            0xAB, 0xCD, 0xEF, 0x4D, 0x61, 0x78, 0x4D,
            0x69, 0x6E, 0x64, 0x2E, 0x63, 0x6F, 0x6D,
        ]
        let searchTree: [UInt8] = [0, 0, 17, 0, 0, 1]
        return Data(searchTree + Array(repeating: 0, count: 16) + record + marker + metadata)
    }

    private func encodedString(_ value: String) -> [UInt8] {
        let bytes = Array(value.utf8)
        precondition(bytes.count <= 28)
        return [0x40 | UInt8(bytes.count)] + bytes
    }

    private func encodedUnsigned(type: UInt8, bytes: [UInt8]) -> [UInt8] {
        precondition((5...7).contains(type))
        precondition(bytes.count <= 28)
        return [(type << 5) | UInt8(bytes.count)] + bytes
    }
}
