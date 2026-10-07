import SwiftUI

/// The editor window. From the top: the options for the active tool, the working area (tools, document, pages)
/// and the status line.
struct ContentView: View {
    let session: EditorSession
    /// The Pages panel's width, remembered between launches.
    @AppStorage("pagesPanelWidth") private var storedPanelWidth = 252.0
    @State private var dropIsHovering = false
    @FocusState private var textFieldFocused: Bool

    private var panelWidth: Double {
        min(max(storedPanelWidth, PagesPanel.widthLimits.lowerBound), PagesPanel.widthLimits.upperBound)
    }

    var body: some View {
        VStack(spacing: 0) {
            optionsBar
            Divider()
            HStack(spacing: 0) {
                toolRail
                Divider()
                documentArea
                PanelDivider(width: $storedPanelWidth, limits: PagesPanel.widthLimits)
                PagesPanel(session: session, width: CGFloat(panelWidth))
            }
            Divider()
            statusLine
        }
        .background(Chrome.window)
        .frame(minWidth: 820, minHeight: 520)
        .preferredColorScheme(.dark)
        .navigationTitle(session.title)
        .toolbar { toolbarItems }
        .alert(session.alert?.title ?? "", isPresented: alertIsShown) {
            Button("OK") { session.alert = nil }
        } message: {
            Text(session.alert?.message ?? "")
        }
        .onChange(of: session.textFocusRequest) { _, _ in textFieldFocused = true }
    }

    private var alertIsShown: Binding<Bool> {
        Binding(get: { session.alert != nil }, set: { shown in if !shown { session.alert = nil } })
    }

    // MARK: Window toolbar

    @ToolbarContentBuilder private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { session.presentOpenPanel() } label: { Label("Apri", systemImage: "folder") }
                .help("Apri un PDF (⌘O)")
        }
        ToolbarItem(placement: .navigation) {
            Button { _ = session.save() } label: { Label("Salva", systemImage: "square.and.arrow.down") }
                .help("Salva (⌘S)")
                .disabled(session.document == nil || !session.isDirty)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Adatta") { session.zoomToFit() }
                .help("Adatta la pagina alla finestra (⌘0)")
                .disabled(session.document == nil)
            Button("100%") { session.zoomToActualSize() }
                .help("Dimensioni reali (⌘1)")
                .disabled(session.document == nil)
            Button { session.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }
                .help("Ingrandisci (⌘+)")
                .disabled(session.document == nil)
            Button { session.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }
                .help("Riduci (⌘−)")
                .disabled(session.document == nil)
        }
    }

    // MARK: Options bar

    private var optionsBar: some View {
        HStack(spacing: 16) {
            Text(session.tool.label).font(Chrome.titleFont)
            if session.selectedTextBox != nil {
                textBoxOptions
            } else if session.document != nil {
                viewOptions
            }
            Spacer(minLength: 0)
        }
        .font(Chrome.textFont)
        .padding(.horizontal, Chrome.sideInset)
        .frame(height: Chrome.barHeight)
    }

    /// How the pages are laid out, and which one is showing.
    @ViewBuilder private var viewOptions: some View {
        Picker("Vista", selection: Binding(get: { session.layout }, set: { session.setLayout($0) })) {
            ForEach(PageLayout.allCases) { layout in
                Text(layout.label).tag(layout)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        HStack(spacing: 8) {
            Button { session.goToPage(session.currentPageIndex - 1) } label: { Image(systemName: "chevron.left") }
                .help("Pagina precedente (⌥⌘←)")
                .disabled(!session.canGoBack)
            Text(verbatim: session.pageDescription).monospacedDigit()
            Button { session.goToPage(session.currentPageIndex + 1) } label: { Image(systemName: "chevron.right") }
                .help("Pagina successiva (⌥⌘→)")
                .disabled(!session.canGoForward)
        }
        .buttonStyle(.borderless)
    }

    /// Shown while a text box is selected: its words, size and color, and a way to remove it.
    @ViewBuilder private var textBoxOptions: some View {
        TextField("Testo", text: Binding(get: { session.textDraft }, set: { session.setText($0) }))
            .textFieldStyle(.roundedBorder)
            .frame(width: 280)
            .focused($textFieldFocused)
            .onSubmit { textFieldFocused = false }
        Stepper(value: Binding(get: { session.textSize }, set: { session.setTextSize($0) }), in: 6...144, step: 1) {
            Text(verbatim: "\(Int(session.textSize)) pt").monospacedDigit()
        }
        .help("Dimensione del testo")
        ColorPicker("Colore", selection: Binding(get: { Color(nsColor: session.textColor) },
                                                 set: { session.setTextColor(NSColor($0)) }), supportsOpacity: false)
            .labelsHidden()
            .help("Colore del testo")
        Button { session.deleteSelectedTextBox() } label: { Image(systemName: "trash") }
            .buttonStyle(.borderless)
            .help("Elimina questo testo (⌘⌫)")
        Button("Fine") { session.deselectTextBox() }
            .help("Termina la modifica del testo")
    }

    // MARK: Tool rail

    private var toolRail: some View {
        // In a scroll view, so a short window scrolls the tools instead of squeezing the bars.
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(Tool.allCases) { tool in
                    Button { session.tool = tool } label: { Image(systemName: tool.symbol) }
                        .buttonStyle(RailButtonStyle(isActive: session.tool == tool))
                        .help(tool.isAvailable ? tool.label : tool.label + " — in arrivo")
                        .accessibilityLabel(Text(tool.label))
                        .disabled(!tool.isAvailable)
                        .opacity(tool.isAvailable ? 1 : 0.35)
                }
            }
            .padding(.vertical, 14)
            .frame(width: Chrome.railWidth)
        }
        .frame(width: Chrome.railWidth)
    }

    // MARK: Document

    private var documentArea: some View {
        ZStack {
            PDFCanvas(session: session)
            if session.document == nil { welcome }
        }
        .overlay {
            if dropIsHovering {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(3)
                    .allowsHitTesting(false)
            }
        }
        // A PDF dropped on the page area is opened; dropped on the Pages panel it's added to the open document.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return false }
            session.open(url)
            return true
        } isTargeted: { dropIsHovering = $0 }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
            Text("Moon").font(.system(size: 22, weight: .semibold))
            Text("Apri un PDF o trascinalo in questa finestra.")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Apri PDF…") { session.presentOpenPanel() }
                    .buttonStyle(.borderedProminent)
                Button("Unisci più PDF…") { session.presentCombinePanel() }
            }
            .controlSize(.large)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Chrome.canvas)
    }

    // MARK: Status line

    private var statusLine: some View {
        HStack(spacing: 16) {
            if session.document != nil {
                Text(verbatim: session.zoomDescription).frame(width: 56, alignment: .leading)
                Text(verbatim: session.pageDescription)
                if let size = session.pageSizeDescription { Text(verbatim: size) }
                if let selection = session.selectionDescription { Text(verbatim: selection) }
                Spacer(minLength: 12)
                Text(verbatim: session.tool.hint)
            } else {
                Text("Pronta quando vuoi")
                Spacer(minLength: 0)
            }
        }
        .font(Chrome.statusFont)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, Chrome.sideInset)
        .frame(height: Chrome.statusHeight)
    }
}
