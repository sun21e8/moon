import Foundation

/// The tools on the rail. `select` and `text` work; the others are waiting for the editing engine and show as
/// unavailable until it lands.
enum Tool: String, CaseIterable, Identifiable {
    case select, highlight, note, draw, shape, text, sign, redact

    var id: String { rawValue }

    var label: String {
        switch self {
        case .select: return "Selezione"
        case .highlight: return "Evidenziatore"
        case .note: return "Nota"
        case .draw: return "Disegno"
        case .shape: return "Forme"
        case .text: return "Testo"
        case .sign: return "Firma"
        case .redact: return "Redazione"
        }
    }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .highlight: return "highlighter"
        case .note: return "note.text"
        case .draw: return "pencil.tip"
        case .shape: return "square.on.circle"
        case .text: return "textformat"
        case .sign: return "signature"
        case .redact: return "eye.slash"
        }
    }

    var isAvailable: Bool { self == .select || self == .text }

    /// What the status bar says while the tool is active.
    var hint: String {
        switch self {
        case .text: return "Clicca sulla pagina per aggiungere testo · Clicca un testo per modificarlo · Trascinalo per spostarlo"
        default: return "Trascina per selezionare il testo · Clicca un testo aggiunto per modificarlo · Pizzica per lo zoom"
        }
    }
}

/// How pages are laid out in the canvas.
enum PageLayout: String, CaseIterable, Identifiable {
    case continuous, single, twoUp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .continuous: return "Continuo"
        case .single: return "Pagina singola"
        case .twoUp: return "Due pagine"
        }
    }
}
