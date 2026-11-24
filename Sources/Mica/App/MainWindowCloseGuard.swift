import AppKit
import SwiftUI

@MainActor
private final class WeakCloseGuardBox {
    weak var value: MainWindowCloseGuard?
    init(_ value: MainWindowCloseGuard) {
        self.value = value
    }
}

@MainActor
final class MainWindowCloseGuard: NSObject, NSWindowDelegate {
    private static var activeGuards: [ObjectIdentifier: WeakCloseGuardBox] = [:]

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

    override init() {
        super.init()
        Self.activeGuards[ObjectIdentifier(self)] = WeakCloseGuardBox(self)
    }

    static func confirmApplicationTermination(for application: NSApplication) -> NSApplication.TerminateReply {
        activeGuards = activeGuards.filter { $0.value.value != nil }
        let guards = activeGuards.values.compactMap(\.value)

        if guards.contains(where: \.isSaving) {
            NSSound.beep()
            return .terminateCancel
        }

        guard let dirtyGuard = guards.first(where: { $0.isDirty && $0.window != nil }),
              let window = dirtyGuard.window else {
            return .terminateNow
        }

        if dirtyGuard.isConfirmingDiscard {
            window.makeKeyAndOrderFront(nil)
            return .terminateCancel
        }

        window.makeKeyAndOrderFront(nil)
        dirtyGuard.presentDiscardAlert(for: window) { shouldDiscard in
            if shouldDiscard {
                dirtyGuard.isDirty = false
                window.isDocumentEdited = false
            }
            application.reply(toApplicationShouldTerminate: shouldDiscard)
        }
        return .terminateLater
    }

    func attach(to candidate: NSWindow) {
        guard candidate !== window else {
            candidate.isDocumentEdited = isDirty
            return
        }

        detach()
        window = candidate
        originalDelegate = candidate.delegate
        candidate.delegate = self
        candidate.isDocumentEdited = isDirty
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

        presentDiscardAlert(for: sender) { [weak self, weak sender] shouldDiscard in
            guard shouldDiscard, let self, let sender else { return }
            self.isDirty = false
            sender.isDocumentEdited = false
            DispatchQueue.main.async { [weak self, weak sender] in
                guard let self, let sender else { return }
                self.allowsNextClose = true
                sender.performClose(nil)
                self.allowsNextClose = false
            }
        }
        return false
    }

    private func presentDiscardAlert(
        for window: NSWindow,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        isConfirmingDiscard = true
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = MicaStrings.localized("editor.window_close_unsaved_title", language: language)
        alert.informativeText = MicaStrings.localized("editor.window_close_unsaved_message", language: language)
        alert.addButton(
            withTitle: MicaStrings.localized("editor.continue_editing", language: language)
        )
        let discardButton = alert.addButton(
            withTitle: MicaStrings.localized("editor.discard_changes", language: language)
        )
        discardButton.hasDestructiveAction = true

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else {
                completion(false)
                return
            }
            self.isConfirmingDiscard = false
            completion(response == .alertSecondButtonReturn)
        }
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

@MainActor
struct MainWindowCloseGuardAttachment: NSViewRepresentable {
    let closeGuard: MainWindowCloseGuard

    func makeNSView(context: Context) -> MainWindowCloseGuardHostView {
        let view = MainWindowCloseGuardHostView()
        view.onWindowChange = { [weak closeGuard] window in
            guard let closeGuard else { return }
            if let window {
                closeGuard.attach(to: window)
            } else {
                closeGuard.detach()
            }
        }
        return view
    }

    func updateNSView(
        _ nsView: MainWindowCloseGuardHostView,
        context: Context
    ) {
        guard let window = nsView.window else { return }
        closeGuard.attach(to: window)
    }
}

@MainActor
final class MainWindowCloseGuardHostView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
