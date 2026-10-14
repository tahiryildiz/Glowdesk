import SwiftUI
import AppKit

// "Light desk" design tokens: a matte console body with silkscreen type.
// The interface itself stays nearly colorless; the lights supply the color.
enum Ink {
    static let body = Color(red: 0x1A / 255, green: 0x19 / 255, blue: 0x17 / 255)
    static let well = Color(red: 0x24 / 255, green: 0x22 / 255, blue: 0x1F / 255)
    static let raised = Color(red: 0x2D / 255, green: 0x2A / 255, blue: 0x26 / 255)
    static let line = Color(red: 0x37 / 255, green: 0x34 / 255, blue: 0x2F / 255)
    static let text = Color(red: 0xF2 / 255, green: 0xEE / 255, blue: 0xE6 / 255)
    static let muted = Color(red: 0x9A / 255, green: 0x94 / 255, blue: 0x8A / 255)
    static let faint = Color(red: 0x5E / 255, green: 0x59 / 255, blue: 0x51 / 255)
    static let dark = Color(red: 0x1A / 255, green: 0x16 / 255, blue: 0x10 / 255)
    /// Readable ink on top of a light-colored fill.
    static func on(_ rgb: RGB) -> Color { rgb.luminance > 0.45 ? dark : text }
}

extension Font {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy).width(.expanded) }
    static func numeral(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight).width(.condensed).monospacedDigit() }
}

let mutedInk = Ink.muted

struct PrimaryButton: ButtonStyle {
    var fill: Color = Ink.text
    var ink: Color = Ink.dark
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 16).frame(minHeight: 34)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill.opacity(configuration.isPressed ? 0.8 : 1)))
            .contentShape(Rectangle())
    }
}

