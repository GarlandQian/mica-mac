import Foundation
import MicaCore

/// Projects only fields that the controller actually published. Recognizing a
/// protocol never supplies defaults or loads a separate configuration source.
enum ProxyProtocolInspectionProjection {
    struct Result: Equatable {
        let runtimeFields: [OverviewPolicyInspectionField]
        let parameters: [OverviewPolicyInspectionField]
        let testingFields: [OverviewPolicyInspectionField]
        let additionalFields: [OverviewPolicyInspectionField]
    }

    private struct Parameter {
        let titleKey: String
        let order: Int
    }

    private enum PathComponent {
        case key(String)
        case index(Int)

        var identifier: String {
            switch self {
            case .key(let key):
                // Keep object keys distinct from both separators and the
                // bracketed components reserved for actual array indices.
                key.replacingOccurrences(of: "~", with: "~0")
                    .replacingOccurrences(of: "/", with: "~1")
                    .replacingOccurrences(of: "[", with: "~2")
                    .replacingOccurrences(of: "]", with: "~3")
            case .index(let index):
                "[\(index)]"
            }
        }

        var displayText: String {
            switch self {
            case .key(let key):
                // A literal punctuation character must not look like a
                // nested property or array index in the inspector.
                key.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: ".", with: "\\.")
                    .replacingOccurrences(of: "[", with: "\\[")
                    .replacingOccurrences(of: "]", with: "\\]")
            case .index(let index):
                "[\(index)]"
            }
        }
    }

    static func project(
        detail: ProxyNodeViewState
    ) -> Result {
        var runtimeFields: [OverviewPolicyInspectionField] = []
        var parameters: [OverviewPolicyInspectionField] = []
        var testingFields: [OverviewPolicyInspectionField] = []
        var additionalFields: [OverviewPolicyInspectionField] = []
        let protocolType = normalizedKey(detail.type)
        let ordered = detail.reportedMetadata.sorted { left, right in
            let leftOrder = runtimeField(for: left.key)?.order
                ?? parameter(for: left.key, protocolType: protocolType)?.order ?? Int.max
            let rightOrder = runtimeField(for: right.key)?.order
                ?? parameter(for: right.key, protocolType: protocolType)?.order ?? Int.max
            return leftOrder == rightOrder ? left.key < right.key : leftOrder < rightOrder
        }

        for (key, value) in ordered {
            if key == "extra", case .object(let states) = value {
                // Mihomo publishes per-URL health state here. Other controller
                // extensions under the same key stay unclassified.
                for (url, state) in states.sorted(by: { $0.key < $1.key }) {
                    var fields: [OverviewPolicyInspectionField] = []
                    appendFields(
                        state,
                        path: [.key(key), .key(url)],
                        rootLabel: .verbatim(key),
                        protocolType: protocolType,
                        inheritedSensitivity: isSensitiveParameter(url, value: state, protocolType: protocolType),
                        to: &fields
                    )
                    if isURLTestState(url: url, value: state) {
                        testingFields.append(contentsOf: fields)
                    } else {
                        additionalFields.append(contentsOf: fields)
                    }
                }
            } else if let runtimeField = runtimeField(for: key) {
                appendFields(
                    value,
                    path: [.key(key)],
                    rootLabel: .localized(runtimeField.titleKey),
                    protocolType: protocolType,
                    inheritedSensitivity: isSensitiveParameter(key, value: value, protocolType: protocolType),
                    to: &runtimeFields
                )
            } else if let parameter = parameter(for: key, protocolType: protocolType) {
                appendFields(
                    value,
                    path: [.key(key)],
                    rootLabel: .localized(parameter.titleKey),
                    protocolType: protocolType,
                    inheritedSensitivity: isSensitiveParameter(key, value: value, protocolType: protocolType),
                    to: &parameters
                )
            } else {
                appendFields(
                    value,
                    path: [.key(key)],
                    rootLabel: .verbatim(PathComponent.key(key).displayText),
                    protocolType: protocolType,
                    inheritedSensitivity: isSensitiveParameter(key, value: value, protocolType: protocolType),
                    to: &additionalFields
                )
            }
        }

        return Result(
            runtimeFields: runtimeFields,
            parameters: parameters,
            testingFields: testingFields,
            additionalFields: additionalFields
        )
    }

    private static func runtimeField(for key: String) -> Parameter? {
        switch key {
        case "id": Parameter(titleKey: "routing.node_runtime_id", order: 0)
        case "routing-mark": Parameter(titleKey: "routing.node_runtime_routing_mark", order: 1)
        case "dialer-proxy": Parameter(titleKey: "routing.node_runtime_dialer_proxy", order: 2)
        default: nil
        }
    }

    private static func isURLTestState(url: String, value: MihomoJSONValue) -> Bool {
        guard let url = URL(string: url),
              ["http", "https"].contains(url.scheme?.lowercased()),
              url.host?.isEmpty == false,
              case .object(let state) = value else { return false }
        if case .bool? = state["alive"] { return true }
        if case .array? = state["history"] { return true }
        return false
    }

    private static func isSensitiveParameter(
        _ key: String,
        value: MihomoJSONValue,
        protocolType: String
    ) -> Bool {
        if isSensitiveKey(key) { return true }
        switch (protocolType, normalizedKey(key), value) {
        // Hysteria v1 reports an XPlus key here; v2 reports an obfuscation
        // method and keeps the credential in obfs-password instead.
        case ("hysteria", "obfs", .string), ("hysteria1", "obfs", .string),
             ("hy", "obfs", .string):
            return true
        // New VLESS encryption descriptions can contain an X25519 password.
        // The explicitly disabled value remains an ordinary visible option.
        case ("vless", "encryption", .string(let encryption)):
            return encryption.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "none"
        default:
            return false
        }
    }

    static func isSensitiveKey(_ key: String) -> Bool {
        let normalized = normalizedKey(key)
        return [
            "password", "passwords", "passwd", "pass", "passphrase", "secret", "secrets",
            "obfspassword", "auth", "authstr", "authkey", "authorization",
            "proxyauthorization", "authentication", "cookie", "setcookie", "credential",
            "credentials", "token", "accesstoken", "refreshtoken", "apikey",
            "xapikey", "xauthtoken", "privatekey", "privatekeypassword",
            "privatekeypassphrase", "clientkey", "presharedkey", "psk", "uuid", "key",
        ].contains(normalized)
    }

    private static func appendFields(
        _ value: MihomoJSONValue,
        path: [PathComponent],
        rootLabel: OverviewPolicyInspectionField.Label,
        protocolType: String,
        inheritedSensitivity: Bool,
        to fields: inout [OverviewPolicyInspectionField]
    ) {
        switch value {
        case .object(let object):
            for (key, child) in object.sorted(by: { $0.key < $1.key }) {
                appendFields(
                    child,
                    path: path + [.key(key)],
                    rootLabel: rootLabel,
                    protocolType: protocolType,
                    inheritedSensitivity: inheritedSensitivity
                        || isSensitiveParameter(key, value: child, protocolType: protocolType),
                    to: &fields
                )
            }
            return
        case .array(let array):
            for (index, child) in array.enumerated() {
                appendFields(
                    child,
                    path: path + [.index(index)],
                    rootLabel: rootLabel,
                    protocolType: protocolType,
                    inheritedSensitivity: inheritedSensitivity,
                    to: &fields
                )
            }
            return
        case .null:
            return
        case .string(let string) where string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return
        default:
            break
        }
        guard let text = ProxyReportedMetadataField.displayText(for: value) else { return }
        let identifier = path.map(\.identifier).joined(separator: "/")
        let reportedPath = path.map(\.displayText).joined(separator: ".")
        fields.append(
            OverviewPolicyInspectionField(
                id: "metadata.\(identifier)",
                label: path.count == 1 ? rootLabel : .verbatim(reportedPath),
                value: text,
                monospaced: true,
                isSensitive: inheritedSensitivity,
                reportedKey: reportedPath
            )
        )
    }

    private static func normalizedKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func parameter(for key: String, protocolType: String) -> Parameter? {
        let definition: (name: String, order: Int)
        switch normalizedKey(key) {
        case "server", "serveraddress", "serverhost", "hostname", "host":
            definition = ("server", 0)
        case "address", "addresses":
            definition = protocolType == "wireguard" || protocolType == "wg"
                ? ("interface_address", 30)
                : ("server", 0)
        case "port", "serverport": definition = ("port", 1)
        case "cipher", "method": definition = ("cipher", 2)
        case "encryption": definition = protocolType == "vless" ? ("encryption", 2) : ("cipher", 2)
        case "security": definition = ("security", 2)
        case "password", "passwd", "pass", "passphrase": definition = ("password", 3)
        case "uuid": definition = ("uuid", 4)
        case "username", "user": definition = ("username", 5)
        case "plugin": definition = ("plugin", 6)
        case "pluginopts", "pluginoptions": definition = ("plugin_options", 7)
        case "servername", "sni": definition = ("sni", 8)
        case "tls", "tlsopts", "tlsoptions": definition = ("tls", 9)
        case "network", "transport": definition = ("transport", 10)
        case "protocol": definition = ("protocol", 10)
        case "alterid": definition = ("alter_id", 11)
        case "flow": definition = ("flow", 12)
        case "auth": definition = ("authentication", 13)
        case "authstr": definition = ("authentication_string", 13)
        case "token": definition = ("token", 14)
        case "obfs", "obfuscation": definition = ("obfuscation", 15)
        case "obfspassword": definition = ("obfuscation_password", 16)
        case "up", "uploadbandwidth": definition = ("upload_bandwidth", 17)
        case "upmbps": definition = ("upload_mbps", 17)
        case "down", "downloadbandwidth": definition = ("download_bandwidth", 18)
        case "downmbps": definition = ("download_mbps", 18)
        case "congestioncontroller", "congestioncontrol": definition = ("congestion_control", 19)
        case "udprelaymode": definition = ("udp_relay_mode", 20)
        case "publickey": definition = ("public_key", 21)
        case "privatekey": definition = ("private_key", 22)
        case "presharedkey", "psk": definition = ("pre_shared_key", 23)
        case "peers": definition = ("peers", 24)
        case "allowedips": definition = ("allowed_ips", 25)
        case "reserved": definition = ("reserved", 26)
        case "ip", "ipv4", "ipv6", "localaddress", "localaddresses":
            definition = ("interface_address", 30)
        case "endpoint": definition = ("endpoint", 31)
        case "mtu": definition = ("mtu", 32)
        case "persistentkeepalive": definition = ("persistent_keepalive", 33)
        case "realityopts", "reality": definition = ("reality", 40)
        case "wsopts", "websocketopts": definition = ("websocket", 41)
        case "grpcopts": definition = ("grpc", 42)
        case "httpopts", "http2opts", "h2opts": definition = ("http_options", 43)
        case "ssopts": definition = ("shadowsocks_options", 44)
        case "alpn": definition = ("alpn", 45)
        case "skipcertverify", "insecure": definition = ("skip_certificate_verification", 46)
        case "fingerprint": definition = ("certificate_fingerprint", 47)
        case "clientfingerprint": definition = ("client_fingerprint", 48)
        case "disablesni": definition = ("disable_sni", 49)
        case "authenticatedlength": definition = ("authenticated_length", 50)
        case "globalpadding": definition = ("global_padding", 51)
        case "packetencoding": definition = ("packet_encoding", 52)
        case "udpovertcp": definition = ("udp_over_tcp", 53)
        case "udpovertcpversion": definition = ("udp_over_tcp_version", 54)
        case "reducertt", "zerortthandshake": definition = ("zero_rtt", 55)
        case "requesttimeout": definition = ("request_timeout", 56)
        case "heartbeatinterval": definition = ("heartbeat_interval", 57)
        case "recvwindowconn": definition = ("connection_receive_window", 58)
        case "recvwindow": definition = ("receive_window", 59)
        case "disablemtudiscovery": definition = ("disable_mtu_discovery", 60)
        case "fastopen": definition = ("fast_open", 61)
        case "headers": definition = ("headers", 62)
        default:
            return nil
        }
        return Parameter(titleKey: "routing.node_parameter_\(definition.name)", order: definition.order)
    }
}
