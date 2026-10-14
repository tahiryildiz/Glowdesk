import SwiftUI
import AppKit

private enum PanelTab: String, CaseIterable, Identifiable {
    case rooms = "Rooms", lights = "Lights", scenes = "Scenes", sync = "Sync", history = "History"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .rooms: return "slider.vertical.3"
        case .lights: return "lightbulb.2"
        case .scenes: return "sparkles"
        case .sync: return "display"
        case .history: return "chart.bar.xaxis"
        }
    }
}

/// Reads a view's height into a binding, so the panel can size itself to its content.
private struct HeightReader: View {
    @Binding var height: CGFloat
    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { height = geometry.size.height }
                .onChange(of: geometry.size.height) { _, value in height = value }
        }
    }
}

struct PanelView: View {
    @ObservedObject var store: HueStore
    @State private var tab: PanelTab
    @State private var settings: Bool
    @State private var expanded: Set<String>
    @State private var selectedRoomID: String?
    @State private var sceneGroupID: String?
    @State private var usageDays = 1
    @State private var draftHost = ""
    @State private var manualAddress = false
    @State private var showDetails = false
    @State private var pairedHere = false
    @State private var revealed: Bool
    @State private var topHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var bottomHeight: CGFloat = 0
    private let contentWidth: CGFloat = 328
    static let arrowHeight: CGFloat = 11

    init(store: HueStore, startTab: Int = 0, showSettings: Bool = false, expanded: Set<String> = [], revealed: Bool = false) {
        self.store = store
        _revealed = State(initialValue: revealed)
        _tab = State(initialValue: PanelTab.allCases[startTab])
        _settings = State(initialValue: showSettings)
        _expanded = State(initialValue: expanded)
    }

