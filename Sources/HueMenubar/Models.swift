import Foundation

// Philips Hue CLIP v2 resources. Only the fields this app reads are modeled; the
// decoder uses convertFromSnakeCase, so `color_temperature` becomes `colorTemperature`.

struct ResourceRef: Codable, Hashable { let rid: String; let rtype: String }
struct XY: Codable, Hashable { var x: Double; var y: Double }

struct HueLight: Codable, Identifiable, Hashable {
    let id: String
    let owner: ResourceRef
    var metadata: Metadata
    var on: OnState
    var dimming: Dimming?
    var colorTemperature: ColorTemperature?
    var color: LightColor?
    struct Metadata: Codable, Hashable { var name: String; var archetype: String? }
    struct OnState: Codable, Hashable { var on: Bool }
    struct Dimming: Codable, Hashable { var brightness: Double; var minDimLevel: Double? }
    struct ColorTemperature: Codable, Hashable {
        var mirek: Int?
        var mirekValid: Bool?
        var mirekSchema: Schema?
        struct Schema: Codable, Hashable { let mirekMinimum: Int; let mirekMaximum: Int }
    }
    struct LightColor: Codable, Hashable { var xy: XY; var gamutType: String? }

    var supportsColor: Bool { color != nil }
    var supportsTemperature: Bool { colorTemperature?.mirekSchema != nil }
    var brightness: Double { dimming?.brightness ?? 100 }
    var mirekRange: ClosedRange<Double> {
        let schema = colorTemperature?.mirekSchema
        return Double(schema?.mirekMinimum ?? 153)...Double(schema?.mirekMaximum ?? 500)
    }
    /// The color the bulb is showing right now, for drawing in the panel.
    var displayRGB: RGB {
        if let ct = colorTemperature, ct.mirekValid == true, let mirek = ct.mirek { return ColorMath.mirekToRGB(mirek) }
        if let xy = color?.xy { return ColorMath.xyToRGB(xy) }
        return ColorMath.mirekToRGB(366)
    }
    var symbol: String { HueIcons.light(metadata.archetype) }
}

struct HueGroup: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    var children: [ResourceRef]
    var services: [ResourceRef]
    var metadata: Metadata?
    struct Metadata: Codable, Hashable { var name: String; var archetype: String? }
    var name: String { metadata?.name ?? "Home" }
    var groupedLightID: String? { services.first { $0.rtype == "grouped_light" }?.rid }
    var symbol: String { HueIcons.room(metadata?.archetype) }
}

struct HueGroupedLight: Codable, Identifiable, Hashable {
    let id: String
    let owner: ResourceRef
    var on: HueLight.OnState?
    var dimming: HueLight.Dimming?
}

struct HueDevice: Codable, Identifiable, Hashable {
    let id: String
    var services: [ResourceRef]
    var metadata: HueGroup.Metadata?
}

struct HueScene: Codable, Identifiable, Hashable {
    let id: String
    var metadata: Metadata
    let group: ResourceRef
    var actions: [SceneAction]
    var palette: Palette?
    var status: Status?
    struct Metadata: Codable, Hashable { var name: String }
    struct Status: Codable, Hashable { var active: String? }
    struct SceneAction: Codable, Hashable {
        let target: ResourceRef
        let action: Action
        struct Action: Codable, Hashable {
            var on: HueLight.OnState?
            var dimming: HueLight.Dimming?
            var color: Color?
            var colorTemperature: Mirek?
            struct Color: Codable, Hashable { var xy: XY }
            struct Mirek: Codable, Hashable { var mirek: Int? }
        }
    }
    struct Palette: Codable, Hashable {
        var color: [Entry]?
        var colorTemperature: [TempEntry]?
        struct Entry: Codable, Hashable { var color: SceneAction.Action.Color }
        struct TempEntry: Codable, Hashable { var colorTemperature: SceneAction.Action.Mirek }
    }
    var isActive: Bool { (status?.active ?? "inactive") != "inactive" }
    /// Up to four colors that describe the scene, used for its tile gradient.
    var swatches: [RGB] {
        var result = (palette?.color ?? []).map { ColorMath.xyToRGB($0.color.xy) }
        result += (palette?.colorTemperature ?? []).compactMap { $0.colorTemperature.mirek.map(ColorMath.mirekToRGB) }
        if result.isEmpty {
            for action in actions where action.action.on?.on != false {
                if let xy = action.action.color?.xy { result.append(ColorMath.xyToRGB(xy)) }
                else if let mirek = action.action.colorTemperature?.mirek { result.append(ColorMath.mirekToRGB(mirek)) }
            }
        }
        var unique: [RGB] = []
        for color in result where !unique.contains(where: { $0.distance(to: color) < 0.08 }) { unique.append(color) }
        return Array(unique.prefix(4))
    }
}

struct HueBridgeResource: Codable { let id: String; let bridgeId: String }

struct BridgeConfig: Codable {
    let name: String
    let bridgeid: String
    let modelid: String
    let apiversion: String?
    let swversion: String?
}

struct HueEnvelope<T: Decodable>: Decodable {
    let errors: [APIError]
    let data: [T]
    struct APIError: Decodable { let description: String }
}

enum HueError: LocalizedError {
    case message(String)
    case unauthorized
    case linkButtonNotPressed
    case certificateChanged
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .unauthorized: return t("The bridge no longer recognizes this Mac. Pair again in Settings.")
        case .linkButtonNotPressed: return t("Press the round button on top of the bridge.")
        case .certificateChanged: return t("The bridge's certificate has changed. If you're sure it's the same bridge, forget the pairing in Settings and pair again.")
        }
    }
}
