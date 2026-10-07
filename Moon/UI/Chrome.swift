import SwiftUI

/// Sizes, colors and fonts shared by the window's bars and panels, so they line up and read as one surface.
enum Chrome {
    static let barHeight: CGFloat = 42
    static let statusHeight: CGFloat = 30
    static let railWidth: CGFloat = 56
    static let sideInset: CGFloat = 18

    static let window = Color(white: 0.14)
    static let canvas = Color(white: 0.09)

    static let titleFont = Font.system(size: 13, weight: .semibold)
    static let textFont = Font.system(size: 12)
    static let statusFont = Font.system(size: 11).monospacedDigit()
}

/// How a tool looks on the rail: a square icon, lit while it's the active tool and dimmer while pressed.
struct RailButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17))
            .frame(width: 36, height: 36)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isActive ? 0.13 : (configuration.isPressed ? 0.07 : 0)))
            }
            .contentShape(Rectangle())
    }
}

/// The edge between the document and a panel on its right. Dragging it left widens the panel, right narrows it.
struct PanelDivider: View {
    @Binding var width: Double
    let limits: ClosedRange<Double>
    @State private var widthAtDragStart: Double?

    var body: some View {
        Divider().overlay {
            // Wider than the line itself, so it's easy to grab.
            Rectangle().fill(Color.clear)
                .frame(width: 9)
                .contentShape(Rectangle())
                .pointerStyle(.columnResize)
                .gesture(resize)
                .help("Trascina per allargare o stringere il pannello")
        }
    }

    private var resize: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let origin = widthAtDragStart ?? width
                widthAtDragStart = origin
                let proposed = (origin - Double(value.translation.width)).rounded()
                width = min(max(proposed, limits.lowerBound), limits.upperBound)
            }
            .onEnded { _ in widthAtDragStart = nil }
    }
}
