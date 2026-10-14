import AppKit
import SwiftUI
import Combine

final class HuePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct PanelArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - 11, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX - 3, y: rect.minY + 2), control: CGPoint(x: rect.midX - 6, y: rect.maxY - 6))
        path.addQuadCurve(to: CGPoint(x: rect.midX + 3, y: rect.minY + 2), control: CGPoint(x: rect.midX, y: rect.minY - 2))
        path.addQuadCurve(to: CGPoint(x: rect.midX + 11, y: rect.maxY), control: CGPoint(x: rect.midX + 6, y: rect.maxY - 6))
        path.closeSubpath()
        return path
    }
}

private struct PanelShell: View {
    @ObservedObject var store: HueStore
    let height: CGFloat
    let arrowX: CGFloat
    var body: some View {
        VStack(spacing: 0) {
            PanelArrow().fill(Ink.body)
                .frame(width: 24, height: 11).frame(width: 360, alignment: .leading).offset(x: arrowX - 12)
            PanelView(store: store).frame(width: 360, height: height - 11)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.7))
        }.frame(width: 360, height: height).preferredColorScheme(.dark)
    }
}

/// The status item: a yellow, filled bulb while any light is on; the system's plain bulb when all are off.
enum MenuBarIcon {
    static let lit = NSColor(srgbRed: 1, green: 0.78, blue: 0.1, alpha: 1)

    static func image(on: Bool, syncing: Bool) -> NSImage {
        let size = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        guard on || syncing else {
            let image = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: t("Lights off"))?.withSymbolConfiguration(size) ?? NSImage()
            image.isTemplate = true
            return image
        }
        let symbol = syncing ? "sparkles.tv.fill" : "lightbulb.fill"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: t("Lights on"))?
            .withSymbolConfiguration(size.applying(.init(paletteColors: [lit]))) ?? NSImage()
        image.isTemplate = false
        return image
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = HueStore()
    var statusItem: NSStatusItem!
    let panel = HuePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var host: NSHostingController<PanelShell>?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateIcon()
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .popUpMenu; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        store.$preferredPanelHeight.dropFirst().removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { if self?.panel.isVisible == true { self?.show() } }
        }.store(in: &subscriptions)
        store.$language.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateIcon() }
        }.store(in: &subscriptions)
        store.$lights.combineLatest(store.$syncing, store.$connected).sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateIcon() }
        }.store(in: &subscriptions)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.hide() }
        }
        // Scrolling over the menu bar icon dims or brightens the lit lights without opening the panel.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.statusItem.button?.window, event.window === window else { return event }
            let amount = ScrollLevel.amount(event, vertical: abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX))
            if amount != 0 { self.store.nudgeAll(by: amount) }
            return nil
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, self?.panel.isVisible == true { self?.hide(); return nil }
            return event
        }
        store.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !CommandLine.arguments.contains("--background") && !self.store.isPaired { self.show() }
        }
    }

    private func updateIcon() {
        statusItem.button?.image = MenuBarIcon.image(on: store.connected && store.anyOn, syncing: store.syncing)
        statusItem.button?.appearsDisabled = !store.connected && store.isPaired
        statusItem.button?.setAccessibilityLabel(store.connected ? "Glowdesk, " + (store.anyOn ? t("Lights on") : t("Lights off")).lowercased() : "Glowdesk")
        statusItem.button?.toolTip = store.connected ? t("Scroll to dim or brighten your lights") : nil
    }

    func hide() {
        panel.orderOut(nil)
        store.panelVisible = false
    }

    /// Left click opens the panel; right click (or Control-click) shows the app menu.
    @objc func statusClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu(); return
        }
        if panel.isVisible { hide() } else { show() }
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        hide()
        let menu = NSMenu()
        menu.addItem(withTitle: t("About Glowdesk"), action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: t("Buy me a coffee"), action: #selector(openCoffee), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: t("Quit Glowdesk"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    static let coffeeURL = URL(string: "https://buymeacoffee.com/tahiryildiz")!

    @objc private func openCoffee() { NSWorkspace.shared.open(Self.coffeeURL) }

    @objc private func showAbout() {
        let credits = NSAttributedString(string: t("Your Philips Hue lights, in the menu bar.\nTalks to your bridge over the local network only.\nNot affiliated with Philips or Signify."),
                                         attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        let text = NSMutableAttributedString(attributedString: credits)
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        text.append(NSAttributedString(string: "\n\n"))
        text.append(NSAttributedString(string: "☕ " + t("Buy me a coffee"), attributes: [
            .link: Self.coffeeURL, .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
        ]))
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        let options: [NSApplication.AboutPanelOptionKey: Any] = [.applicationName: "Glowdesk", .credits: text]
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }

    func show() {
        guard let button = statusItem.button, let anchorWindow = button.window else { return }
        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = anchorWindow.screen ?? NSScreen.main!
        let visible = screen.visibleFrame
        let top = min(anchor.minY - 3, visible.maxY - 3)
        let available = max(300, top - visible.minY - 12)
        if store.maxPanelHeight != available { store.maxPanelHeight = available }
        let height = min(max(store.preferredPanelHeight, 200), available)
        let x = min(max(anchor.midX - 180, visible.minX + 8), visible.maxX - 368)
        let root = PanelShell(store: store, height: height, arrowX: min(342, max(18, anchor.midX - x)))
        if let host { host.rootView = root }
        else { let controller = NSHostingController(rootView: root); host = controller; panel.contentViewController = controller }
        // Screen coordinates keep AppKit from flipping the panel above the menu bar.
        panel.setFrame(NSRect(x: x, y: top - height, width: 360, height: height), display: true)
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if !store.panelVisible { store.panelVisible = true }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.disconnect()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
    }
}

let app = NSApplication.shared
if CommandLine.arguments.contains("--help") {
    print("""
    Glowdesk — Philips Hue lights in your Mac menu bar

    Open the app normally and pair your bridge in Settings.
    --background   Start without showing the panel.
    --self-check   Run offline checks without touching the bridge or saved pairing.
    """)
} else if CommandLine.arguments.contains("--self-check") {
    Task { @MainActor in
        do { try await FeatureChecks.run(); exit(0) } catch { print("FAIL: \(error)"); exit(1) }
    }
    RunLoop.main.run()
} else if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > index + 1 {
    #if DEBUG
    MainActor.assumeIsolated { Snapshot.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
    #else
    print("--snapshot is only available in debug builds.")
    #endif
} else {
    LegacyMigration.run()
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
