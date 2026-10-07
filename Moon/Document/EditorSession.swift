import AppKit
import Observation
import PDFKit
import UniformTypeIdentifiers

/// A message for the window to show in an alert.
struct SessionAlert {
    let title: String
    let message: String
}

/// The open document and everything the window shows about it. One session lives for the life of the app; the
/// views read it and call its methods, and it drives the PDF view.
@MainActor
@Observable
final class EditorSession {
    /// One PDF view for the life of the window: SwiftUI hosts it, the session drives it.
    let pdfView = CanvasPDFView()

    private(set) var document: PDFDocument?
    private(set) var fileURL: URL?
    private(set) var pageCount = 0
    private(set) var currentPageIndex = 0
    private(set) var zoom: Double = 1
    private(set) var layout: PageLayout = .continuous
    /// Bumped whenever a different document is shown, so views drop what they cached for the old one.
    private(set) var generation = 0
    /// Bumped on every edit that changes how a page looks, so thumbnails redraw.
    private(set) var revision = 0
    private(set) var isDirty = false
    /// The pages selected in the Pages panel, by index.
    private(set) var selectedPages: Set<Int> = []
    /// The text box being edited, if any, and its properties as the tool header shows them.
    private(set) var selectedTextBox: PDFAnnotation?
    private(set) var textDraft = ""
    private(set) var textSize: Double = 14
    private(set) var textColor: NSColor = .black
    /// Bumped to ask the tool header to put the keyboard in the text field.
    private(set) var textFocusRequest = 0
    var tool: Tool = .select
    var alert: SessionAlert?

    private var undoStack: [UndoStep] = []
    private var redoStack: [UndoStep] = []

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var selectionAnchor: Int?
    @ObservationIgnored private var selectedTextBoxColor: NSColor = .clear
    @ObservationIgnored private var textEditedSinceSelection = false
    @ObservationIgnored private var mouseCaptured = false
    @ObservationIgnored private var drag: DragState?
    /// Documents whose pages were added to this one; kept alive for as long as their pages are in use.
    @ObservationIgnored private var sources: [PDFDocument] = []
    private let thumbnails = NSCache<NSNumber, NSImage>()

