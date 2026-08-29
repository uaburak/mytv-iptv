import Foundation

/// Kullanıcının içerik tercihleri.
///
/// Katalog sağlayıcıdan geldiği gibi tutuluyor; süzgeç yalnızca *türetilen*
/// listeleri (anasayfa rayları, gezinme, arama) etkiliyor. Böylece tercih
/// değiştiğinde yeniden indirme gerekmiyor.
enum AppSettings {
    private static let hidesAdultKey = "kctv.hidesAdultContent"

    /// Varsayılan **açık**: sağlayıcı listeleri yetişkin kategorileri ayırt
    /// etmeden gönderiyor ve bunların çocuk erişimine açık bir ekranda
    /// kendiliğinden görünmesi kabul edilebilir değil.
    static var hidesAdultContent: Bool {
        get {
            guard UserDefaults.standard.object(forKey: hidesAdultKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: hidesAdultKey)
        }
        // Değişimi ayarlar ekranı `ContentLibrary.applyContentFilter()` ile
        // uyguluyor; katalog yeniden indirilmiyor, yalnızca türetiliyor.
        set { UserDefaults.standard.set(newValue, forKey: hidesAdultKey) }
    }
}

/// Yetişkin içerik tespiti.
///
/// Sağlayıcılar içerik derecelendirmesi göndermiyor; tek ipucu ad ve kategori
/// metni ("XXX", "ADULT 18+", "EROTİK"). Bu yüzden eşleşme kelime bazında
/// yapılıyor: kelimenin ortasında aramak "MAXXX" gibi adları yanlışlıkla
/// yakalıyordu.
///
/// Kategori sinyali addan çok daha güvenilir — IPTV listelerinde yetişkin
/// içerik neredeyse her zaman kendi kategorisinde toplanıyor — bu yüzden
/// `ContentLibrary` önce kategoriyi işaretliyor, ada yalnızca ikincil olarak
/// bakıyor.
enum AdultContentFilter {
    private static let markers: Set<String> = [
        "xxx", "adult", "adults", "porn", "porno", "pornstar",
        "erotik", "erotic", "hardcore", "18+", "+18",
    ]

    static func looksAdult(_ text: String) -> Bool {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        // Harf ve rakam dışındaki her şey ayırıcı: "🔞 TR | ADULT-18+" →
        // ["tr", "adult", "18+"]. "+" korunuyor, "18+"/"+18" tek işaret.
        var words: [String] = []
        var current = ""
        for character in folded {
            if character.isLetter || character.isNumber || character == "+" {
                current.append(character)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }

        return words.contains { markers.contains($0) }
    }
}
