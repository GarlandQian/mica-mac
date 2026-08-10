import Foundation
import MicaCore
import SwiftUI

// MARK: - sing-box Tailscale

struct WorkbenchSingBoxTailscaleSection: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    var body: some View {
        Section {
            if let status = appModel.singBoxTailscaleStatus {
                if let error = appModel.singBoxTailscaleError {
                    Label {
                        Text(verbatim: error)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .micaFont(.caption)
                    .foregroundStyle(MicaDesignTokens.signalAmber)

                    if !status.endpoints.isEmpty { Divider() }
                }

                if status.endpoints.isEmpty {
                    inlineState(
                        symbol: "network.slash",
                        titleKey: "tailscale.no_endpoints_title",
                        detail: MicaStrings.localizedKey(
                            "tailscale.no_endpoints_detail",
                            language: language
                        )
                    )
                } else {
                    ForEach(Array(status.endpoints.enumerated()), id: \.element.id) { index, endpoint in
                        if index > 0 { Divider() }
                        WorkbenchTailscaleEndpointView(
                            controllerID: appModel.selectedRouterID,
                            generation: appModel.controllerSessionPresentation.generation,
                            endpoint: endpoint
                        )
                    }
                }
            } else if let error = appModel.singBoxTailscaleError {
                inlineState(
                    symbol: "exclamationmark.triangle",
                    titleKey: "tailscale.stream_error_title",
                    detail: MicaStrings.localized(
                        "tailscale.stream_error_detail \(error)",
                        language: language
                    )
                )
            } else {
                HStack(spacing: MicaSpacing.row) {
                    ProgressView()
                        .controlSize(.small)
                    Text(MicaStrings.localizedKey("tailscale.loading", language: language))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            }
        } header: {
            Label(
                MicaStrings.localizedKey(
                    "diagnostics.operation_tailscale",
                    language: language
                ),
                systemImage: "network"
            )
        } footer: {
            Text(
                MicaStrings.localizedKey(
                    "diagnostics.operation_tailscale_detail",
                    language: language
                )
            )
        }
    }

    private func inlineState(
        symbol: String,
        titleKey: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: MicaSpacing.module) {
            Image(systemName: symbol)
                .micaFont(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: MicaSpacing.tight) {
                Text(MicaStrings.localizedKey(titleKey, language: language))
                    .micaFont(.callout, weight: .semibold)
                Text(verbatim: detail)
                    .micaFont(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
    }
}

private struct WorkbenchTailscaleEndpointView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var language

    let controllerID: RouterProfile.ID?
    let generation: UUID
    let endpoint: SingBoxTailscaleEndpoint

    @State private var pendingExitNodeID: String?
    @State private var confirmsLogout = false

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: MicaSpacing.row) {
                detailRow("tailscale.endpoint_tag", endpoint.endpointTag)
                detailRow("tailscale.backend_state", endpoint.backendState)
                detailRow("tailscale.network_name", endpoint.networkName)
                detailRow("tailscale.magic_dns_suffix", endpoint.magicDNSSuffix)
                authenticationURLRow
                detailRow(
                    "tailscale.key_authentication",
                    booleanLabel(endpoint.usesKeyAuthentication)
                )

                if let peer = endpoint.selfPeer {
                    Divider()
                    peerDisclosure("tailscale.current_device", peer: peer)
                }

                if !exitNodeCandidates.isEmpty {
                    Divider()
                    WorkbenchFormRow("tailscale.exit_node_candidates") {
                        Picker(
                            MicaStrings.localizedKey(
                                "tailscale.exit_node_candidates",
                                language: language
                            ),
                            selection: exitNodeSelection
                        ) {
                            Text(
                                MicaStrings.localizedKey(
                                    "tailscale.exit_node_none",
                                    language: language
                                )
                            )
                            .tag("")

                            ForEach(exitNodeCandidates) { peer in
                                Text(verbatim: peerTitle(peer)).tag(peer.stableID)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: MicaBounds.formControlMax, alignment: .leading)
                        .disabled(appModel.isBusy)
                    }
                } else if let peer = endpoint.exitNode {
                    Divider()
                    peerDisclosure("tailscale.exit_node", peer: peer)
                }

                ForEach(endpoint.userGroups) { group in
                    Divider()
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: MicaSpacing.row) {
                            detailRow("tailscale.user_id", String(group.userID))
                            detailRow("tailscale.login_name", group.loginName)
                            detailRow("tailscale.display_name", group.displayName)
                            detailRow("tailscale.profile_picture_url", group.profilePictureURL)

                            ForEach(group.peers) { peer in
                                peerDisclosure("tailscale.peer", peer: peer)
                            }
                        }
                        .padding(.top, MicaSpacing.row)
                    } label: {
                        Label(groupTitle(group), systemImage: "person.2")
                            .textSelection(.enabled)
                    }
                }

                if endpoint.selfPeer != nil {
                    Divider()
                    logoutControls
                }
            }
            .padding(.top, MicaSpacing.row)
        } label: {
            HStack(spacing: MicaSpacing.row) {
                Image(systemName: "network")
                    .foregroundStyle(MicaDesignTokens.signalCyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: endpointTitle)
                        .micaFont(.callout, weight: .semibold)
                        .textSelection(.enabled)
                    Text(verbatim: endpoint.backendState.managementNonEmpty ?? endpoint.endpointTag)
                        .micaFont(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .onChange(of: endpoint.exitNode?.stableID) { _, next in
            if pendingExitNodeID == next { pendingExitNodeID = nil }
        }
        .onChange(of: appModel.runningRuntimeOperationID) { _, next in
            if next == nil { pendingExitNodeID = nil }
        }
        .onChange(of: appModel.selectedRouterID) { _, next in
            if next != controllerID {
                pendingExitNodeID = nil
                confirmsLogout = false
            }
        }
        .onChange(of: appModel.controllerSessionPresentation.generation) { _, next in
            if next != generation {
                pendingExitNodeID = nil
                confirmsLogout = false
            }
        }
    }

    @ViewBuilder
    private var logoutControls: some View {
        if confirmsLogout {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: MicaSpacing.row) { logoutConfirmationContent }
                VStack(alignment: .leading, spacing: MicaSpacing.row) {
                    logoutConfirmationContent
                }
            }
        } else {
            HStack {
                Spacer(minLength: 0)
                Button {
                    if isCurrentSession { confirmsLogout = true }
                } label: {
                    Label(
                        MicaStrings.localizedKey("tailscale.logout", language: language),
                        systemImage: "rectangle.portrait.and.arrow.right"
                    )
                    .frame(minHeight: MicaBounds.controlMinHeight)
                }
                .buttonStyle(.bordered)
                .disabled(appModel.isBusy)
            }
        }
    }

    @ViewBuilder
    private var logoutConfirmationContent: some View {
        Text(MicaStrings.localizedKey("tailscale.logout", language: language))
            .foregroundStyle(MicaDesignTokens.signalRed)

        Spacer(minLength: MicaSpacing.row)

        Button(MicaStrings.localizedKey("action.cancel", language: language)) {
            confirmsLogout = false
        }
        .frame(minHeight: MicaBounds.controlMinHeight)

        Button(
            MicaStrings.localizedKey("tailscale.logout", language: language),
            role: .destructive
        ) {
            confirmsLogout = false
            guard isCurrentSession else { return }
            appModel.logoutSingBoxTailscale(endpointTag: endpoint.endpointTag)
        }
        .buttonStyle(.borderedProminent)
        .tint(MicaDesignTokens.signalRed)
        .disabled(appModel.isBusy)
        .frame(minHeight: MicaBounds.controlMinHeight)
    }

    private var endpointTitle: String {
        endpoint.networkName.managementNonEmpty
            ?? endpoint.endpointTag.managementNonEmpty
            ?? MicaStrings.localizedKey("diagnostics.operation_tailscale", language: language)
    }

    private var exitNodeSelection: Binding<String> {
        Binding(
            get: { pendingExitNodeID ?? endpoint.exitNode?.stableID ?? "" },
            set: { next in
                guard isCurrentSession else { return }
                guard next != (pendingExitNodeID ?? endpoint.exitNode?.stableID ?? "") else {
                    return
                }
                pendingExitNodeID = next
                appModel.setSingBoxTailscaleExitNode(
                    endpointTag: endpoint.endpointTag,
                    stableID: next
                )
            }
        )
    }

    private var exitNodeCandidates: [SingBoxTailscalePeer] {
        var seen = Set<String>()
        var peers: [SingBoxTailscalePeer] = []

        if let current = endpoint.exitNode,
           current.stableID.managementNonEmpty != nil,
           seen.insert(current.stableID).inserted {
            peers.append(current)
        }

        for group in endpoint.userGroups {
            for peer in group.peers
                where peer.canBeExitNode
                    && peer.stableID.managementNonEmpty != nil
                    && seen.insert(peer.stableID).inserted {
                peers.append(peer)
            }
        }

        return peers
    }

    private var isCurrentSession: Bool {
        appModel.selectedRouterID == controllerID
            && appModel.controllerSessionPresentation.generation == generation
            && permitsMutation
    }

    private var permitsMutation: Bool {
        switch appModel.controllerSessionPresentation.state {
        case .live, .partial:
            true
        case .idle, .connecting, .staleReconnecting, .failedBeforeFirstSnapshot,
             .failed, .stopped:
            false
        }
    }

    private func groupTitle(_ group: SingBoxTailscaleUserGroup) -> String {
        group.displayName.managementNonEmpty
            ?? group.loginName.managementNonEmpty
            ?? String(group.userID)
    }

    private func peerTitle(_ peer: SingBoxTailscalePeer) -> String {
        peer.hostName.managementNonEmpty
            ?? peer.dnsName.managementNonEmpty
            ?? peer.stableID
    }

    private func peerDisclosure(_ titleKey: String, peer: SingBoxTailscalePeer) -> some View {
        DisclosureGroup {
            WorkbenchTailscalePeerDetails(peer: peer)
                .padding(.top, MicaSpacing.row)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: MicaSpacing.row) {
                Text(MicaStrings.localizedKey(titleKey, language: language))
                    .micaFont(.caption, weight: .medium)
                    .foregroundStyle(.secondary)

                Text(verbatim: peerTitle(peer))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailRow(_ titleKey: String, _ value: String) -> some View {
        WorkbenchFormRow(titleKey) {
            WorkbenchFormValue(
                value: value.managementNonEmpty
                    ?? MicaStrings.localizedKey("overview.config_not_reported", language: language),
                placeholder: value.managementNonEmpty == nil
            )
        }
    }

    private var authenticationURLRow: some View {
        WorkbenchFormRow("tailscale.authentication_url") {
            HStack(alignment: .center, spacing: MicaSpacing.row) {
                WorkbenchFormValue(
                    value: endpoint.authenticationURL.managementNonEmpty == nil
                        ? MicaStrings.localizedKey(
                            "overview.config_not_reported",
                            language: language
                        )
                        : endpoint.authenticationURL,
                    monospaced: true,
                    placeholder: endpoint.authenticationURL.managementNonEmpty == nil
                )

                if let authenticationLinkURL {
                    Link(destination: authenticationLinkURL) {
                        Image(systemName: "arrow.up.right.square")
                            .frame(
                                width: MicaBounds.iconControlSize,
                                height: MicaBounds.iconControlSize
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help(
                        MicaStrings.localizedKey(
                            "tailscale.authentication_url",
                            language: language
                        )
                    )
                    .accessibilityLabel(
                        MicaStrings.localizedKey(
                            "tailscale.authentication_url",
                            language: language
                        )
                    )
                }
            }
        }
    }

    private var authenticationLinkURL: URL? {
        guard let value = endpoint.authenticationURL.managementNonEmpty,
              let url = URL(string: value),
              url.scheme?.isEmpty == false else {
            return nil
        }
        return url
    }

    private func booleanLabel(_ value: Bool) -> String {
        MicaStrings.localizedKey(
            value ? "overview.config_enabled" : "overview.config_disabled",
            language: language
        )
    }
}

private struct WorkbenchTailscalePeerDetails: View {
    @Environment(\.micaAppLanguage) private var language

    let peer: SingBoxTailscalePeer

    var body: some View {
        VStack(alignment: .leading, spacing: MicaSpacing.row) {
            row("tailscale.host_name", peer.hostName)
            row("tailscale.dns_name", peer.dnsName)
            row("tailscale.operating_system", peer.operatingSystem)
            row("tailscale.ip_addresses", peer.ipAddresses.joined(separator: "\n"))
            row("tailscale.online", booleanLabel(peer.online))
            row("tailscale.active", booleanLabel(peer.active))
            row("tailscale.exit_node", booleanLabel(peer.isExitNode))
            row("tailscale.can_be_exit_node", booleanLabel(peer.canBeExitNode))
            row("tailscale.received_bytes", byteString(peer.receivedBytes))
            row("tailscale.transmitted_bytes", byteString(peer.transmittedBytes))
            row("tailscale.key_expiry", String(peer.keyExpiry))
            row("tailscale.stable_id", peer.stableID)
            row("tailscale.expired", booleanLabel(peer.expired))
            row("tailscale.ssh_host_keys", peer.sshHostKeys.joined(separator: "\n"))
            row("tailscale.sharee_node", booleanLabel(peer.isShareeNode))
            row("tailscale.last_seen", String(peer.lastSeen))
        }
    }

    private func row(_ titleKey: String, _ value: String) -> some View {
        WorkbenchFormRow(titleKey) {
            WorkbenchFormValue(
                value: value.managementNonEmpty
                    ?? MicaStrings.localizedKey("overview.config_not_reported", language: language),
                monospaced: true,
                placeholder: value.managementNonEmpty == nil
            )
        }
    }

    private func booleanLabel(_ value: Bool) -> String {
        MicaStrings.localizedKey(
            value ? "overview.config_enabled" : "overview.config_disabled",
            language: language
        )
    }

    private func byteString(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
    }
}