struct QuietButton: ButtonStyle {
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(active ? Ink.dark : Ink.muted)
            .padding(.horizontal, 12).frame(minHeight: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(active ? Ink.text.opacity(configuration.isPressed ? 0.8 : 1) : configuration.isPressed ? Ink.raised : Ink.body))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(active ? .clear : Ink.line, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// Icon tabs: the selected tab shows its icon and name, the rest only their icons (named in tooltips).
struct IconTabs<Item: Hashable>: View {
    let items: [Item]
    let symbol: (Item) -> String
    let title: (Item) -> String
    @Binding var selection: Item
    var tint: Color = Ink.text
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let selected = item == selection
                Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { selection = item } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: symbol(item)).font(.system(size: 14, weight: .medium))
                            .foregroundStyle(selected ? tint : Ink.muted)
                        if selected { Text(title(item)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.text).fixedSize() }
                    }
                    .padding(.horizontal, selected ? 12 : 0)
                    .frame(minWidth: 40).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Ink.raised : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(title(item))
                .accessibilityLabel(title(item))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

/// Text tabs with an underline in the color of the lights.
struct TextTabs<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item
    var tint: Color = Ink.text
    var size: CGFloat = 13
    var body: some View {
        HStack(spacing: 14) {
            ForEach(items, id: \.self) { item in
                let selected = item == selection
                Button { selection = item } label: {
                    VStack(spacing: 5) {
                        Text(title(item)).font(.system(size: size, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Ink.text : Ink.muted).lineLimit(1).fixedSize()
                        Capsule().fill(selected ? tint : .clear).frame(height: 2)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Detents at 25, 50 and 75: a light trackpad tap when a fader crosses one, like a console fader's notch.
enum Detent {
    static func band(_ value: Double) -> Int { value < 25 ? 0 : value < 50 ? 1 : value < 75 ? 2 : 3 }
    static func feel(from old: Double, to new: Double) {
        guard band(old) != band(new) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

enum ScrollLevel {
    /// Level change for one scroll event: positive means more light (fingers or wheel up, or right).
    /// AppKit reports "scroll up" and "scroll left" as positive, and natural scrolling flips both.
    static func amount(_ event: NSEvent, vertical: Bool) -> Double {
        let raw = vertical ? event.scrollingDeltaY : -event.scrollingDeltaX
        let towardMore = event.isDirectionInvertedFromDevice ? -raw : raw
        return Double(towardMore) * (event.hasPreciseScrollingDeltas ? 0.25 : 3)
    }
}

/// Turns scroll-wheel and two-finger trackpad scrolling over a view into level changes,
/// without stealing clicks or drags from the views above it.
struct ScrollCatcher: NSViewRepresentable {
    let axis: Axis
    let onScroll: (Double) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.axis = axis; view.onScroll = onScroll
        return view
    }
    func updateNSView(_ view: CatcherView, context: Context) { view.axis = axis; view.onScroll = onScroll }

    final class CatcherView: NSView {
        var axis: Axis = .vertical
        var onScroll: ((Double) -> Void)?
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window, !self.isHiddenOrHasHiddenAncestor else { return event }
                guard self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                let vertical = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
                // Lists still scroll normally: only the fader's own axis is captured.
                guard (self.axis == .vertical) == vertical else { return event }
                let amount = ScrollLevel.amount(event, vertical: vertical)
                if amount != 0 { self.onScroll?(amount) }
                return nil
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

/// One room as a vertical fader: filled from the bottom with the room's own light, as bright as the room is.
struct Channel: View {
    let name: String
    let symbol: String
    let on: Bool
    let level: Double
    let color: RGB
    let selected: Bool
    var index = 0
    var revealed = true
    let onToggle: () -> Void
    let onLevel: (Double) -> Void
    let onSelect: () -> Void
    @State private var dragLevel: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func set(_ next: Double) {
        Detent.feel(from: on ? (dragLevel ?? level) : 0, to: next)
        onLevel(next)
    }

    var body: some View {
        let shown = dragLevel ?? level
        let visible = revealed || reduceMotion
        VStack(spacing: 9) {
            GeometryReader { geometry in
                let height = geometry.size.height
                let fill = on && visible ? max(0.04, shown / 100) * height : 0
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Ink.well)
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { _ in Spacer(); Rectangle().fill(Ink.line).frame(height: 1) }
                        Spacer()
                    }.padding(.horizontal, 10)
                    if on {
                        VStack(spacing: 0) {
                            Rectangle().fill(Color.white.opacity(0.9)).frame(height: 2)
                            LinearGradient(colors: [color.color, color.color.opacity(0.78)], startPoint: .top, endPoint: .bottom)
                        }
                        .frame(height: fill)
                        .animation(reduceMotion || dragLevel != nil ? nil : .spring(response: 0.6, dampingFraction: 0.82).delay(0.055 * Double(index)), value: revealed)
                    }
                    VStack {
                        Text(on ? "\(Int(shown.rounded()))" : t("off"))
                            .font(on ? .numeral(22) : .system(size: 11, weight: .medium))
                            .foregroundStyle(on && shown > 80 && visible ? Ink.on(color) : on ? Ink.text : Ink.faint)
                            .padding(.top, 10)
                        Spacer()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(selected ? Ink.text.opacity(0.55) : Ink.line, lineWidth: selected ? 1.2 : 1))
                .animation(reduceMotion || dragLevel != nil ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: on)
                .background(ScrollCatcher(axis: .vertical) { delta in
                    let base = on ? level : 0
                    guard on || delta > 0 else { return }
                    set(min(100, max(1, base + delta)))
                })
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 3).onChanged { drag in
                    let next = min(100, max(1, (1 - drag.location.y / height) * 100))
                    set(next); dragLevel = next
                }.onEnded { _ in dragLevel = nil })
                .simultaneousGesture(TapGesture().onEnded(onToggle))
            }
            Button(action: onSelect) {
                VStack(spacing: 4) {
                    Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(on ? color.color : Ink.faint)
                    Text(name).font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Ink.text : Ink.muted).lineLimit(2).multilineTextAlignment(.center)
                        .frame(height: 28, alignment: .top)
                }.frame(maxWidth: .infinity).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(on ? t("%d percent", Int(level)) : t("off"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onToggle() }
        .accessibilityAdjustableAction { direction in
            onLevel(min(100, max(1, level + (direction == .increment ? 10 : -10))))
        }
    }
}

/// One light as a horizontal fader bar.
struct LevelBar: View {
    let name: String
    var symbol = "lightbulb"
    let detail: String
    let on: Bool
    let level: Double
    let color: RGB
    let expanded: Bool
    let onToggle: () -> Void
    let onLevel: (Double) -> Void
    let onExpand: () -> Void
    @State private var dragLevel: Double?

    private func set(_ next: Double) {
        Detent.feel(from: on ? (dragLevel ?? level) : 0, to: next)
        onLevel(next)
    }

    var body: some View {
        let shown = dragLevel ?? level
        HStack(spacing: 6) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let fraction = on ? max(0.03, shown / 100) : 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Ink.well)
                    // Ruler notches at 25, 50 and 75 along the bottom edge.
                    VStack(spacing: 0) {
                        Spacer()
                        HStack(spacing: 0) {
                            ForEach(0..<3, id: \.self) { _ in Spacer(); Rectangle().fill(Ink.faint).frame(width: 1) }
                            Spacer()
                        }.frame(height: 5)
                    }
                    if on {
                        HStack(spacing: 0) {
                            color.color.opacity(0.92)
                            Rectangle().fill(Color.white.opacity(0.9)).frame(width: 2)
                        }.frame(width: fraction * width)
                    }
                    HStack(alignment: .center) {
                        HStack(spacing: 9) {
                            Image(systemName: symbol).font(.system(size: 14)).frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(detail).font(.system(size: 10)).opacity(0.75).lineLimit(1)
                            }
                        }.foregroundStyle(on && fraction > 0.3 ? Ink.on(color) : on ? Ink.text : Ink.muted)
                        Spacer(minLength: 6)
                        Text(on ? "\(Int(shown.rounded()))" : "")
                            .font(.numeral(17))
                            .foregroundStyle(on && fraction > 0.9 ? Ink.on(color) : Ink.text)
                    }.padding(.horizontal, 11)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .background(ScrollCatcher(axis: .horizontal) { delta in
                    guard on || delta > 0 else { return }
                    set(min(100, max(1, (on ? level : 0) + delta)))
                })
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 3).onChanged { drag in
                    let next = min(100, max(1, drag.location.x / width * 100))
                    set(next); dragLevel = next
                }.onEnded { _ in dragLevel = nil })
                .simultaneousGesture(TapGesture().onEnded(onToggle))
            }.frame(height: 44)
            Button(action: onExpand) {
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(expanded ? Ink.text : Ink.muted)
                    .rotationEffect(.degrees(expanded ? 180 : 0)).frame(width: 26, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).help(t("Color and white tone")).accessibilityLabel(t("%@ color settings", name))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
        .accessibilityValue(on ? t("%d percent", Int(level)) : t("off"))
    }
}

/// A scene drawn like a theatrical gel swatch: hard-edged bands, no blending.
struct GelSwatch: View {
    let colors: [RGB]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array((colors.isEmpty ? [RGB(r: 0.35, g: 0.33, b: 0.3)] : colors).enumerated()), id: \.offset) { _, rgb in rgb.color }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
    }
}

/// A flat track with a custom gradient, used for color temperature.
struct GradientSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let colors: [Color]
    let onChange: (Double) -> Void
    @State private var dragValue: Double?
    var body: some View {
        GeometryReader { geometry in
            let span = range.upperBound - range.lowerBound
            let fraction = ((dragValue ?? value) - range.lowerBound) / max(span, 0.0001)
            let travel = max(1, geometry.size.width - 14)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)).frame(height: 10)
                RoundedRectangle(cornerRadius: 3).fill(Ink.text).frame(width: 14, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Ink.dark.opacity(0.5), lineWidth: 1))
                    .offset(x: min(travel, max(0, fraction * travel)))
            }
            .frame(maxHeight: .infinity).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let f = min(1, max(0, (drag.location.x - 7) / travel))
                let next = range.lowerBound + f * span
                dragValue = next; onChange(next)
            }.onEnded { _ in dragValue = nil })
        }.frame(height: 24)
    }
}

