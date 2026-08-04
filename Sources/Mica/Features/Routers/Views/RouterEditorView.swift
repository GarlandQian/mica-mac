import MicaCore
import SwiftUI

struct RouterEditorView: View {
    @Environment(\.micaAppLanguage) var appLanguage
    @Environment(AppModel.self) var appModel

    @State var draft: RouterDraft
    @State private var initialDraft: RouterDraft
    @State var testState: TestState = .idle
    @State var showsValidation = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showsDiscardConfirmation = false

    let title: String
    let discardRequestID: Int
    let onClose: () -> Void
    let onDiscardConfirmed: () -> Void
    let onEditingStateChange: (Bool, Bool) -> Void

    init(
        draft: RouterDraft,
        title: String,
        discardRequestID: Int = 0,
        onClose: @escaping () -> Void,
        onDiscardConfirmed: @escaping () -> Void,
        onEditingStateChange: @escaping (Bool, Bool) -> Void = { _, _ in }
    ) {
        _draft = State(initialValue: draft)
        _initialDraft = State(initialValue: draft)
        self.title = title
        self.discardRequestID = discardRequestID
        self.onClose = onClose
        self.onDiscardConfirmed = onDiscardConfirmed
        self.onEditingStateChange = onEditingStateChange
    }

    var body: some View {
        WorkbenchPageScaffold {
            editorCommandBar
        } content: {
            WorkbenchManagementFormCanvas {
                controllerFormContent

                if testState.shouldShow {
                    diagnosisSection
                }
            }
        }
        .navigationTitle(MicaStrings.localizedKey(title, language: appLanguage))
        .toolbarTitleDisplayMode(.inline)
        .onAppear { reportEditingState() }
        .onChange(of: draft) { _, _ in reportEditingState() }
        .onChange(of: isSaving) { _, _ in reportEditingState() }
        .onChange(of: appLanguage.rawValue) { _, _ in reportEditingState() }
        .onChange(of: draft.controllerKind) { _, _ in testState = .idle }
        .onChange(of: discardRequestID) { _, _ in
            guard !isSaving else { return }
            if isDirty {
                showsDiscardConfirmation = true
            } else {
                onDiscardConfirmed()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showsDiscardConfirmation || saveError != nil {
                VStack(spacing: 0) {
                    if showsDiscardConfirmation {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(MicaStyle.signalAmber)
                            Text(discardPrompt)
                                .micaFont(.callout)
                            Spacer(minLength: 12)
                            Button(continueEditingTitle) {
                                showsDiscardConfirmation = false
                            }
                            Button(discardTitle, role: .destructive) {
                                showsDiscardConfirmation = false
                                onDiscardConfirmed()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }

                    if let saveError {
                        if showsDiscardConfirmation { Divider() }
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(MicaStyle.signalRed)
                            Text(saveError)
                                .micaFont(.callout)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
                .background(MicaStyle.contentFill)
                .overlay(alignment: .top) { Divider() }
            }
        }
    }

    private var editorCommandBar: some View {
        WorkbenchCommandBar {
            WorkbenchManagementHeader(
                systemImage: draft.controllerKind.editorSymbol,
                titleKey: title,
                detail: editorHeaderDetail
            )
        } commands: {
            HStack(spacing: MicaSpacing.tight) {
                Button(action: requestClose) {
                    Label(
                        MicaStrings.localizedKey("editor.cancel", language: appLanguage),
                        systemImage: "xmark"
                    )
                    .labelStyle(.titleAndIcon)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)

                Button(action: testConnection) {
                    HStack(spacing: MicaSpacing.row) {
                        if testState == .testing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: MicaSymbols.Command.test)
                        }
                        Text(
                            testState == .testing
                                ? MicaStrings.localized("editor.testing", language: appLanguage)
                                : MicaStrings.localized("editor.test", language: appLanguage)
                        )
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(testState == .testing || isSaving)
                .help(MicaStrings.localizedKey("editor.help_test", language: appLanguage))

                Button(action: saveController) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(
                            MicaStrings.localizedKey("editor.save", language: appLanguage),
                            systemImage: "checkmark"
                        )
                        .labelStyle(.titleAndIcon)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .disabled(testState == .testing || isSaving)
                .help(MicaStrings.localizedKey("editor.help_save", language: appLanguage))
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
    }

    private var editorHeaderDetail: String {
        let unconfigured = MicaStrings.localizedKey(
            "editor.target_not_configured",
            language: appLanguage
        )
        return localizedVisibleControllerTargetLabel == unconfigured
            ? draft.controllerKind.micaLabel(language: appLanguage)
            : localizedVisibleControllerTargetLabel
    }

    var validationError: String? {
        draft.validationError(language: appLanguage)
    }

    private var isDirty: Bool {
        draft != initialDraft
    }

    private func reportEditingState() {
        onEditingStateChange(isDirty, isSaving)
    }

    private func requestClose() {
        guard !isSaving else { return }
        if isDirty {
            showsDiscardConfirmation = true
        } else {
            onClose()
        }
    }

    private func saveController() {
        showsValidation = true
        guard validationError == nil else { return }
        guard !isSaving else { return }

        isSaving = true
        saveError = nil
        Task {
            do {
                try await appModel.upsertRouter(from: draft)
                initialDraft = draft
                onClose()
            } catch {
                saveError = MicaStrings.localized("operation.profile_save_failed", language: appLanguage)
                isSaving = false
            }
        }
    }

    private var discardPrompt: String {
        MicaStrings.localizedKey("editor.unsaved_changes_prompt", language: appLanguage)
    }

    private var continueEditingTitle: String {
        MicaStrings.localizedKey("editor.continue_editing", language: appLanguage)
    }

    private var discardTitle: String {
        MicaStrings.localizedKey("editor.discard_changes", language: appLanguage)
    }
}

enum TestState: Equatable {
    case idle
    case testing
    case report(ConnectionTestReport)

    var shouldShow: Bool {
        switch self {
        case .idle: false
        case .testing, .report: true
        }
    }

    var iconName: String {
        switch self {
        case .idle, .testing: "hourglass"
        case .report(let report): report.summary == .ready ? MicaSymbols.Command.ready : "exclamationmark.triangle"
        }
    }

    var foregroundStyle: Color {
        switch self {
        case .idle, .testing: MicaStyle.signalCyan
        case .report(let report): report.summary == .ready ? MicaStyle.signalMint : MicaStyle.signalRed
        }
    }
}

extension ConnectionCheckState {
    var iconName: String {
        switch self {
        case .ready: MicaSymbols.Command.ready
        case .warning: "exclamationmark.circle"
        case .failed: "xmark.octagon"
        }
    }

    var tint: Color {
        switch self {
        case .ready: MicaStyle.signalMint
        case .warning: MicaStyle.signalAmber
        case .failed: MicaStyle.signalRed
        }
    }
}

extension ControllerKind {
    var editorSymbol: String {
        switch self {
        case .surgeCompatible: MicaSymbols.Controller.surge
        case .singBoxCompatible: MicaSymbols.Controller.singBox
        case .cmfaCompatible, .stashCompatible, .stashCmfaCompatible: MicaSymbols.Controller.stashCmfa
        case .mihomoCompatible, .nikkiMihomoCompatible, .openClashMihomoCompatible: MicaSymbols.Controller.mihomo
        case .autoDetect: MicaSymbols.Controller.autoDetect
        case .unknown, .unsupported: MicaSymbols.Controller.unknown
        }
    }
}
