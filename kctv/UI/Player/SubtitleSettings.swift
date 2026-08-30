import KSPlayer
import SwiftUI
import UIKit

/// Altyazının görünümü ve zamanlaması.
///
/// Tercih oynatıcıyla birlikte doğmuyor, cihazda kalıyor: kullanıcı yazıyı bir
/// kez büyüttüğünde bir sonraki bölümde yeniden büyütmek zorunda kalmıyor.
///
/// Değerler iki yerde okunuyor. `SubtitleOverlayView` çizimi buradan yapıyor;
/// KSPlayer ise altyazı metnine yazı tipini **kendi** statik alanlarından
/// (`SubtitleModel.textFont`) karakter özniteliği olarak yazıyor ve öznitelik
/// etiketin puntosunu eziyor. Bu yüzden her değişimde `apply()` çağrılıp
/// kütüphanenin statikleri de eşitleniyor.
enum SubtitleSettings {
    // MARK: - Değerler

    enum TextSize: String, CaseIterable, Sendable {
        case small
        case medium
        case large
        case extraLarge

        var title: String {
            switch self {
            case .small: L10n.subtitleSizeSmall
            case .medium: L10n.subtitleSizeMedium
            case .large: L10n.subtitleSizeLarge
            case .extraLarge: L10n.subtitleSizeExtraLarge
            }
        }

        /// Aynı punto tvOS'ta ve telefonda aynı okunabilirliği vermiyor:
        /// biri kanepeden, diğeri avuç içinden okunuyor.
        var pointSize: CGFloat {
            #if os(tvOS)
            switch self {
            case .small: return 38
            case .medium: return 48
            case .large: return 58
            case .extraLarge: return 70
            }
            #else
            let isPad = UIDevice.current.userInterfaceIdiom == .pad
            switch self {
            case .small: return isPad ? 20 : 15
            case .medium: return isPad ? 26 : 19
            case .large: return isPad ? 32 : 24
            case .extraLarge: return isPad ? 40 : 30
            }
            #endif
        }
    }

    enum TextColor: String, CaseIterable, Sendable {
        case white
        case yellow
        case green
        case cyan

        var title: String {
            switch self {
            case .white: L10n.colorWhite
            case .yellow: L10n.colorYellow
            case .green: L10n.colorGreen
            case .cyan: L10n.colorCyan
            }
        }

        var color: UIColor {
            switch self {
            case .white: .white
            case .yellow: UIColor(red: 1.0, green: 0.85, blue: 0.24, alpha: 1)
            case .green: UIColor(red: 0.48, green: 0.94, blue: 0.55, alpha: 1)
            case .cyan: UIColor(red: 0.42, green: 0.90, blue: 0.98, alpha: 1)
            }
        }
    }

    /// Altyazının arkasındaki şerit.
    ///
    /// `clear` şerit koymuyor; okunabilirliği yazının gölgesi taşıyor. Parlak
    /// sahnelerde bu yetmediği için iki koyu kademe de var.
    enum Background: String, CaseIterable, Sendable {
        /// Şeritsiz. `none` yerine `clear`: `.none` adlı bir case, optional
        /// bağlamlarda `Optional.none` ile karışıyor.
        case clear
        case dim
        case solid

        var title: String {
            switch self {
            case .clear: L10n.subtitleBackgroundNone
            case .dim: L10n.subtitleBackgroundDim
            case .solid: L10n.subtitleBackgroundSolid
            }
        }

        var color: UIColor {
            switch self {
            case .clear: .clear
            case .dim: UIColor.black.withAlphaComponent(0.45)
            case .solid: UIColor.black.withAlphaComponent(0.82)
            }
        }
    }

    /// Menüde sunulan gecikme kademeleri. Serbest bir alan yerine hazır
    /// değerler var: kumandayla ± tuşlamak yerine tek seçimle gidiliyor.
    static let delayOptions: [TimeInterval] = stride(from: -3.0, through: 3.0, by: 0.5).map { $0 }

    // MARK: - Saklama

    private static let sizeKey = "kctv.subtitle.textSize"
    private static let colorKey = "kctv.subtitle.textColor"
    private static let backgroundKey = "kctv.subtitle.background"
    private static let boldKey = "kctv.subtitle.bold"
    private static let delayKey = "kctv.subtitle.delay"
    private static let autoEnableKey = "kctv.subtitle.autoEnable"

    static var textSize: TextSize {
        get { read(sizeKey, default: .medium) }
        set { write(newValue.rawValue, sizeKey) }
    }

    static var textColor: TextColor {
        get { read(colorKey, default: .white) }
        set { write(newValue.rawValue, colorKey) }
    }

    static var background: Background {
        get { read(backgroundKey, default: .clear) }
        set { write(newValue.rawValue, backgroundKey) }
    }

    static var isBold: Bool {
        get { UserDefaults.standard.object(forKey: boldKey) as? Bool ?? true }
        set { write(newValue, boldKey) }
    }

    /// Altyazının video karesine göre kaydırılması. Artı değer altyazıyı
    /// geciktiriyor.
    static var delay: TimeInterval {
        get { UserDefaults.standard.double(forKey: delayKey) }
        set { write(newValue, delayKey) }
    }

    /// Yayında gömülü altyazı varsa kendiliğinden açılsın mı.
    ///
    /// Varsayılan **açık**: bu uygulamada altyazılı içerik çoğunlukla yabancı
    /// dilde ve kullanıcı her bölümde menüye girmek zorunda kalmamalı.
    static var autoEnable: Bool {
        get { UserDefaults.standard.object(forKey: autoEnableKey) as? Bool ?? true }
        set { write(newValue, autoEnableKey) }
    }

    // MARK: - Uygulama

    static var font: UIFont {
        let size = textSize.pointSize
        return isBold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
    }

    /// Ayarları KSPlayer'ın statiklerine yazar. Kütüphane altyazı metnini
    /// buradan biçimlendirdiği için, ekrandaki etiketi ayarlamak tek başına
    /// yetmiyor.
    static func applyToPlayer() {
        SubtitleModel.textFontSize = textSize.pointSize
        SubtitleModel.textBold = isBold
        SubtitleModel.textColor = Color(uiColor: textColor.color)
        // Şeridi bizim katmanımız çiziyor; kütüphaneninki devre dışı kalıyor.
        SubtitleModel.textBackgroundColor = .clear
    }

    private static func read<T: RawRepresentable>(_ key: String, default fallback: T) -> T
        where T.RawValue == String
    {
        UserDefaults.standard.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }

    private static func write(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
