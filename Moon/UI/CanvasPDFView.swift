import AppKit
import PDFKit

/// The PDF view in the canvas. It offers each mouse event to the session first — which uses it to add, pick and
/// move text boxes — and otherwise behaves as a plain PDF view (text selection, links, scrolling).
final class CanvasPDFView: PDFView {
    weak var session: EditorSession?

    override func mouseDown(with event: NSEvent) {
        if let session, session.canvasMouseDown(event) { return }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if let session, session.canvasMouseDragged(event) { return }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if let session, session.canvasMouseUp(event) { return }
        super.mouseUp(with: event)
    }
}
