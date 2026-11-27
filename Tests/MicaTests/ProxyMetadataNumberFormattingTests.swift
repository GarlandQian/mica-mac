import Foundation
import MicaCore
import Testing
@testable import Mica

@MainActor
struct ProxyMetadataNumberFormattingTests {
    @Test func integerBoundaryValuesRemainRepresentableWithoutOverflow() throws {
        let upperBoundary = 9_223_372_036_854_775_808.0
        let lowerBoundary = -9_223_372_036_854_775_808.0

        #expect(MicaFormatters.formatMetadataNumber(upperBoundary.nextDown)
            == "9223372036854774784")
        #expect(MicaFormatters.formatMetadataNumber(lowerBoundary)
            == "-9223372036854775808")
        #expect(MicaFormatters.formatMetadataNumber(lowerBoundary.nextUp)
            == "-9223372036854774784")

        for value in [upperBoundary, upperBoundary.nextUp, lowerBoundary.nextDown] {
            let displayed = MicaFormatters.formatMetadataNumber(value)
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
            #expect(MicaFormatters.formatMetadataNumber(value) == expected)
        }
    }

    @Test func nonFiniteValuesRemainVisibleWhenProvidedDirectly() {
        #expect(MicaFormatters.formatMetadataNumber(.infinity) == "inf")
        #expect(MicaFormatters.formatMetadataNumber(-.infinity) == "-inf")
        #expect(MicaFormatters.formatMetadataNumber(.nan) == "nan")
    }
}