    private var accent: Color { store.accent.color }
    private var naturalHeight: CGFloat { (topHeight + contentHeight + bottomHeight).rounded(.up) + Self.arrowHeight }
    /// The page only scrolls when its content can't fit on screen, so scrolling never fights the faders.
    private var fits: Bool { naturalHeight <= store.maxPanelHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.top, 18).padding(.bottom, 14)
                if !settings {
                    IconTabs(items: PanelTab.allCases, symbol: \.symbol, title: { t($0.rawValue) }, selection: $tab, tint: store.anyOn ? accent : Ink.text)
                        .padding(.bottom, 12)
                }
                Rectangle().fill(Ink.line).frame(height: 1).padding(.horizontal, -16)
            }.background(HeightReader(height: $topHeight))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if settings { settingsPanel }
                    else if !store.connected && store.lights.isEmpty { connectionPanel }
                    else {
                        switch tab {
                        case .rooms: roomsPanel
                        case .lights: lightsPanel
                        case .scenes: scenesPanel
                        case .sync: syncPanel
                        case .history: historyPanel
                        }
                    }
                    feedback
                }
                .padding(.vertical, 16).frame(width: contentWidth, alignment: .leading)
                .background(HeightReader(height: $contentHeight))
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(fits)
            VStack(spacing: 0) {
                Rectangle().fill(Ink.line).frame(height: 1).padding(.horizontal, -16)
                footer.padding(.vertical, 10)
            }.background(HeightReader(height: $bottomHeight))
        }
        .padding(.horizontal, 16).frame(width: 360)
        .background(Ink.body)
        .foregroundStyle(Ink.text)
        .font(.system(size: 12))
        .tint(Ink.text)
        .preferredColorScheme(.dark)
        .onChange(of: naturalHeight) { _, height in
            if contentHeight > 0, abs(store.preferredPanelHeight - height) > 1 { store.preferredPanelHeight = height }
        }
        .onChange(of: store.pairing) { _, pairing in if pairing { pairedHere = true } }
        .onChange(of: store.connected) { _, connected in
            // After a fresh pairing, go straight to the lights.
            if connected && pairedHere { pairedHere = false; settings = false }
        }
        .onChange(of: store.discovered) { _, found in if draftHost.isEmpty, let first = found.first { draftHost = first.host } }
        .onAppear {
            if !store.isPaired && !store.connected { openSettings() }
            if store.panelVisible { DispatchQueue.main.async { revealed = true } }
        }
        .onChange(of: store.panelVisible) { _, visible in
            if visible { revealed = true }
            else {
                // Reset while hidden, without animating, so the next opening fills the faders from empty.
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { revealed = false }
            }
        }
    }

    // MARK: Header and footer

    private var headline: String {
        if settings { return store.isPaired ? t("Settings") : t("Set up") }
        if store.pairing { return t("Press the button") }
        if !store.connected { return store.connecting ? t("Connecting") : store.isPaired ? t("Offline") : t("Connect Hue") }
        let lit = store.litLights.count
        if lit == 0 { return t("All dark") }
        if lit == store.lights.count { return t("All lights on") }
        return lit == 1 ? t("1 light on") : t("%d lights on", lit)
    }

    @ViewBuilder private var subline: some View {
        if store.syncing {
            Label(t("Following your screen"), systemImage: "display")
        } else if store.connected, !settings, let scene = store.activeScene {
            Label(scene.metadata.name, systemImage: "sparkles")
        } else if !store.connected && !settings && store.isPaired {
            Label(t("Same Wi-Fi as the bridge?"), systemImage: "wifi.exclamationmark")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(headline).font(.display(22)).tracking(-0.4).lineLimit(1).minimumScaleFactor(0.7)
                subline.font(.system(size: 12)).foregroundStyle(Ink.muted).lineLimit(1)
            }
            Spacer(minLength: 6)
            if store.connected && !settings {
                Button { store.toggleAll() } label: {
                    Image(systemName: "power").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(store.anyOn ? Ink.dark : Ink.muted)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(store.anyOn ? Ink.text : .clear))
                        .overlay(Circle().strokeBorder(store.anyOn ? .clear : Ink.line, lineWidth: 1))
                        .contentShape(Circle())
                }.buttonStyle(.plain)
                    .help(store.anyOn ? t("Turn all lights off") : t("Turn all lights on"))
                    .accessibilityLabel(store.anyOn ? t("Turn all lights off") : t("Turn all lights on"))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Circle().fill(store.connected ? Color.green : store.connecting || store.pairing ? Color.orange : Ink.faint)
                .frame(width: 6, height: 6).shadow(color: store.connected ? .green.opacity(0.7) : .clear, radius: 3)
            Text(store.connected ? store.bridgeName : t(store.status)).font(.system(size: 11)).foregroundStyle(Ink.muted).lineLimit(1)
            Spacer()
            if store.syncing {
                Image(systemName: "display").font(.system(size: 11)).foregroundStyle(store.syncColor?.color ?? Ink.text).help(t("Screen sync is on"))
            }
            Button { if settings { settings = false } else { openSettings() } } label: {
                Image(systemName: settings ? "xmark" : "gearshape").font(.system(size: 13)).foregroundStyle(Ink.muted)
                    .frame(width: 26, height: 22).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .help(settings ? t("Close settings") : t("Settings"))
                .accessibilityLabel(settings ? t("Close settings") : t("Settings"))
                .disabled(settings && !store.isPaired)
        }
    }

    @ViewBuilder private var feedback: some View {
        if let error = store.error {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { store.error = nil } label: { Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(Ink.muted) }
                    .buttonStyle(.plain).help(t("Dismiss"))
            }.padding(10).background(Ink.well).clipShape(RoundedRectangle(cornerRadius: 6))
        } else if let notice = store.notice {
            Label(notice, systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var connectionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: store.isPaired ? "wifi.slash" : "link").font(.system(size: 28, weight: .light)).foregroundStyle(Ink.muted)
            Button {
                if store.connecting { store.disconnect() } else if store.isPaired { store.connect() } else { openSettings() }
            } label: {
                Label(store.connecting ? t("Cancel") : store.isPaired ? t("Reconnect") : t("Pair a bridge"),
                      systemImage: store.connecting ? "xmark" : store.isPaired ? "arrow.clockwise" : "link")
            }.buttonStyle(PrimaryButton())
        }
    }

    // MARK: Rooms: the light desk

    private var deskGroups: [HueGroup] { store.rooms + store.zones }
    private var selectedRoom: HueGroup? {
        deskGroups.first { $0.id == selectedRoomID } ?? store.rooms.first { store.isOn($0) } ?? deskGroups.first
    }

    private var roomsPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            desk
            if let room = selectedRoom { roomDetail(room) }
        }
    }

    private var desk: some View {
        let groups = deskGroups
        let count = CGFloat(max(groups.count, 1))
        let width = groups.count <= 5 ? (contentWidth - 8 * (count - 1)) / count : 60
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    Channel(name: group.name, symbol: group.symbol, on: store.isOn(group), level: store.brightness(group),
                            color: store.color(group), selected: selectedRoom?.id == group.id, index: index, revealed: revealed,
                            onToggle: { store.setGroup(group, on: !store.isOn(group)); selectedRoomID = group.id },
                            onLevel: { store.setGroup(group, brightness: $0) },
                            onSelect: { selectedRoomID = group.id })
                        .frame(width: width)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(groups.count <= 5)
        .frame(height: 262)
        .disabled(!store.connected)
    }

    private func roomDetail(_ room: HueGroup) -> some View {
        let members = store.lights(in: room)
        let lit = members.filter(\.on.on).count
        let roomScenes = store.scenes(for: room.id).sorted { store.favoriteScenes.contains($0.id) && !store.favoriteScenes.contains($1.id) }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(room.name).font(.display(17)).tracking(-0.3).lineLimit(1)
                Spacer()
                Label("\(lit)/\(members.count)", systemImage: lit > 0 ? "lightbulb.fill" : "lightbulb")
                    .font(.numeral(14)).foregroundStyle(Ink.muted)
                    .help(t("%d of %d lights on", lit, members.count)).accessibilityLabel(t("%d of %d lights on", lit, members.count))
            }
            SwatchRow(showColors: members.contains(where: \.supportsColor), showWhites: members.contains(where: \.supportsTemperature),
                      onColor: { store.setGroup(room, color: $0) }, onMirek: { store.setGroup(room, mirek: $0) })
            if !roomScenes.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) { ForEach(roomScenes) { scene in sceneChip(scene) } }
                }.scrollIndicators(.hidden)
            }
        }
        .disabled(!store.connected)
    }

    private func sceneChip(_ scene: HueScene) -> some View {
        Button { store.recall(scene) } label: {
            HStack(spacing: 7) {
                GelSwatch(colors: scene.swatches).frame(width: 22, height: 16)
                Text(scene.metadata.name).font(.system(size: 12, weight: scene.isActive ? .semibold : .regular)).lineLimit(1)
                if scene.isActive { Image(systemName: "play.fill").font(.system(size: 8)).accessibilityLabel(t("Playing")) }
            }
        }.buttonStyle(QuietButton(active: scene.isActive)).help(t("Play %@", scene.metadata.name))
    }

    // MARK: Lights

    private var lightsPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(store.rooms) { room in
                let members = store.lights(in: room)
                if !members.isEmpty { lightSection(room.name, symbol: room.symbol, members) }
            }
            if !store.unassignedLights.isEmpty { lightSection(t("No room"), symbol: "questionmark.square.dashed", store.unassignedLights) }
        }.disabled(!store.connected)
    }

    private func lightSection(_ title: String, symbol: String, _ members: [HueLight]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold)).padding(.bottom, 2)
            ForEach(members) { light in
                VStack(spacing: 6) {
                    LevelBar(name: light.metadata.name, symbol: light.symbol, detail: detail(light), on: light.on.on, level: light.brightness,
                             color: light.displayRGB, expanded: expanded.contains(light.id),
                             onToggle: { store.setLight(light.id, on: !light.on.on) },
                             onLevel: { store.setLight(light.id, brightness: $0) },
                             onExpand: { toggleExpanded(light.id) })
                    if expanded.contains(light.id) { lightControls(light) }
                }
            }
        }
    }

    private func detail(_ light: HueLight) -> String {
        guard light.on.on else { return t("Off") }
        if light.colorTemperature?.mirekValid == true, let mirek = light.colorTemperature?.mirek { return "\(ColorMath.kelvin(mirek)) K" }
        return light.supportsColor ? t("Color") : t("On")
    }

    private func lightControls(_ light: HueLight) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if light.supportsTemperature {
                let range = light.mirekRange
                let mirek = Double(light.colorTemperature?.mirek ?? 366)
                HStack(spacing: 10) {
                    Image(systemName: "thermometer.medium").font(.system(size: 12)).foregroundStyle(Ink.muted).help(t("White tone"))
                    // Warm on the left, cool on the right: the slider runs over reversed mirek.
                    GradientSlider(value: range.upperBound + range.lowerBound - mirek, range: range,
                                   colors: [ColorMath.mirekToRGB(Int(range.upperBound)).color, ColorMath.mirekToRGB(300).color, ColorMath.mirekToRGB(Int(range.lowerBound)).color]) {
                        store.setLight(light.id, mirek: Int((range.upperBound + range.lowerBound - $0).rounded()))
                    }
                    Text(verbatim: "\(ColorMath.kelvin(Int(mirek)))K").font(.numeral(13)).foregroundStyle(Ink.muted).frame(width: 42, alignment: .trailing)
                }
            }
            if light.supportsColor {
                ColorPad(current: light.colorTemperature?.mirekValid == true ? nil : light.displayRGB) { store.setLight(light.id, color: $0) }
            }
            SwatchRow(showColors: light.supportsColor, showWhites: light.supportsTemperature,
                      onColor: { store.setLight(light.id, color: $0) }, onMirek: { store.setLight(light.id, mirek: $0) })
        }
        .padding(12).background(Ink.well).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.trailing, 32)
    }

    private func toggleExpanded(_ id: String) {
        withAnimation(.easeOut(duration: 0.18)) { if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) } }
    }

    // MARK: Scenes: a gel swatch book

    private var sceneGroup: HueGroup? { store.groups.first { $0.id == sceneGroupID } ?? store.rooms.first ?? store.zones.first }

    private var scenesPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal) {
                TextTabs(items: store.groups.map(\.id), title: { id in store.groups.first { $0.id == id }?.name ?? "" },
                         selection: Binding(get: { sceneGroup?.id ?? "" }, set: { sceneGroupID = $0 }), size: 12)
            }.scrollIndicators(.hidden)
            if let group = sceneGroup {
                let list = store.scenes(for: group.id).sorted { store.favoriteScenes.contains($0.id) && !store.favoriteScenes.contains($1.id) }
                VStack(spacing: 0) {
                    ForEach(list) { scene in
                        sceneRow(scene)
                        if scene.id != list.last?.id { Rectangle().fill(Ink.line).frame(height: 1) }
                    }
                }
                if list.isEmpty {
                    Label(t("No scenes yet. Create them in the Hue app."), systemImage: "sparkles")
                        .font(.system(size: 12)).foregroundStyle(Ink.muted)
                }
            }
        }.disabled(!store.connected)
    }

    private func sceneRow(_ scene: HueScene) -> some View {
        let favorite = store.favoriteScenes.contains(scene.id)
        let lead = scene.swatches.first ?? RGB(r: 0.95, g: 0.93, b: 0.9)
        return HStack(spacing: 12) {
            Button { store.recall(scene) } label: {
                HStack(spacing: 12) {
                    GelSwatch(colors: scene.swatches).frame(width: 76, height: 42)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Ink.text, lineWidth: scene.isActive ? 2 : 0))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scene.metadata.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            .foregroundStyle(scene.isActive ? Ink.text : Ink.text.opacity(0.8))
                        if scene.isActive {
                            Label(t("Playing"), systemImage: "play.fill")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(Ink.on(lead))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(lead.color))
                        }
                    }
                    Spacer()
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help(t("Play %@", scene.metadata.name))
            Button { store.toggleFavorite(scene) } label: {
                Image(systemName: favorite ? "star.fill" : "star").font(.system(size: 12)).foregroundStyle(favorite ? Ink.text : Ink.faint)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .help(favorite ? t("Unpin from Rooms") : t("Pin to Rooms"))
                .accessibilityLabel(favorite ? t("Unpin from Rooms") : t("Pin to Rooms"))
        }
        .padding(.vertical, 8).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(scene.isActive ? Ink.raised : .clear))
        .padding(.horizontal, -8)
        .accessibilityAddTraits(scene.isActive ? .isSelected : [])
    }

    // MARK: Screen sync

    private var syncPanel: some View {
        let live = store.syncing ? store.syncColor : nil
        return VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(live?.color ?? Ink.well)
                    if live == nil {
                        Image(systemName: store.syncing ? "hourglass" : "play.slash").font(.system(size: 22, weight: .light)).foregroundStyle(Ink.faint)
                    }
                }
                .frame(height: 150)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Ink.line, lineWidth: 6))
                .animation(.easeOut(duration: 0.6), value: live)
                Rectangle().fill(Ink.line).frame(width: 40, height: 14)
                Capsule().fill(Ink.line).frame(width: 96, height: 5)
            }.frame(maxWidth: .infinity)
                .help(t("Your screen's main color is sent to the room's color lights."))
                .accessibilityHidden(true)
            VStack(spacing: 14) {
                HStack {
                    Label(t("Room"), systemImage: "square.split.2x2").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Picker(t("Room"), selection: Binding(get: { store.syncGroupID ?? "" }, set: { store.syncGroupID = $0 })) {
                        ForEach(store.groups) { group in Text(group.name).tag(group.id) }
                    }.labelsHidden().fixedSize().disabled(store.syncing)
                }
                HStack(spacing: 10) {
                    Image(systemName: "sun.max").font(.system(size: 13)).foregroundStyle(Ink.muted).frame(width: 18).help(t("Maximum brightness"))
                    Slider(value: $store.syncMaxBrightness, in: 10...100).controlSize(.small).accessibilityLabel(t("Maximum brightness"))
                    Text("\(Int(store.syncMaxBrightness))").font(.numeral(15)).foregroundStyle(Ink.muted).frame(width: 28, alignment: .trailing)
                }
                HStack {
                    Label(t("Restore lights after"), systemImage: "arrow.uturn.backward").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Toggle(t("Restore lights after"), isOn: $store.syncRestore).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                }
            }
            Button { store.syncing ? store.stopSync() : store.startSync() } label: {
                Label(store.syncing ? t("Stop sync") : t("Start sync"), systemImage: store.syncing ? "stop.fill" : "play.fill").frame(maxWidth: .infinity)
            }.buttonStyle(PrimaryButton()).disabled(!store.connected || store.syncGroupID == nil)
                .help(t("Needs Screen Recording access the first time. Only color lights take part."))
        }
    }

    // MARK: History

    private var historyPanel: some View {
        let totals = store.usage(days: usageDays)
        let top = totals.first?.seconds ?? 0
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                TextTabs(items: [1, 7, 30], title: { $0 == 1 ? t("Today") : t("%d days", $0) }, selection: $usageDays, size: 12).fixedSize()
                Spacer()
                Image(systemName: "info.circle").foregroundStyle(Ink.faint)
                    .help(t("Counts only while this Mac is awake and connected. Stays on this Mac."))
            }
            VStack(spacing: 14) {
                ForEach(totals) { item in
                    let group = store.rooms.first { $0.id == item.id }
                    let tint = group.map { store.isOn($0) ? store.color($0) : ColorMath.mirekToRGB(370) } ?? ColorMath.mirekToRGB(370)
                    VStack(spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: group?.symbol ?? "square").font(.system(size: 12)).foregroundStyle(Ink.muted).frame(width: 22, alignment: .leading)
                            Text(group?.name ?? item.name).font(.system(size: 13)).lineLimit(1)
                            Spacer()
                            Text(durationText(item.seconds)).font(.numeral(15)).foregroundStyle(Ink.muted)
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2).fill(Ink.well)
                                RoundedRectangle(cornerRadius: 2).fill(tint.color).frame(width: geometry.size.width * CGFloat(item.seconds / max(top, 1)))
                            }
                        }.frame(height: 8)
                    }
                }
            }
            if totals.isEmpty {
                Label(t("Nothing yet. Time is added every 30 seconds while lights are on."), systemImage: "clock")
                    .font(.system(size: 12)).foregroundStyle(Ink.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Settings

    private var bridgeGlyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Ink.text)
            Circle().strokeBorder(Ink.dark.opacity(0.22), lineWidth: 2).frame(width: 18, height: 18)
        }.frame(width: 40, height: 40).accessibilityHidden(true)
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            if store.pairing { pairingWait }
            else if store.isPaired { pairedBridge }
            else { findBridge }
            preferences
        }
    }

    private var pairingWait: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                bridgeGlyph
                Image(systemName: "hand.tap").font(.system(size: 22, weight: .light))
            }
            Text(t("Press the round button on top of your bridge.")).font(.display(16)).fixedSize(horizontal: false, vertical: true)
            HStack {
                ProgressView().controlSize(.small)
                Text(t("45 seconds")).font(.system(size: 12)).foregroundStyle(Ink.muted)
                Spacer()
                Button(t("Cancel")) { store.cancelPairing() }.buttonStyle(QuietButton())
            }
        }
    }

    private var findBridge: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.discovering {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(t("Looking for your Hue Bridge…")).font(.system(size: 13))
                }.frame(minHeight: 40)
            } else if store.discovered.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 20, weight: .light)).foregroundStyle(Ink.muted).frame(width: 40)
                    Text(t("No bridge found")).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button { store.discover() } label: { Label(t("Search again"), systemImage: "arrow.clockwise") }.buttonStyle(QuietButton())
                }
            } else {
                ForEach(store.discovered) { bridge in
                    HStack(spacing: 12) {
                        bridgeGlyph
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t("Hue Bridge found")).font(.system(size: 14, weight: .semibold))
                            Text(bridge.name).font(.system(size: 11)).foregroundStyle(Ink.muted).lineLimit(1)
                        }
                        Spacer()
                        Button { store.pair(host: bridge.host) } label: { Label(t("Pair"), systemImage: "link") }
                            .buttonStyle(PrimaryButton()).help(t("You'll press the button on the bridge next."))
                    }
                }
            }
            Button { withAnimation(.easeOut(duration: 0.18)) { manualAddress.toggle() } } label: {
                Label(manualAddress ? t("Hide address") : t("Enter address manually"), systemImage: manualAddress ? "chevron.up" : "keyboard")
                    .font(.system(size: 11)).foregroundStyle(Ink.muted)
            }.buttonStyle(.plain)
            if manualAddress {
                HStack(spacing: 8) {
                    TextField("192.168.1.20", text: $draftHost).textFieldStyle(.roundedBorder).onSubmit { store.pair(host: draftHost) }
                    Button { store.pair(host: draftHost) } label: { Label(t("Pair"), systemImage: "link") }
                        .buttonStyle(PrimaryButton())
                        .disabled(!HueClient.isLocalHost(draftHost.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
        }
    }

    private var pairedBridge: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                bridgeGlyph
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.bridgeName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Label(store.connected ? t("Connected") : t("Not connected"), systemImage: store.connected ? "checkmark.circle.fill" : "wifi.slash")
                        .font(.system(size: 11)).foregroundStyle(store.connected ? Color.green : Ink.muted)
                }
                Spacer()
                Button { withAnimation(.easeOut(duration: 0.18)) { showDetails.toggle() } } label: {
                    Image(systemName: "info.circle").font(.system(size: 14)).foregroundStyle(showDetails ? Ink.text : Ink.muted)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).help(t("Details")).accessibilityLabel(t("Details"))
            }
            if showDetails {
                VStack(alignment: .leading, spacing: 8) {
                    if !store.modelID.isEmpty { infoRow(t("Model"), store.modelID) }
                    if !store.swVersion.isEmpty { infoRow(t("Software"), store.swVersion) }
                    infoRow(t("Address"), store.host)
                    if let fingerprint = store.certificateFingerprint { infoRow(t("Certificate"), String(fingerprint.prefix(16)).uppercased() + "…") }
                    Button { store.forgetPairing() } label: { Label(t("Forget bridge"), systemImage: "trash") }
                        .buttonStyle(QuietButton()).padding(.top, 4)
                }.padding(12).background(Ink.well).clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var preferences: some View {
        VStack(spacing: 14) {
            HStack {
                Label(t("Language"), systemImage: "globe").font(.system(size: 12, weight: .semibold))
                Spacer()
                Picker(t("Language"), selection: $store.language) {
                    Text(t("System")).tag(AppLanguage.system)
                    Text(verbatim: "English").tag(AppLanguage.en)
                    Text(verbatim: "Türkçe").tag(AppLanguage.tr)
                }.labelsHidden().fixedSize()
            }
            HStack {
                Label(t("Open at login"), systemImage: "power").font(.system(size: 12, weight: .semibold))
                Spacer()
                Toggle(t("Open at login"), isOn: Binding(get: { store.launchAtLogin }, set: { store.launchAtLogin = $0 }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Ink.muted)
            Spacer()
            Text(value).textSelection(.enabled).lineLimit(1)
        }.font(.system(size: 12))
    }

    private func openSettings() {
        draftHost = store.host
        settings = true
        if !store.isPaired && store.discovered.isEmpty && !store.discovering { store.discover() }
    }
}
