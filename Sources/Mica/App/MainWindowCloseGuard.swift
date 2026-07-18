import AppKit

@MainActor
final class MainWindowCloseGuard: NSObject, NSWindowDelegate {
    private weak var window: NSWindow?
    // NSObject message forwarding is nonisolated even though AppKit invokes
    // NSWindowDelegate on the main thread. Keep only this forwarding reference
    // outside actor checking; all mutation still happens in MainActor methods.
    nonisolated(unsafe) private var originalDelegate: (any NSWindowDelegate)?
    private var isDirty = false
    private var isSaving = false
    private var isConfirmingDiscard = false
    private var allowsNextClose = false
    private var language: AppLanguage = .system

    func attachToCurrentMainWindow() {
        guard let candidate = NSApplication.shared.mainWindow ?? NSApplication.shared.keyWindow else {
            return
        }
        guard candidate !== window else { return }

        detach()
        window = candidate
        originalDelegate = candidate.delegate
        candidate.delegate = self
    }

    func update(isDirty: Bool, isSaving: Bool, language: AppLanguage) {
        self.isDirty = isDirty
        self.isSaving = isSaving
        self.language = language
        window?.isDocumentEdited = isDirty
    }

    func detach() {
        if let window, window.delegate === self {
            window.delegate = originalDelegate
            window.isDocumentEdited = false
        }
        window = nil
        originalDelegate = nil
        isConfirmingDiscard = false
        allowsNextClose = false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowsNextClose {
            allowsNextClose = false
            return originalDelegate?.windowShouldClose?(sender) ?? true
        }

        guard !isSaving else {
            NSSound.beep()
            return false
        }
        guard isDirty else {
            return originalDelegate?.windowShouldClose?(sender) ?? true
        }
        guard !isConfirmingDiscard else { return false }

        isConfirmingDiscard = true
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = MicaStrings.localized("editor.window_close_unsaved_title", language: language)
        alert.informativeText = MicaStrings.localized("editor.window_close_unsaved_message", language: language)
        let discardButton = alert.addButton(
            withTitle: MicaStrings.localized("editor.discard_changes", language: language)
        )
        discardButton.hasDestructiveAction = true
        alert.addButton(
            withTitle: MicaStrings.localized("editor.continue_editing", language: language)
        )

        alert.beginSheetModal(for: sender) { [weak self, weak sender] response in
            guard let self else { return }
            self.isConfirmingDiscard = false
            guard response == .alertFirstButtonReturn, let sender else { return }
            self.isDirty = false
            sender.isDocumentEdited = false
            self.allowsNextClose = true
            sender.performClose(nil)
        }
        return false
    }

    override nonisolated func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || originalDelegate?.responds(to: selector) == true
    }

    override nonisolated func forwardingTarget(for selector: Selector!) -> Any? {
        if originalDelegate?.responds(to: selector) == true {
            return originalDelegate
        }
        return super.forwardingTarget(for: selector)
    }
}
