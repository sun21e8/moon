import SwiftUI

@main
struct MoonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private var session: EditorSession { appDelegate.session }

    /// Whether the keyboard is in a text field, where ⌘Z and ⌘⌫ should act on the text being typed.
    private var isTypingInField: Bool { NSApp.keyWindow?.firstResponder is NSTextView }

    var body: some Scene {
        Window("Moon", id: "editor") {
            ContentView(session: session)
        }
        .defaultSize(width: 1180, height: 780)
        // A PDF opened from the Finder goes to the app delegate and into this window, not into a new one.
        .handlesExternalEvents(matching: [])
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Apri…") { session.presentOpenPanel() }
                    .keyboardShortcut("o")
                Button("Unisci più PDF…") { session.presentCombinePanel() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Salva") { _ = session.save() }
                    .keyboardShortcut("s").disabled(session.document == nil)
                Button("Salva con nome…") { _ = session.saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift]).disabled(session.document == nil)
                Divider()
                // With a document open ⌘W closes it; with none it closes the window.
                Button(session.document == nil ? "Chiudi finestra" : "Chiudi documento") {
                    if session.document == nil { NSApp.keyWindow?.performClose(nil) } else { session.close() }
                }
                .keyboardShortcut("w")
            }
            CommandGroup(replacing: .undoRedo) {
                Button(session.undoTitle) {
                    if isTypingInField { _ = NSApp.sendAction(NSSelectorFromString("undo:"), to: nil, from: nil) } else { session.undo() }
                }
                .keyboardShortcut("z")
                Button(session.redoTitle) {
                    if isTypingInField { _ = NSApp.sendAction(NSSelectorFromString("redo:"), to: nil, from: nil) } else { session.redo() }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Adatta alla finestra") { session.zoomToFit() }
                    .keyboardShortcut("0").disabled(session.document == nil)
                Button("Dimensioni reali") { session.zoomToActualSize() }
                    .keyboardShortcut("1").disabled(session.document == nil)
                Button("Ingrandisci") { session.zoomIn() }
                    .keyboardShortcut("=").disabled(session.document == nil)
                Button("Riduci") { session.zoomOut() }
                    .keyboardShortcut("-").disabled(session.document == nil)
                Divider()
                Button("Pagina precedente") { session.goToPage(session.currentPageIndex - 1) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option]).disabled(!session.canGoBack)
                Button("Pagina successiva") { session.goToPage(session.currentPageIndex + 1) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option]).disabled(!session.canGoForward)
                Divider()
            }
            CommandMenu("Pagine") {
                Button("Aggiungi pagine da PDF…") { session.presentAddPagesPanel() }
                    .disabled(session.document == nil)
                Button("Estrai pagine selezionate…") { session.extractSelectedPages() }
                    .disabled(session.document == nil)
                Divider()
                Button("Ruota a sinistra") { session.rotateSelectedPages(clockwise: false) }
                    .keyboardShortcut("l").disabled(session.document == nil)
                Button("Ruota a destra") { session.rotateSelectedPages(clockwise: true) }
                    .keyboardShortcut("r").disabled(session.document == nil)
                Button("Sposta prima") { session.moveSelectedPages(by: -1) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option]).disabled(session.document == nil)
                Button("Sposta dopo") { session.moveSelectedPages(by: 1) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option]).disabled(session.document == nil)
                Divider()
                // In a text field ⌘⌫ keeps its usual meaning: delete back to the start of the line.
                Button("Elimina") {
                    if isTypingInField {
                        _ = NSApp.sendAction(#selector(NSResponder.deleteToBeginningOfLine(_:)), to: nil, from: nil)
                    } else {
                        session.deleteSelection()
                    }
                }
                .keyboardShortcut(.delete, modifiers: .command).disabled(session.document == nil)
            }
        }
    }
}

/// Owns the editor session for the life of the app, receives files opened from outside it, and asks about
/// unsaved changes before the app quits.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Lazy, so the session is built on the main actor at first use rather than in a stored-property initializer,
    // which the compiler treats as nonisolated.
    private(set) lazy var session = EditorSession()

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) ?? urls.first else { return }
        session.open(url)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Once the window is gone there's nothing to go back to, so Cancel is only offered while it's open.
        let windowIsOpen = sender.windows.contains { $0.isVisible && $0.canBecomeMain }
        return session.confirmDiscardIfNeeded(allowCancel: windowIsOpen) ? .terminateNow : .terminateCancel
    }
}
