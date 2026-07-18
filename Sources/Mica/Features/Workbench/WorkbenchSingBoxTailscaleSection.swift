import Foundation
import MicaCore
import SwiftUI

struct WorkbenchSingBoxTailscaleSection: View {
    var appModel: AppModel

    @Environment(\.micaAppLanguage) private var appLanguage

    var body: some View {
        Section {
            if let status = appModel.singBoxTailscaleStatus {
                if let error = appModel.singBoxTailscaleError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(MicaStyle.signalAmber)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if status.endpoints.isEmpty {
                    ContentUnavailableView {
                        Label(
                            MicaStrings.localizedKey("tailscale.no_endpoints_title", language: appLanguage),
                            systemImage: "network.slash"
                        )
                    } description: {
                        Text(MicaStrings.localizedKey("tailscale.no_endpoints_detail", language: appLanguage))
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ForEach(Array(status.endpoints.enumerated()), id: \.offset) { _, endpoint in
                        SingBoxTailscaleEndpointView(appModel: appModel, endpoint: endpoint)
                    }
                }
            } else if let error = appModel.singBoxTailscaleError {
                ContentUnavailableView {
                    Label(
                        MicaStrings.localizedKey("tailscale.stream_error_title", language: appLanguage),
                        systemImage: "exclamationmark.triangle"
                    )
                } description: {
                    Text(
                        MicaStrings.localized(
                            "tailscale.stream_error_detail \(error)",
                            language: appLanguage
                        )
                    )
                    .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(MicaStrings.localizedKey("tailscale.loading", language: appLanguage))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 72)
            }
        } header: {
            MicaText("diagnostics.operation_tailscale")
        } footer: {
            MicaText("diagnostics.operation_tailscale_detail")
        }
    }
}

private struct SingBoxTailscaleEndpointView: View {
    var appModel: AppModel
    let endpoint: SingBoxTailscaleEndpoint

    @Environment(\.micaAppLanguage) private var appLanguage
    @State private var pendingExitNodeID: String?

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                detailRow("tailscale.endpoint_tag", value: endpoint.endpointTag)
                detailRow("tailscale.backend_state", value: endpoint.backendState)
                detailRow("tailscale.network_name", value: endpoint.networkName)
                detailRow("tailscale.magic_dns_suffix", value: endpoint.magicDNSSuffix)
                detailRow("tailscale.authentication_url", value: endpoint.authenticationURL)
                detailRow(
                    "tailscale.key_authentication",
                    value: booleanLabel(endpoint.usesKeyAuthentication)
                )

                if let selfPeer = endpoint.selfPeer {
                    Divider()
                    peerDisclosure(
                        titleKey: "tailscale.current_device",
                        peer: selfPeer
                    )
                }