    init() {
        pdfView.session = self
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.pageShadowsEnabled = true
        pdfView.autoScales = true
        pdfView.backgroundColor = NSColor(white: 0.09, alpha: 1)

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .PDFViewPageChanged, object: pdfView, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.syncPage() }
        })
        observers.append(center.addObserver(forName: .PDFViewScaleChanged, object: pdfView, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.syncZoom() }
        })
    }

    // MARK: Opening and closing

    private var displayName: String { fileURL?.deletingPathExtension().lastPathComponent ?? "Senza titolo" }

    var title: String {
        guard document != nil else { return "Moon" }
        return isDirty ? displayName + " — modificato" : displayName
    }

    func presentOpenPanel() {
        guard let url = pickPDFs(multiple: false, message: "Scegli un PDF da aprire").first else { return }
        open(url)
    }

    func open(_ url: URL) {
        guard confirmDiscardIfNeeded() else { return }
        guard let loaded = PDFDocument(url: url) else {
            alert = SessionAlert(title: "Impossibile aprire il file",
                                 message: "Non riesco ad aprire “\(url.lastPathComponent)”. Potrebbe non essere un PDF, oppure essere danneggiato.")
            return
        }
        show(loaded, url: url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    /// Builds a new, unsaved document out of the pages of several files.
    func presentCombinePanel() {
        let urls = pickPDFs(multiple: true, message: "Scegli i PDF da unire in un nuovo documento")
        guard !urls.isEmpty, confirmDiscardIfNeeded() else { return }
        let merged = PDFDocument()
        let imported = pages(from: urls)
        for (index, page) in imported.pages.enumerated() { merged.insert(page, at: index) }
        guard merged.pageCount > 0 else {
            alert = SessionAlert(title: "Niente da unire", message: "Non sono riuscita a leggere nessuno dei file scelti.")
            return
        }
        show(merged, url: nil)
        sources = imported.sources
        isDirty = true
        reportUnreadable(imported.failed)
    }

    func close() {
        guard confirmDiscardIfNeeded() else { return }
        resetState()
        pdfView.document = nil
        document = nil
        fileURL = nil
        pageCount = 0
        generation += 1
    }

    /// Asks what to do with unsaved changes. Returns whether it's fine to go ahead and drop the document.
    func confirmDiscardIfNeeded(allowCancel: Bool = true) -> Bool {
        guard document != nil, isDirty else { return true }
        let question = NSAlert()
        question.messageText = "Vuoi salvare le modifiche a “\(displayName)”?"
        question.informativeText = "Se non le salvi, le modifiche andranno perse."
        question.addButton(withTitle: "Salva")
        question.addButton(withTitle: "Non salvare")
        if allowCancel { question.addButton(withTitle: "Annulla") }
        switch question.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    // MARK: Saving

    @discardableResult
    func save() -> Bool {
        guard document != nil else { return false }
        guard let url = fileURL else { return saveAs() }
        return write(to: url)
    }

    @discardableResult
    func saveAs() -> Bool {
        guard document != nil, let url = pickSaveURL(suggestedName: displayName + ".pdf") else { return false }
        return write(to: url)
    }

    /// Saves the selected pages (or the current one) as a separate PDF, leaving this document as it is.
    func extractSelectedPages() {
        let targets = targetPages
        guard let document, !targets.isEmpty else { return }
        guard let url = pickSaveURL(suggestedName: displayName + " - estratto.pdf") else { return }
        deselectTextBox()
        let extracted = PDFDocument()
        for (position, index) in targets.enumerated() {
            if let page = document.page(at: index), let copy = page.copy() as? PDFPage {
                extracted.insert(copy, at: position)
            }
        }
        writeSafely(extracted, to: url)
    }

    private func write(to url: URL) -> Bool {
        guard let document else { return false }
        deselectTextBox()
        guard writeSafely(document, to: url) else { return false }
        fileURL = url
        isDirty = false
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        return true
    }

    /// Writes to a temporary file beside the destination, checks that it reads back with every page, and only
    /// then puts it in place — so a failed save never leaves a damaged file where a good one was.
    @discardableResult
    private func writeSafely(_ output: PDFDocument, to url: URL) -> Bool {
        let files = FileManager.default
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".moon-\(UUID().uuidString).pdf")
        func fail(_ message: String) -> Bool {
            try? files.removeItem(at: temporary)
            alert = SessionAlert(title: "Salvataggio non riuscito", message: message)
            return false
        }
        guard output.write(to: temporary) else {
            return fail("Non riesco a scrivere in quella cartella. Prova a salvare altrove.")
        }
        guard let check = PDFDocument(url: temporary), check.pageCount == output.pageCount else {
            return fail("Il file scritto non risulta leggibile, quindi l'ho scartato. L'originale non è stato toccato.")
        }
        do {
            if files.fileExists(atPath: url.path) {
                _ = try files.replaceItemAt(url, withItemAt: temporary)
            } else {
                try files.moveItem(at: temporary, to: url)
            }
        } catch {
            return fail(error.localizedDescription)
        }
        return true
    }

    // MARK: Undo

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoTitle: String { undoStack.last.map { "Annulla " + $0.name } ?? "Annulla" }
    var redoTitle: String { redoStack.last.map { "Ripristina " + $0.name } ?? "Ripristina" }

    func undo() {
        guard let step = undoStack.popLast() else { return }
        redoStack.append(UndoStep(name: step.name, snapshot: takeSnapshot()))
        restore(step.snapshot)
        isDirty = true
    }

    func redo() {
        guard let step = redoStack.popLast() else { return }
        undoStack.append(UndoStep(name: step.name, snapshot: takeSnapshot()))
        restore(step.snapshot)
        isDirty = true
    }

    /// Call before changing the document: records how it is now, so the change can be undone.
    private func beginEdit(_ name: String) {
        undoStack.append(UndoStep(name: name, snapshot: takeSnapshot()))
        if undoStack.count > 60 { undoStack.removeFirst() }
        redoStack.removeAll()
        isDirty = true
    }

    private func takeSnapshot() -> Snapshot {
        var pages: [PDFPage] = []
        var rotations: [Int] = []
        var boxes: [TextBoxState] = []
        if let document {
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                pages.append(page)
                rotations.append(page.rotation)
                for annotation in page.annotations where isTextBox(annotation) {
                    boxes.append(TextBoxState(annotation: annotation, page: page, bounds: annotation.bounds,
                                              contents: annotation.contents ?? "",
                                              font: annotation.font ?? NSFont.systemFont(ofSize: 14),
                                              fontColor: annotation.fontColor ?? .black))
                }
            }
        }
        return Snapshot(pages: pages, rotations: rotations, textBoxes: boxes, selectedPages: selectedPages)
    }

    private func restore(_ snapshot: Snapshot) {
        guard document != nil else { return }
        deselectTextBox()
        let target = snapshot.selectedPages.min() ?? currentPageIndex
        withDetachedView(goTo: target) { document in
            while document.pageCount > 0 { document.removePage(at: document.pageCount - 1) }
            for (index, page) in snapshot.pages.enumerated() {
                document.insert(page, at: index)
                page.rotation = snapshot.rotations[index]
                for annotation in page.annotations where self.isTextBox(annotation) { page.removeAnnotation(annotation) }
            }
            for state in snapshot.textBoxes {
                state.annotation.bounds = state.bounds
                state.annotation.contents = state.contents
                state.annotation.font = state.font
                state.annotation.fontColor = state.fontColor
                state.page.addAnnotation(state.annotation)
            }
        }
        selectedPages = snapshot.selectedPages.filter { $0 < pageCount }
    }

    // MARK: Pages

    var canGoBack: Bool { document != nil && currentPageIndex > 0 }
    var canGoForward: Bool { document != nil && currentPageIndex < pageCount - 1 }

    func goToPage(_ index: Int) {
        guard let document, index >= 0, index < document.pageCount, let page = document.page(at: index) else { return }
        pdfView.go(to: page)
    }

    /// A click on a thumbnail: plain selects that page, ⌘ adds or removes it, ⇧ extends from the last one clicked.
    func selectPage(_ index: Int, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selectedPages.contains(index) { selectedPages.remove(index) } else { selectedPages.insert(index) }
            selectionAnchor = index
        } else if modifiers.contains(.shift), let anchor = selectionAnchor {
            selectedPages = Set(min(anchor, index)...max(anchor, index))
        } else {
            selectedPages = [index]
            selectionAnchor = index
            goToPage(index)
        }
    }

    func rotateSelectedPages(clockwise: Bool) {
        let targets = targetPages
        guard document != nil, !targets.isEmpty else { return }
        deselectTextBox()
        beginEdit(clockwise ? "Ruota a destra" : "Ruota a sinistra")
        withDetachedView(goTo: targets[0]) { document in
            for index in targets {
                guard let page = document.page(at: index) else { continue }
                page.rotation = (page.rotation + (clockwise ? 90 : 270)) % 360
            }
        }
    }

    func deleteSelectedPages() {
        let targets = targetPages
        guard document != nil, !targets.isEmpty else { return }
        guard targets.count < pageCount else {
            alert = SessionAlert(title: "Non posso eliminarle tutte",
                                 message: "Un PDF deve avere almeno una pagina. Lasciane selezionata una in meno.")
            return
        }
        deselectTextBox()
        beginEdit(targets.count == 1 ? "Elimina pagina" : "Elimina pagine")
        let next = min(targets[0], pageCount - targets.count - 1)
        withDetachedView(goTo: next) { document in
            for index in targets.reversed() { document.removePage(at: index) }
        }
        selectedPages = [max(0, next)]
        selectionAnchor = max(0, next)
    }

    /// Moves the selected pages one place earlier (`-1`) or later (`1`).
    func moveSelectedPages(by offset: Int) {
        let targets = targetPages
        guard document != nil, let first = targets.first, let last = targets.last else { return }
        guard offset < 0 ? first > 0 : last < pageCount - 1 else { return }
        deselectTextBox()
        beginEdit(targets.count == 1 ? "Sposta pagina" : "Sposta pagine")
        let ordered = offset < 0 ? targets : Array(targets.reversed())
        withDetachedView(goTo: first + offset) { document in
            for index in ordered { document.exchangePage(at: index, withPageAt: index + offset) }
        }
        selectedPages = Set(targets.map { $0 + offset })
        selectionAnchor = first + offset
    }

    func presentAddPagesPanel() {
        guard document != nil else { return }
        let urls = pickPDFs(multiple: true, message: "Scegli i PDF le cui pagine vuoi aggiungere dopo quella selezionata")
        guard !urls.isEmpty else { return }
        addPages(from: urls)
    }

    /// Inserts every page of the given files after the last selected page.
    func addPages(from urls: [URL]) {
        guard document != nil else { return }
        let imported = pages(from: urls)
        guard !imported.pages.isEmpty else {
            alert = SessionAlert(title: "Nessuna pagina aggiunta", message: "Non sono riuscita a leggere nessuno dei file scelti.")
            return
        }
        deselectTextBox()
        let insertion = min(pageCount, (targetPages.last ?? pageCount - 1) + 1)
        beginEdit(imported.pages.count == 1 ? "Aggiungi pagina" : "Aggiungi pagine")
        sources.append(contentsOf: imported.sources)
        withDetachedView(goTo: insertion) { document in
            for (offset, page) in imported.pages.enumerated() { document.insert(page, at: insertion + offset) }
        }
        selectedPages = Set(insertion..<(insertion + imported.pages.count))
        selectionAnchor = insertion
        reportUnreadable(imported.failed)
    }

    func setLayout(_ newLayout: PageLayout) {
        layout = newLayout
        switch newLayout {
        case .continuous: pdfView.displayMode = .singlePageContinuous
        case .single: pdfView.displayMode = .singlePage
        case .twoUp: pdfView.displayMode = .twoUpContinuous
        }
    }

    /// Height over width of a page as displayed, for laying out its thumbnail before the image exists.
    func pageAspect(at index: Int) -> CGFloat {
        guard let page = document?.page(at: index) else { return 1.414 }
        let size = displayedSize(of: page)
        return size.width > 0 ? size.height / size.width : 1.414
    }

    func thumbnail(for index: Int, width: CGFloat) -> NSImage? {
        let key = NSNumber(value: index)
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let page = document?.page(at: index) else { return nil }
        // Twice the point size, so thumbnails stay sharp on a Retina display.
        let pixelWidth = max(1, width * 2)
        let size = NSSize(width: pixelWidth, height: pixelWidth * pageAspect(at: index))
        let image = page.thumbnail(of: size, for: .cropBox)
        thumbnails.setObject(image, forKey: key)
        return image
    }

    // MARK: Text boxes

    /// Deletes what's selected: the text box being edited if there is one, otherwise the selected pages.
    func deleteSelection() {
        if selectedTextBox != nil { deleteSelectedTextBox() } else { deleteSelectedPages() }
    }

    func setText(_ text: String) {
        guard let box = selectedTextBox else { return }
        noteTextEdit()
        textDraft = text
        box.contents = text
        fitBounds(of: box)
        refresh(box)
    }

    func setTextSize(_ size: Double) {
        guard let box = selectedTextBox else { return }
        noteTextEdit()
        textSize = min(144, max(6, size.rounded()))
        let current = box.font ?? NSFont.systemFont(ofSize: 14)
        box.font = NSFont(descriptor: current.fontDescriptor, size: CGFloat(textSize)) ?? NSFont.systemFont(ofSize: CGFloat(textSize))
        fitBounds(of: box)
        refresh(box)
    }

    func setTextColor(_ color: NSColor) {
        guard let box = selectedTextBox else { return }
        noteTextEdit()
        textColor = color
        box.fontColor = color
        refresh(box)
    }

    func deleteSelectedTextBox() {
        guard let box = selectedTextBox, let page = box.page else { return }
        beginEdit("Elimina testo")
        box.color = selectedTextBoxColor
        selectedTextBox = nil
        page.removeAnnotation(box)
        pdfView.annotationsChanged(on: page)
        invalidateThumbnails()
    }

    /// Ends editing of the selected text box, if any. A box left empty is removed.
    func deselectTextBox() {
        guard let box = selectedTextBox else { return }
        box.color = selectedTextBoxColor
        selectedTextBox = nil
        guard let page = box.page else { return }
        if (box.contents ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { page.removeAnnotation(box) }
        pdfView.annotationsChanged(on: page)
        invalidateThumbnails()
    }

    private func isTextBox(_ annotation: PDFAnnotation) -> Bool {
        let type = annotation.type ?? ""
        return type == "FreeText" || type == "/FreeText"
    }

    private func selectTextBox(_ box: PDFAnnotation) {
        if selectedTextBox === box { return }
        deselectTextBox()
        selectedTextBox = box
        selectedTextBoxColor = box.color
        // A light tint marks the box being edited; it's taken off again before saving.
        box.color = NSColor.systemBlue.withAlphaComponent(0.14)
        textDraft = box.contents ?? ""
        textSize = Double(box.font?.pointSize ?? 14)
        textColor = box.fontColor ?? .black
        textEditedSinceSelection = false
        if let page = box.page { pdfView.annotationsChanged(on: page) }
    }

    private func addTextBox(at point: CGPoint, on page: PDFPage) -> PDFAnnotation {
        deselectTextBox()
        beginEdit("Aggiungi testo")
        let box = PDFAnnotation(bounds: CGRect(x: point.x, y: point.y, width: 10, height: 0), forType: .freeText, withProperties: nil)
        box.contents = "Testo"
        box.font = NSFont.systemFont(ofSize: CGFloat(textSize))
        box.fontColor = textColor
        box.color = .clear
        fitBounds(of: box)
        page.addAnnotation(box)
        selectTextBox(box)
        // Adding the box is the undo step; typing into it straight away doesn't add another.
        textEditedSinceSelection = true
        textFocusRequest += 1
        return box
    }

    /// Sizes a text box to its text, keeping its top-left corner where it is.
    private func fitBounds(of box: PDFAnnotation) {
        let font = box.font ?? NSFont.systemFont(ofSize: 14)
        let text = box.contents ?? ""
        let measured = ((text.isEmpty ? " " : text) as NSString).size(withAttributes: [.font: font])
        let width = ceil(measured.width) + 16
        let height = ceil(measured.height) + 8
        let old = box.bounds
        box.bounds = CGRect(x: old.minX, y: old.maxY - height, width: width, height: height)
    }

    /// The first change to a text box after selecting it becomes one undo step, not one per keystroke.
    private func noteTextEdit() {
        if !textEditedSinceSelection {
            beginEdit("Modifica testo")
            textEditedSinceSelection = true
        }
    }

    private func refresh(_ box: PDFAnnotation) {
        isDirty = true
        if let page = box.page { pdfView.annotationsChanged(on: page) }
    }

    // MARK: Mouse in the canvas

    /// Each returns whether the session handled the event; if not, the PDF view does what it normally does.
    func canvasMouseDown(_ event: NSEvent) -> Bool {
        guard document != nil else { return false }
        let viewPoint: NSPoint = pdfView.convert(event.locationInWindow, from: nil)
        guard let page = pdfView.page(for: viewPoint, nearest: false) else {
            deselectTextBox()
            return false
        }
        let point: NSPoint = pdfView.convert(viewPoint, to: page)
        if let hit = page.annotation(at: point), isTextBox(hit) {
            selectTextBox(hit)
            drag = DragState(box: hit, page: page, start: point,
                             offset: CGPoint(x: point.x - hit.bounds.minX, y: point.y - hit.bounds.minY), isMoving: false)
            mouseCaptured = true
            return true
        }
        if tool == .text {
            let box = addTextBox(at: point, on: page)
            // Keep hold of the new box: dragging before letting go places it.
            drag = DragState(box: box, page: page, start: point,
                             offset: CGPoint(x: 0, y: box.bounds.height), isMoving: true)
            mouseCaptured = true
            return true
        }
        deselectTextBox()
        return false
    }

    func canvasMouseDragged(_ event: NSEvent) -> Bool {
        guard mouseCaptured else { return false }
        guard var state = drag else { return true }
        let viewPoint: NSPoint = pdfView.convert(event.locationInWindow, from: nil)
        let point: NSPoint = pdfView.convert(viewPoint, to: state.page)
        if !state.isMoving {
            // A click that wobbles a little isn't a move.
            guard abs(point.x - state.start.x) > 2 || abs(point.y - state.start.y) > 2 else { return true }
            beginEdit("Sposta testo")
            state.isMoving = true
            drag = state
        }
        var bounds = state.box.bounds
        bounds.origin = CGPoint(x: point.x - state.offset.x, y: point.y - state.offset.y)
        state.box.bounds = bounds
        refresh(state.box)
        return true
    }

    func canvasMouseUp(_ event: NSEvent) -> Bool {
        guard mouseCaptured else { return false }
        mouseCaptured = false
        drag = nil
        return true
    }

    // MARK: Zoom

    func zoomIn() { pdfView.zoomIn(nil) }
    func zoomOut() { pdfView.zoomOut(nil) }
    func zoomToFit() { pdfView.autoScales = true }
    func zoomToActualSize() {
        pdfView.autoScales = false
        pdfView.scaleFactor = 1
    }

    // MARK: Status

    var zoomDescription: String { "\(Int((zoom * 100).rounded()))%" }

    var pageDescription: String { "Pagina \(currentPageIndex + 1) di \(pageCount)" }

    var selectionDescription: String? {
        selectedPages.count > 1 ? "\(selectedPages.count) pagine selezionate" : nil
    }

    /// The current page's size in millimetres, as displayed (rotation applied).
    var pageSizeDescription: String? {
        guard let page = document?.page(at: currentPageIndex) else { return nil }
        let size = displayedSize(of: page)
        let millimetres = 25.4 / 72.0
        return String(format: "%.0f × %.0f mm", Double(size.width) * millimetres, Double(size.height) * millimetres)
    }

    // MARK: Private

    /// The pages a page command applies to: the selection, or the current page when nothing is selected.
    private var targetPages: [Int] {
        let chosen = selectedPages.isEmpty ? [currentPageIndex] : Array(selectedPages)
        return chosen.filter { $0 >= 0 && $0 < pageCount }.sorted()
    }

    private func show(_ loaded: PDFDocument, url: URL?) {
        resetState()
        document = loaded
        fileURL = url
        pageCount = loaded.pageCount
        selectedPages = pageCount > 0 ? [0] : []
        selectionAnchor = 0
        generation += 1
        pdfView.document = loaded
        pdfView.autoScales = true
        pdfView.goToFirstPage(nil)
        syncPage()
        syncZoom()
    }

    private func resetState() {
        thumbnails.removeAllObjects()
        selectedTextBox = nil
        selectedPages = []
        selectionAnchor = nil
        undoStack.removeAll()
        redoStack.removeAll()
        sources.removeAll()
        drag = nil
        mouseCaptured = false
        isDirty = false
        currentPageIndex = 0
    }

    /// Changes the document's pages with the view let go of it, then shows the result at `target`. The PDF view
    /// doesn't follow pages being added, removed or turned underneath it, so it's handed the document afresh.
    private func withDetachedView(goTo target: Int, _ change: (PDFDocument) -> Void) {
        guard let document else { return }
        let autoScales = pdfView.autoScales
        let scale = pdfView.scaleFactor
        pdfView.document = nil
        change(document)
        pdfView.document = document
        if autoScales {
            pdfView.autoScales = true
        } else {
            pdfView.autoScales = false
            pdfView.scaleFactor = scale
        }
        pageCount = document.pageCount
        let index = min(max(0, target), max(0, pageCount - 1))
        if let page = document.page(at: index) { pdfView.go(to: page) }
        currentPageIndex = index
        invalidateThumbnails()
    }

    private func invalidateThumbnails() {
        thumbnails.removeAllObjects()
        revision += 1
    }

    /// Copies of every page of the given files, in order, with the documents they came from.
    private func pages(from urls: [URL]) -> (pages: [PDFPage], sources: [PDFDocument], failed: [String]) {
        var pages: [PDFPage] = []
        var opened: [PDFDocument] = []
        var failed: [String] = []
        for url in urls {
            guard let source = PDFDocument(url: url), !source.isLocked else {
                failed.append(url.lastPathComponent)
                continue
            }
            opened.append(source)
            for index in 0..<source.pageCount {
                if let page = source.page(at: index), let copy = page.copy() as? PDFPage { pages.append(copy) }
            }
        }
        return (pages, opened, failed)
    }

    private func reportUnreadable(_ names: [String]) {
        guard !names.isEmpty else { return }
        alert = SessionAlert(title: "Alcuni file sono stati saltati",
                             message: "Non sono riuscita a leggere: " + names.joined(separator: ", ") + ". Se sono protetti da password, aprili e salvali senza protezione prima di aggiungerli.")
    }

    private func pickPDFs(multiple: Bool, message: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        panel.message = message
        return panel.runModal() == .OK ? panel.urls : []
    }

    private func pickSaveURL(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName
        panel.directoryURL = fileURL?.deletingLastPathComponent()
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func displayedSize(of page: PDFPage) -> CGSize {
        let bounds = page.bounds(for: .cropBox)
        let sideways = page.rotation % 180 != 0
        return sideways ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
    }

    private func syncPage() {
        guard let document, let page = pdfView.currentPage else { return }
        let index = document.index(for: page)
        guard index != NSNotFound, index != currentPageIndex else { return }
        currentPageIndex = index
        // With one page selected or none, the selection follows the page being read.
        if selectedPages.count <= 1 {
            selectedPages = [index]
            selectionAnchor = index
        }
    }

    private func syncZoom() {
        let scale = Double(pdfView.scaleFactor)
        if abs(scale - zoom) > 0.0005 { zoom = scale }
    }

    // MARK: Types

    private struct UndoStep {
        let name: String
        let snapshot: Snapshot
    }

    /// The document's pages, in order, and its text boxes, as they were at one moment.
    private struct Snapshot {
        let pages: [PDFPage]
        let rotations: [Int]
        let textBoxes: [TextBoxState]
        let selectedPages: Set<Int>
    }

    private struct TextBoxState {
        let annotation: PDFAnnotation
        let page: PDFPage
        let bounds: CGRect
        let contents: String
        let font: NSFont
        let fontColor: NSColor
    }

    private struct DragState {
        let box: PDFAnnotation
        let page: PDFPage
        let start: CGPoint
        let offset: CGPoint
        var isMoving: Bool
    }
}