/// Hue runs left to right, saturation fades toward the bottom.
struct ColorPad: View {
    let current: RGB?
    let onPick: (RGB) -> Void
    @State private var marker: CGPoint?
    private static let spectrum = stride(from: 0.0, through: 1.0, by: 1.0 / 12).map { Color(hue: $0, saturation: 1, brightness: 1) }
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let position = marker ?? current.map { rgb -> CGPoint in
                let hs = rgb.hueSaturation
                return CGPoint(x: hs.hue * size.width, y: (1 - hs.saturation) * size.height)
            }
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: Self.spectrum, startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .bottom)
                if let position {
                    Circle().strokeBorder(Ink.dark, lineWidth: 2).background(Circle().strokeBorder(Color.white, lineWidth: 4))
                        .frame(width: 18, height: 18)
                        .position(x: min(size.width - 6, max(6, position.x)), y: min(size.height - 6, max(6, position.y)))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let x = min(size.width, max(0, drag.location.x)), y = min(size.height, max(0, drag.location.y))
                marker = CGPoint(x: x, y: y)
                onPick(.hsb(min(0.999, x / size.width), 1 - y / size.height, 1))
            }.onEnded { _ in marker = nil })
        }
        .frame(height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel(t("Color picker"))
    }
}

enum Presets {
    static let colors: [RGB] = [0.0, 0.05, 0.11, 0.3, 0.5, 0.6, 0.72, 0.85].map { RGB.hsb($0, 1, 1) }
    /// 2200 K, 2700 K, 4000 K, 6500 K
    static let whites: [Int] = [454, 370, 250, 153]
}

