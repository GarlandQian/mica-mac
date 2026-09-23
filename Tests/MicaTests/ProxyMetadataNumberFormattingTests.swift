import Foundation
import MicaCore
import Testing
@testable import Mica

@MainActor
struct ProxyMetadataNumberFormattingTests {
    @Test func integerBoundaryValuesRemainRepresentableWithoutOverflow() throws {
        let upperBoundary = 9_223_372_036_854_775_808.0
        let lowerBoundary = -9_223_372_036_854_775_808.0

        // The upper boundary is also Double(Int64.max), which has rounded up
        // past the representable integer range. Its nearest lower Double is
        // still an exactly representable Int64.
        #expect(ProxyReportedMetadataField.displayText(for: .number(upperBoundary.nextDown))
            == "9223372036854774784")
        #expect(ProxyReportedMetadataField.displayText(for: .number(lowerBoundary))
            == "-9223372036854775808")
        #expect(ProxyReportedMetadataField.displayText(for: .number(lowerBoundary.nextUp))
            == "-9223372036854774784")

        for value in [upperBoundary, upperBoundary.nextUp, lowerBoundary.nextDown] {
            let displayed = try #require(
                ProxyReportedMetadataField.displayText(for: .number(value))
            )
            #expect(Double(displayed) == value)
        }
    }

    @Test func ordinaryIntegersAndFractionsKeepTheirReportedValue() {
        for (value, expected) in [
            (0.0, "0"),
            (-1.0, "-1"),
            (443.0, "443"),
            (0.5, "0.5"),
            (-12.75, "-12.75"),
        ] {
            #expect(ProxyReportedMetadataField.displayText(for: .number(value)) == expected)
        }
    }

    @Test func nonFiniteValuesRemainVisibleWhenProvidedDirectly() {
        #expect(ProxyReportedMetadataField.displayText(for: .number(.infinity)) == "inf")
        #expect(ProxyReportedMetadataField.displayText(for: .number(-.infinity)) == "-inf")
        #expect(ProxyReportedMetadataField.displayText(for: .number(.nan)) == "nan")
    }
}
