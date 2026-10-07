import PDFKit
import SwiftUI

/// Puts the session's PDF view in the window. The session owns the view and drives it.
struct PDFCanvas: NSViewRepresentable {
    let session: EditorSession

    func makeNSView(context: Context) -> CanvasPDFView { session.pdfView }

    func updateNSView(_ view: CanvasPDFView, context: Context) {}
}
