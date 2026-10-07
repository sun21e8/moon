import SwiftUI

/// The panel on the right: a thumbnail for every page, and the commands that work on the selected ones.
struct PagesPanel: View {
    let session: EditorSession
    let width: CGFloat
    static let widthLimits: ClosedRange<Double> = 236...360

    @State private var dropIsHovering = false

    private var thumbnailWidth: CGFloat { min(150, max(84, width - 96)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if session.document == nil { placeholder } else { pageList }
            Divider()
            footer
        }
        .frame(width: width)
        .overlay {
            if dropIsHovering {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(3)
                    .allowsHitTesting(false)
            }
        }
        // A PDF dropped here is added to the open document; dropped on the page area it's opened instead.
        .dropDestination(for: URL.self) { urls, _ in
            let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            guard !pdfs.isEmpty else { return false }
            if session.document == nil, let first = pdfs.first {
                session.open(first)
            } else {
                session.addPages(from: pdfs)
            }
            return true
        } isTargeted: { dropIsHovering = $0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Pagine").font(Chrome.titleFont)
            Spacer()
            Text(verbatim: "\(session.pageCount)")
                .font(Chrome.textFont.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Chrome.sideInset)
        .frame(height: Chrome.barHeight)
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.doc").font(.system(size: 26, weight: .light))
            Text("Nessun documento").font(.callout.weight(.medium))
            Text("Apri un PDF per vederne le pagine.")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(0..<session.pageCount, id: \.self) { index in
                        PageCell(session: session, index: index, width: thumbnailWidth)
                            .id(index)
                    }
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            // A different document starts again from the top.
            .id(session.generation)
            .onChange(of: session.currentPageIndex) { _, index in
                proxy.scrollTo(index)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 0) {
            iconButton("plus", "Aggiungi pagine da altri PDF…") { session.presentAddPagesPanel() }
            iconButton("rotate.left", "Ruota a sinistra (⌘L)") { session.rotateSelectedPages(clockwise: false) }
            iconButton("rotate.right", "Ruota a destra (⌘R)") { session.rotateSelectedPages(clockwise: true) }
            iconButton("arrow.up", "Sposta prima (⌥⌘↑)") { session.moveSelectedPages(by: -1) }
            iconButton("arrow.down", "Sposta dopo (⌥⌘↓)") { session.moveSelectedPages(by: 1) }
            iconButton("square.and.arrow.up", "Estrai le pagine selezionate in un nuovo PDF…") { session.extractSelectedPages() }
            Spacer(minLength: 0)
            iconButton("trash", "Elimina le pagine selezionate (⌘⌫)") { session.deleteSelectedPages() }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(height: 38)
        .disabled(session.document == nil)
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 28, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}

/// One page in the list: its thumbnail and number. Selected pages are outlined; the page being read has its
/// number in full white.
private struct PageCell: View {
    let session: EditorSession
    let index: Int
    let width: CGFloat

    var body: some View {
        // Reading the revision makes the cell redraw when an edit changes how pages look.
        let _ = session.revision
        let isSelected = session.selectedPages.contains(index)
        let isCurrent = session.currentPageIndex == index
        let height = width * session.pageAspect(at: index)
        Button {
            session.selectPage(index, modifiers: NSEvent.modifierFlags)
        } label: {
            VStack(spacing: 6) {
                thumbnail
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                    }
                Text(verbatim: "\(index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.08 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "Pagina \(index + 1)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var thumbnail: some View {
        if let image = session.thumbnail(for: index, width: width) {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            Color.white
        }
    }
}