/// Quick whites and colors, as small gel chips.
struct SwatchRow: View {
    var showColors = true
    var showWhites = true
    let onColor: (RGB) -> Void
    let onMirek: (Int) -> Void
    var body: some View {
        HStack(spacing: 4) {
            if showWhites {
                ForEach(Presets.whites, id: \.self) { mirek in
                    chip(ColorMath.mirekToRGB(mirek).color, help: t("%d K white", ColorMath.kelvin(mirek))) { onMirek(mirek) }
                }
            }
            if showWhites && showColors { Spacer().frame(width: 8) }
            if showColors {
                ForEach(Presets.colors, id: \.self) { rgb in chip(rgb.color, help: t("Switch to this color")) { onColor(rgb) } }
            }
            Spacer(minLength: 0)
        }
    }
    private func chip(_ color: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color).frame(minWidth: 12, maxWidth: 20).frame(height: 26)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}

struct MiniToggle: View {
    let isOn: Bool
    let tint: Color
    let action: (Bool) -> Void
    var body: some View {
        Toggle("", isOn: Binding(get: { isOn }, set: action)).toggleStyle(.switch).controlSize(.mini).labelsHidden().tint(tint)
    }
}

func durationText(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds) / 60
    if minutes == 0 { return t("%d s", Int(seconds)) }
    return minutes >= 60 ? t("%d h %d min", minutes / 60, minutes % 60) : t("%d min", minutes)
}

/// "Den", "Den and Kitchen", "Den, Kitchen and Bath"
func naturalList(_ items: [String]) -> String {
    guard items.count > 1 else { return items.first ?? "" }
    return items.dropLast().joined(separator: ", ") + t(" and ") + items.last!
}
