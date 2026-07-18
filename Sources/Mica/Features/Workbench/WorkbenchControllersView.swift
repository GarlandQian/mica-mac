import MicaCore
import SwiftUI

struct WorkbenchControllersView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.micaAppLanguage) private var appLanguage
    @Environment(\.micaFontMultiplier) private var fontMultiplier

    @State private var searchText = ""
    @State private var managementSelection: RouterProfile.ID?
    @State private var previousOrder: [RouterProfile.ID] = []
    @State private var pendingDelete: RouterProfile?

    let onAddController: () -> Void
    let onEditController: (RouterProfile) -> Void

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                Divider()

                if appModel.routers.isEmpty {
                    emptyState
                } else if visibleProfiles.isEmpty {
                    filteredEmptyState
                } else if tableMode(for: geometry.size.width) == .wide {
                    wideTable
                } else {
                    compactTable
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let pendingDelete {
                    deleteConfirmation(for: pendingDelete)
                }
            }
        }
        .onAppear {
            previousOrder = appModel.routers.map(\.id)
        }
        .onChange(of: appModel.routers.map(\.id)) { oldOrder, newOrder in
            managementSelection = ControllerManagementPresentation.reconciledManagementSelection(
                managementSelection,
                previousOrder: oldOrder,
                currentOrder: newOrder
            )
            previousOrder = newOrder
            if let pendingDelete, !newOrder.contains(pendingDelete.id) {
                self.pendingDelete = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ControllerManagementCopy.title(language: appLanguage))
                    .font(.title2.weight(.semibold))
                Text(ControllerManagementCopy.subtitle(language: appLanguage))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            Text(ControllerManagementCopy.count(appModel.routers.count, language: appLanguage))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            TextField(
                ControllerManagementCopy.searchPrompt(language: appLanguage),
                text: $searchText
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: min(320 * fontMultiplier, 420))

            Button(action: onAddController) {
                Label(ControllerManagementCopy.add(language: appLanguage), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(MicaStyle.accent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var visibleProfiles: [RouterProfile] {
        ControllerManagementPresentation.filteredProfiles(
            appModel.routers,
            matching: searchText,
            language: appLanguage
        )
    }

    private func tableMode(for width: CGFloat) -> ControllerTableMode {
        ControllerManagementPresentation.tableMode(
            availableWidth: width,
            fontMultiplier: fontMultiplier
        )
    }

    private var wideTable: some View {
        Table(visibleProfiles, selection: $managementSelection) {
            TableColumn(ControllerManagementCopy.active(language: appLanguage)) { profile in
                activeIndicator(for: profile)
            }
            .width(36)

            TableColumn(ControllerManagementCopy.name(language: appLanguage)) { profile in
                reorderableCell(for: profile) {
                    Text(profile.displayName)
                        .font(.body.weight(.medium))
                        .textSelection(.enabled)
                        .lineLimit(nil)
                }
            }
            .width(min: 130, ideal: 180)

            TableColumn(ControllerManagementCopy.endpoint(language: appLanguage)) { profile in
                Text(verbatim: profile.endpointURL)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .width(min: 240, ideal: 360)

            TableColumn(ControllerManagementCopy.type(language: appLanguage)) { profile in
                Text(profile.controllerKind.micaLabel(language: appLanguage))
                    .lineLimit(nil)
            }
            .width(min: 110, ideal: 140)

            TableColumn(ControllerManagementCopy.status(language: appLanguage)) { profile in
                statusLabel(for: profile)
            }
            .width(min: 120, ideal: 150)

            TableColumn(ControllerManagementCopy.lastSuccess(language: appLanguage)) { profile in
                lastSuccessLabel(for: profile)
            }
            .width(min: 130, ideal: 160)

            TableColumn(ControllerManagementCopy.actions(language: appLanguage)) { profile in
                actionStrip(for: profile)
            }
            .width(min: 220, ideal: 220, max: 232)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
    }

    private var compactTable: some View {
        Table(visibleProfiles, selection: $managementSelection) {
            TableColumn(ControllerManagementCopy.controller(language: appLanguage)) { profile in
                reorderableCell(for: profile) {
                    HStack(alignment: .top, spacing: 10) {
                        activeIndicator(for: profile)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(profile.displayName)
                                .font(.body.weight(.semibold))
                                .textSelection(.enabled)
                            Text(verbatim: profile.endpointURL)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(profile.controllerKind.micaLabel(language: appLanguage))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .width(min: 300, ideal: 440)

            TableColumn(ControllerManagementCopy.status(language: appLanguage)) { profile in
                VStack(alignment: .leading, spacing: 4) {
                    statusLabel(for: profile)
                    lastSuccessLabel(for: profile)
                }
                .padding(.vertical, 4)
            }
            .width(min: 150, ideal: 190)

            TableColumn(ControllerManagementCopy.actions(language: appLanguage)) { profile in
                actionStrip(for: profile)
            }
            .width(min: 220, ideal: 220, max: 232)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
    }

    private func activeIndicator(for profile: RouterProfile) -> some View {
        Image(systemName: appModel.selectedRouterID == profile.id ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(appModel.selectedRouterID == profile.id ? MicaStyle.signalMint : Color.secondary)
            .accessibilityLabel(
                appModel.selectedRouterID == profile.id
                    ? ControllerManagementCopy.active(language: appLanguage)
                    : profile.displayName
            )
    }

    private func status(for profile: RouterProfile) -> ControllerManagementStatus {
        ControllerManagementStatus.resolve(
            isActive: appModel.selectedRouterID == profile.id,
            connectionState: appModel.connectionState,
            controllerHealth: appModel.controllerHealth.summary,
            trialHealth: appModel.trialSession(for: profile).sessionHealth,
            language: appLanguage
        )
    }

    private func statusLabel(for profile: RouterProfile) -> some View {
        let status = status(for: profile)
        return Label(status.label, systemImage: status.symbolName)
            .font(.callout)
            .foregroundStyle(status.tint)
            .lineLimit(nil)
    }

    private func lastSuccessLabel(for profile: RouterProfile) -> some View {
        let date = appModel.selectedRouterID == profile.id
            ? (appModel.controllerSession.lastSuccessAt ?? profile.lastConnectedAt)
            : profile.lastConnectedAt

        return Group {
            if let date {
                Text(date, format: .dateTime.year().month().day().hour().minute().second())
            } else {
                Text(ControllerManagementCopy.never(language: appLanguage))
            }
        }
        .font(.callout.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(nil)
    }

    private func actionStrip(for profile: RouterProfile) -> some View {
        let isActive = appModel.selectedRouterID == profile.id
        let canReorder = ControllerManagementPresentation.isReorderingEnabled(searchText: searchText)
        let sourceIndex = appModel.routers.firstIndex(where: { $0.id == profile.id })

        return HStack(spacing: 0) {
            Button {
                appModel.selectRouter(profile)
            } label: {
                Image(systemName: isActive ? "checkmark" : "play.fill")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .disabled(isActive)
            .help(ControllerManagementCopy.use(language: appLanguage))
            .accessibilityLabel(ControllerManagementCopy.use(language: appLanguage))

            Button {
                Task { _ = await appModel.testConnection(draft: appModel.draft(for: profile)) }
            } label: {
                Image(systemName: MicaSymbols.Command.test)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .help(ControllerManagementCopy.test(language: appLanguage))
            .accessibilityLabel(ControllerManagementCopy.test(language: appLanguage))

            Button {
                onEditController(profile)
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .help(ControllerManagementCopy.edit(language: appLanguage))
            .accessibilityLabel(ControllerManagementCopy.edit(language: appLanguage))

            Button {
                pendingDelete = profile
            } label: {
                Image(systemName: "trash")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(MicaStyle.signalRed)
            .help(ControllerManagementCopy.delete(language: appLanguage))
            .accessibilityLabel(ControllerManagementCopy.delete(language: appLanguage))

            Menu {
                Button(ControllerManagementCopy.moveUp(language: appLanguage), systemImage: "arrow.up") {
                    guard let sourceIndex else { return }
                    Task { try? await appModel.moveRouter(profile.id, to: sourceIndex - 1) }
                }
                .disabled(!canReorder || sourceIndex == nil || sourceIndex == 0)

                Button(ControllerManagementCopy.moveDown(language: appLanguage), systemImage: "arrow.down") {
                    guard let sourceIndex else { return }
                    Task { try? await appModel.moveRouter(profile.id, to: sourceIndex + 1) }
                }
                .disabled(!canReorder || sourceIndex == nil || sourceIndex == appModel.routers.indices.last)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .frame(width: 44, height: 44)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .disabled(!canReorder)
            .help(ControllerManagementCopy.moveUp(language: appLanguage) + " / " + ControllerManagementCopy.moveDown(language: appLanguage))
            .accessibilityLabel(ControllerManagementCopy.actions(language: appLanguage))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func reorderableCell<Content: View>(
        for profile: RouterProfile,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if ControllerManagementPresentation.isReorderingEnabled(searchText: searchText) {
            content()
                .draggable(profile.id.uuidString)
                .dropDestination(for: String.self) { items, _ in
                    guard let rawID = items.first,
                          let sourceID = UUID(uuidString: rawID),
                          sourceID != profile.id,
                          let targetIndex = appModel.routers.firstIndex(where: { $0.id == profile.id }) else {
                        return false
                    }
                    Task { try? await appModel.moveRouter(sourceID, to: targetIndex) }
                    return true
                }
                .accessibilityAction(named: Text(ControllerManagementCopy.moveUp(language: appLanguage))) {
                    guard let index = appModel.routers.firstIndex(where: { $0.id == profile.id }), index > 0 else { return }
                    Task { try? await appModel.moveRouter(profile.id, to: index - 1) }
                }
                .accessibilityAction(named: Text(ControllerManagementCopy.moveDown(language: appLanguage))) {
                    guard let index = appModel.routers.firstIndex(where: { $0.id == profile.id }), index < appModel.routers.count - 1 else { return }
                    Task { try? await appModel.moveRouter(profile.id, to: index + 1) }
                }
        } else {
            content()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(ControllerManagementCopy.title(language: appLanguage), systemImage: "server.rack")
        } description: {
            Text(ControllerManagementCopy.noControllersDescription(language: appLanguage))
        } actions: {
            Button(action: onAddController) {
                Label(ControllerManagementCopy.add(language: appLanguage), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(MicaStyle.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredEmptyState: some View {
        ContentUnavailableView(
            ControllerManagementCopy.noMatchTitle(language: appLanguage),
            systemImage: "magnifyingglass",
            description: Text(ControllerManagementCopy.noMatchDescription(language: appLanguage))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func deleteConfirmation(for profile: RouterProfile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(MicaStyle.signalRed)
            Text(deleteConfirmationText(for: profile))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button(MicaStrings.localizedKey("editor.cancel", language: appLanguage)) {
                pendingDelete = nil
            }
            Button(ControllerManagementCopy.delete(language: appLanguage), role: .destructive) {
                pendingDelete = nil
                appModel.deleteRouter(profile)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MicaStyle.contentFill)
        .overlay(alignment: .top) { Divider() }
    }

    private func deleteConfirmationText(for profile: RouterProfile) -> String {
        guard appModel.selectedRouterID == profile.id,
              let index = appModel.routers.firstIndex(where: { $0.id == profile.id }) else {
            return MicaStrings.localized(
                "controllers.delete_confirm \(profile.displayName)",
                language: appLanguage
            )
        }

        var remaining = appModel.routers
        remaining.remove(at: index)
        let replacement = remaining.indices.contains(index) ? remaining[index] : remaining.last
        if let replacement {
            return MicaStrings.localized(
                "controllers.delete_active_confirm \(profile.displayName) \(replacement.displayName)",
                language: appLanguage
            )
        }
        return MicaStrings.localized(
            "controllers.delete_only_confirm \(profile.displayName)",
            language: appLanguage
        )
    }
}
