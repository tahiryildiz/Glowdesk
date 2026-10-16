import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, tr
    var id: String { rawValue }
}

/// In-app strings. English text is the key; other languages map from it.
/// Kept in code (not .strings files) so the language switches live, without relaunching.
enum L10n {
    static var language = resolve(.system)
    /// Keys looked up but not translated; the snapshot renderer reports them.
    static var missing = Set<String>()

    static func resolve(_ choice: AppLanguage) -> String {
        switch choice {
        case .en: return "en"
        case .tr: return "tr"
        case .system: return Locale.preferredLanguages.first?.lowercased().hasPrefix("tr") == true ? "tr" : "en"
        }
    }

    static let tr: [String: String] = [
        // Tabs and headers
        "Rooms": "Odalar", "Lights": "Lambalar", "Scenes": "Sahneler", "Sync": "Senkron", "History": "Geçmiş",
        "Settings": "Ayarlar", "Set up": "Kurulum", "Press the button": "Düğmeye bas", "Connecting": "Bağlanıyor",
        "Offline": "Bağlantı yok", "Connect Hue": "Hue'yu bağla", "All dark": "Her yer karanlık",
        "All lights on": "Bütün ışıklar açık", "1 light on": "1 ışık açık", "%d lights on": "%d ışık açık",
        "Following your screen": "Ekranı izliyor", "Same Wi-Fi as the bridge?": "Köprüyle aynı Wi-Fi'da mısın?",
        "Turn all lights off": "Bütün ışıkları kapat", "Turn all lights on": "Bütün ışıkları aç",
        "Screen sync is on": "Ekran senkronu açık", "Close settings": "Ayarları kapat", "Dismiss": "Kapat",
        "Cancel": "Vazgeç", "Reconnect": "Yeniden bağlan", "Pair a bridge": "Köprü eşleştir",
        // Rooms and lights
        "%d of %d lights on": "%2$d lambadan %1$d tanesi açık", "Play %@": "%@ sahnesini çalıştır",
        "No room": "Odası olmayanlar", "Off": "Kapalı", "On": "Açık", "Color": "Renkli", "off": "kapalı",
        "White tone": "Beyaz tonu", "Color and white tone": "Renk ve beyaz tonu", "%@ color settings": "%@ renk ayarları",
        "Color picker": "Renk seçici", "Switch to this color": "Bu renge geç", "%d K white": "%d K beyaz",
        "%d percent": "yüzde %d",
        // Scenes
        "No scenes yet. Create them in the Hue app.": "Henüz sahne yok. Hue uygulamasından oluşturabilirsin.",
        "Playing": "Çalışıyor", "Pin to Rooms": "Odalar'a sabitle", "Unpin from Rooms": "Odalar'dan kaldır",
        // Sync
        "Your screen's main color is sent to the room's color lights.": "Ekrandaki baskın renk odadaki renkli lambalara gönderilir.",
        "Room": "Oda", "Maximum brightness": "En yüksek parlaklık", "Restore lights after": "Sonra ışıkları geri getir",
        "Start sync": "Senkronu başlat", "Stop sync": "Senkronu durdur",
        "Needs Screen Recording access the first time. Only color lights take part.": "İlk seferde Ekran Kaydı izni ister. Sadece renkli lambalar katılır.",
        // History
        "Today": "Bugün", "%d days": "%d gün",
        "Counts only while this Mac is awake and connected. Stays on this Mac.": "Sadece bu Mac uyanık ve bağlıyken sayılır. Bu Mac'te kalır.",
        "Nothing yet. Time is added every 30 seconds while lights are on.": "Henüz kayıt yok. Işıklar açıkken her 30 saniyede bir süre eklenir.",
        // Settings and pairing
        "Press the round button on top of your bridge.": "Köprünün üstündeki yuvarlak düğmeye bas.", "45 seconds": "45 saniye",
        "Looking for your Hue Bridge…": "Hue Bridge aranıyor…", "Hue Bridge found": "Hue Bridge bulundu",
        "No bridge found": "Köprü bulunamadı", "Search again": "Tekrar ara", "Pair": "Eşleştir",
        "Enter address manually": "Adresi elle gir", "Hide address": "Adresi gizle",
        "You'll press the button on the bridge next.": "Sonra köprünün üstündeki düğmeye basacaksın.",
        "Connected": "Bağlı", "Not connected": "Bağlı değil", "Details": "Ayrıntılar", "Name": "Ad", "Model": "Model",
        "Software": "Yazılım", "Address": "Adres", "Certificate": "Sertifika", "Forget bridge": "Köprüyü unut",
        "Language": "Dil", "System": "Sistem", "Open at login": "Mac açılınca başlat",
        // Menu bar
        "About Glowdesk": "Glowdesk Hakkında", "Buy me a coffee": "Bana bir kahve ısmarla", "Quit Glowdesk": "Glowdesk'ten Çık",
        "Lights on": "Işıklar açık", "Lights off": "Işıklar kapalı",
        "Scroll to dim or brighten your lights": "Işıkları kısmak ya da açmak için kaydır",
        "Your Philips Hue lights, in the menu bar.\nTalks to your bridge over the local network only.\nNot affiliated with Philips or Signify.":
            "Philips Hue ışıkların, menü çubuğunda.\nKöprünle yalnızca yerel ağ üzerinden konuşur.\nPhilips veya Signify ile bağlantısı yoktur.",
        // Status and errors
        "Disconnected": "Bağlantı kesildi", "Pairing needed": "Eşleştirme gerekli", "Connecting…": "Bağlanıyor…",
        "Waiting for the bridge button…": "Köprü düğmesi bekleniyor…", "Pairing failed": "Eşleştirilemedi", "Pair again": "Yeniden eşleştir",
        "A different bridge (%@) answers at %@. Choose the right bridge in Settings.": "%2$@ adresinde başka bir köprü (%1$@) var. Ayarlardan doğru köprüyü seç.",
        "Enter the bridge's local IP address, like 192.168.1.20.": "Köprünün yerel IP adresini gir, örneğin 192.168.1.20.",
        "Paired with %@.": "%@ ile eşleşildi.",
        "The bridge button wasn't pressed within 45 seconds. Try again.": "45 saniye içinde köprü düğmesine basılmadı. Tekrar dene.",
        "Pairing removed. You can also revoke this Mac's access in the Hue app.": "Eşleştirme silindi. Bu Mac'in erişimini Hue uygulamasından da kaldırabilirsin.",
        "No bridge found on the network. Enter its IP address instead.": "Ağda köprü bulunamadı. IP adresini elle girebilirsin.",
        "Screen sync needs Screen Recording access. Allow Glowdesk in System Settings > Privacy & Security > Screen & System Audio Recording, then reopen the app.":
            "Ekran senkronu için Ekran Kaydı izni gerekiyor. Sistem Ayarları > Gizlilik ve Güvenlik > Ekran ve Sistem Sesi Kaydı'ndan Glowdesk'e izin ver, sonra uygulamayı yeniden aç.",
        "%@ has no color lights.": "%@ içinde renkli lamba yok.", "Couldn't read the screen: %@": "Ekran okunamadı: %@",
        "Couldn't change Open at Login: %@": "Girişte açılma ayarlanamadı: %@",
        "The bridge no longer recognizes this Mac. Pair again in Settings.": "Köprü bu Mac'i artık tanımıyor. Ayarlardan yeniden eşleştir.",
        "Press the round button on top of the bridge.": "Köprünün üstündeki yuvarlak düğmeye bas.",
        "The bridge's certificate has changed. If you're sure it's the same bridge, forget the pairing in Settings and pair again.":
            "Köprünün sertifikası değişmiş. Aynı köprü olduğundan eminsen Ayarlar'dan köprüyü unutup yeniden eşleştir.",
        "The bridge is getting commands too fast. Slow down a little.": "Köprüye çok hızlı komut gidiyor. Biraz yavaşla.",
        "The bridge returned HTTP %d.": "Köprü HTTP %d döndürdü.",
        "Can't reach the Hue Bridge at %@. Make sure it's powered on and connected to your router.": "%@ adresindeki Hue Bridge'e ulaşılamıyor. Köprünün açık ve modeme bağlı olduğundan emin ol.",
        "The bridge sent an unexpected reply.": "Köprüden beklenmeyen bir yanıt geldi.", "The bridge refused pairing.": "Köprü eşleştirmeyi reddetti.",
        "Couldn't open the live update stream (HTTP %d).": "Canlı güncelleme akışı açılamadı (HTTP %d).",
        "No display found.": "Ekran bulunamadı.",
        "Keychain refused to save the item (%d).": "Anahtar Zinciri kaydı reddetti (%d).",
        "Keychain refused to remove the item (%d).": "Anahtar Zinciri kaydı silemedi (%d).",
        // Units
        "%d s": "%d sn", "%d min": "%d dk", "%d h %d min": "%d sa %d dk", " and ": " ve ",
    ]
}

/// Localized text for an English key.
func t(_ key: String) -> String {
    guard L10n.language == "tr" else { return key }
    if let value = L10n.tr[key] { return value }
    L10n.missing.insert(key)
    return key
}

/// Localized format string filled with arguments (`%@`, `%d`, positional `%1$d` in translations).
func t(_ key: String, _ args: CVarArg...) -> String {
    String(format: t(key), locale: Locale(identifier: L10n.language), arguments: args)
}