                if !exitNodeCandidates.isEmpty {
                    Divider()
                    Picker(
                        MicaStrings.localizedKey("tailscale.exit_node_candidates", language: appLanguage),
                        selection: exitNodeSelection
                    ) {
                        Text(MicaStrings.localizedKey("tailscale.exit_node_none", language: appLanguage))
                            .tag("")
                        ForEach(Array(exitNodeCandidates.enumerated()), id: \.offset) { _, peer in
                            Text(verbatim: peerTitle(peer))
                                .tag(peer.stableID)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .disabled(appModel.isBusy)
                    .accessibilityLabel(
                        MicaStrings.localizedKey("tailscale.exit_node_candidates", language: appLanguage)
                    )
                } else if let exitNode = endpoint.exitNode {
                    Divider()
                    peerDisclosure(titleKey: "tailscale.exit_node", peer: exitNode)
                }

                ForEach(Array(endpoint.userGroups.enumerated()), id: \.offset) { _, group in
                    Divider()
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            detailRow("tailscale.user_id", value: String(group.userID))
                            detailRow("tailscale.login_name", value: group.loginName)
                            detailRow("tailscale.display_name", value: group.displayName)
                            detailRow("tailscale.profile_picture_url", value: group.profilePictureURL)

                            ForEach(Array(group.peers.enumerated()), id: \.offset) { _, peer in
                                peerDisclosure(titleKey: "tailscale.peer", peer: peer)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Label(groupTitle(group), systemImage: "person.2")
                    }
                }

                if endpoint.selfPeer != nil {
                    Divider()
                    HStack {
                        Spacer()
                        Button {
                            appModel.logoutSingBoxTailscale(endpointTag: endpoint.endpointTag)
                        } label: {
                            Label(
                                MicaStrings.localizedKey("tailscale.logout", language: appLanguage),
                                systemImage: "rectangle.portrait.and.arrow.right"
                            )
                        }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                        .disabled(appModel.isBusy)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: endpointTitle)
                        .fontWeight(.medium)
                        .textSelection(.enabled)
                    Text(verbatim: endpoint.backendState.nilIfEmpty ?? endpoint.endpointTag)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .onChange(of: endpoint.exitNode?.stableID) { _, newValue in
            if pendingExitNodeID == newValue {
                pendingExitNodeID = nil
            }
        }
        .onChange(of: appModel.runningRuntimeOperationID) { _, newValue in
            if newValue == nil {
                pendingExitNodeID = nil
            }
        }
    }

    private var endpointTitle: String {
        endpoint.networkName.nilIfEmpty
            ?? endpoint.endpointTag.nilIfEmpty
            ?? MicaStrings.localizedKey("diagnostics.operation_tailscale", language: appLanguage)
    }

    private var exitNodeSelection: Binding<String> {
        Binding(
            get: { pendingExitNodeID ?? endpoint.exitNode?.stableID ?? "" },
            set: { stableID in
                guard stableID != (pendingExitNodeID ?? endpoint.exitNode?.stableID ?? "") else {
                    return
                }
                pendingExitNodeID = stableID
                appModel.setSingBoxTailscaleExitNode(
                    endpointTag: endpoint.endpointTag,
                    stableID: stableID
                )
            }
        )
    }

    private var exitNodeCandidates: [SingBoxTailscalePeer] {
        var seen: Set<String> = []
        var peers: [SingBoxTailscalePeer] = []

        if let current = endpoint.exitNode,
           !current.stableID.isEmpty,
           seen.insert(current.stableID).inserted {
            peers.append(current)
        }

        for group in endpoint.userGroups {
            for peer in group.peers where peer.canBeExitNode && !peer.stableID.isEmpty {
                if seen.insert(peer.stableID).inserted {
                    peers.append(peer)
                }
            }
        }

        return peers
    }

    private func groupTitle(_ group: SingBoxTailscaleUserGroup) -> String {
        group.displayName.nilIfEmpty
            ?? group.loginName.nilIfEmpty
            ?? String(group.userID)
    }

    private func peerTitle(_ peer: SingBoxTailscalePeer) -> String {
        peer.hostName.nilIfEmpty
            ?? peer.dnsName.nilIfEmpty
            ?? peer.stableID
    }

    private func peerDisclosure(
        titleKey: String,
        peer: SingBoxTailscalePeer
    ) -> some View {
        DisclosureGroup {
            SingBoxTailscalePeerDetailsView(peer: peer)
                .padding(.top, 6)
        } label: {
            LabeledContent(MicaStrings.localizedKey(titleKey, language: appLanguage)) {
                Text(verbatim: peerTitle(peer))
                    .textSelection(.enabled)
            }
        }
    }

    private func detailRow(_ titleKey: String, value: String) -> some View {
        LabeledContent(MicaStrings.localizedKey(titleKey, language: appLanguage)) {
            Text(verbatim: value.nilIfEmpty ?? unavailableValue)
                .foregroundStyle(value.nilIfEmpty == nil ? .secondary : .primary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func booleanLabel(_ value: Bool) -> String {
        MicaStrings.localizedKey(
            value ? "overview.config_enabled" : "overview.config_disabled",
            language: appLanguage
        )
    }

    private var unavailableValue: String {
        MicaStrings.localizedKey("overview.config_not_reported", language: appLanguage)
    }
}

private struct SingBoxTailscalePeerDetailsView: View {
    let peer: SingBoxTailscalePeer

    @Environment(\.micaAppLanguage) private var appLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            detailRow("tailscale.host_name", peer.hostName)
            detailRow("tailscale.dns_name", peer.dnsName)
            detailRow("tailscale.operating_system", peer.operatingSystem)
            detailRow("tailscale.ip_addresses", peer.ipAddresses.joined(separator: "\n"))
            detailRow("tailscale.online", booleanLabel(peer.online))
            detailRow("tailscale.active", booleanLabel(peer.active))
            detailRow("tailscale.exit_node", booleanLabel(peer.isExitNode))
            detailRow("tailscale.can_be_exit_node", booleanLabel(peer.canBeExitNode))
            detailRow("tailscale.received_bytes", String(peer.receivedBytes))
            detailRow("tailscale.transmitted_bytes", String(peer.transmittedBytes))
            detailRow("tailscale.key_expiry", String(peer.keyExpiry))
            detailRow("tailscale.stable_id", peer.stableID)
            detailRow("tailscale.expired", booleanLabel(peer.expired))
            detailRow("tailscale.ssh_host_keys", peer.sshHostKeys.joined(separator: "\n"))
            detailRow("tailscale.sharee_node", booleanLabel(peer.isShareeNode))
            detailRow("tailscale.last_seen", String(peer.lastSeen))
        }
    }

    private func detailRow(_ titleKey: String, _ value: String) -> some View {
        LabeledContent(MicaStrings.localizedKey(titleKey, language: appLanguage)) {
            Text(verbatim: value.nilIfEmpty ?? unavailableValue)
                .foregroundStyle(value.nilIfEmpty == nil ? .secondary : .primary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func booleanLabel(_ value: Bool) -> String {
        MicaStrings.localizedKey(
            value ? "overview.config_enabled" : "overview.config_disabled",
            language: appLanguage
        )
    }

    private var unavailableValue: String {
        MicaStrings.localizedKey("overview.config_not_reported", language: appLanguage)
    }
}
