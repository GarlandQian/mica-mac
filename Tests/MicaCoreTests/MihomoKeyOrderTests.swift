import Foundation
import XCTest
@testable import MicaCore

final class MihomoKeyOrderTests: XCTestCase {
    func testOrderSkipsNestedValuesWithoutInterpretingTheirPunctuation() throws {
        let data = Data(#"""
        {
          "ignored": [{"proxies": {"wrong": true}}, "}\"\\[", 123, false, null],
          "pr\u006fxies": {
            "末尾/🇭🇰": {"type":"Direct", "extra":{"a":["}\"\\[",{"b":"节点"}]}},
            "Quote \" and \\ and \uD83C\uDF38": {"type":"Direct"},
            "a\nb\tc": {"type":"Direct"},
            "First alphabetically": {"type":"Direct"}
          },
          "other": {"proxies":{"also wrong": null}}
        }
        """#.utf8)
        let response = try ProxiesResponse.decodePreservingProxyOrder(from: data)
        XCTAssertEqual(response.proxyOrder, ["末尾/🇭🇰", "Quote \" and \\ and 🌸", "a\nb\tc", "First alphabetically"])
        XCTAssertEqual(response.proxies.count, 4)
    }

    func testOrderScanDoesNotBypassResponseValidation() {
        for body in [#"{"proxies":{"broken":{"type":"Direct","extra":"\q"}}}"#,
                     #"{"proxies":{"broken":{"type":"Direct"}}"#] {
            XCTAssertThrowsError(try ProxiesResponse.decodePreservingProxyOrder(from: Data(body.utf8)))
        }
    }
}
