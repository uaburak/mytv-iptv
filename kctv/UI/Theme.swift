import UIKit

extension UIScrollView {
    /// Kenar efektinde ekstra bir şey yapmıyoruz: üstte durum çubuğu
    /// hizasında sistemin kendi davranışı kalıyor, altta efekt kapalı.
    func applyNativeScrollEdges() {
        #if os(iOS)
        topEdgeEffect.style = .automatic
        bottomEdgeEffect.isHidden = true
        #endif
    }
}

/// Uygulamanın renk paleti. Apple TV uygulaması gibi tamamen koyu.
enum AppPalette {
    static let background = UIColor.black
    static let elevated = UIColor.white.withAlphaComponent(0.08)
    static let separator = UIColor.white.withAlphaComponent(0.12)
    static let primaryText = UIColor.white
    static let secondaryText = UIColor.white.withAlphaComponent(0.62)
    static let accent = UIColor(red: 0.16, green: 0.62, blue: 1.0, alpha: 1.0)

    static func mainCardColors(for kind: MediaKind) -> [UIColor] {
        switch kind {
        case .live:
            [UIColor(red: 0.85, green: 0.16, blue: 0.28, alpha: 1), UIColor(red: 0.45, green: 0.05, blue: 0.22, alpha: 1)]
        case .movie:
            [UIColor(red: 0.13, green: 0.42, blue: 0.86, alpha: 1), UIColor(red: 0.05, green: 0.16, blue: 0.42, alpha: 1)]
        case .series:
            [UIColor(red: 0.44, green: 0.20, blue: 0.78, alpha: 1), UIColor(red: 0.16, green: 0.06, blue: 0.35, alpha: 1)]
        }
    }
}

/// Ölçüler platforma ve ekran genişliğine göre değişiyor: tvOS'ta 10 feet
/// mesafe için her şey büyük, iPhone'da kompakt.
struct AppMetrics {
    var posterWidth: CGFloat
    var rowSpacing: CGFloat
    var cardSpacing: CGFloat
    var screenPadding: CGFloat
    var heroHeight: CGFloat
    var heroImageWidth: CGFloat
    var mainCardWidth: CGFloat
    /// Kart altındaki başlık/alt satır. Telefonda afişler kendi başına yeterli,
    /// etiketler kalabalık yapıyor; iPad ve tvOS'ta gösteriliyor.
    var showsCardLabels: Bool
    var titleFont: UIFont
    var rowTitleFont: UIFont
    var cardTitleFont: UIFont
    var cornerRadius: CGFloat

    static let tv = AppMetrics(
        posterWidth: 240,
        rowSpacing: 56,
        cardSpacing: 32,
        screenPadding: 60,
        heroHeight: 720,
        heroImageWidth: 1920,
        mainCardWidth: 380,
        showsCardLabels: true,
        titleFont: .systemFont(ofSize: 56, weight: .bold),
        rowTitleFont: .systemFont(ofSize: 26, weight: .semibold),
        cardTitleFont: .systemFont(ofSize: 22, weight: .medium),
        cornerRadius: 12
    )

    static let regular = AppMetrics(
        posterWidth: 152,
        rowSpacing: 34,
        cardSpacing: 16,
        screenPadding: 28,
        heroHeight: 560,
        heroImageWidth: 1100,
        mainCardWidth: 260,
        showsCardLabels: true,
        titleFont: .systemFont(ofSize: 34, weight: .bold),
        rowTitleFont: .systemFont(ofSize: 18, weight: .semibold),
        cardTitleFont: .systemFont(ofSize: 15, weight: .medium),
        cornerRadius: 10
    )

    static let compact = AppMetrics(
        posterWidth: 108,
        rowSpacing: 26,
        cardSpacing: 12,
        screenPadding: 16,
        heroHeight: 480,
        heroImageWidth: 520,
        mainCardWidth: 190,
        showsCardLabels: false,
        titleFont: .systemFont(ofSize: 28, weight: .bold),
        rowTitleFont: .systemFont(ofSize: 16, weight: .semibold),
        cardTitleFont: .systemFont(ofSize: 13, weight: .medium),
        cornerRadius: 8
    )

    /// Görünümün kendi genişliğine göre doğru ölçü setini seçer.
    static func metrics(for width: CGFloat) -> AppMetrics {
        #if os(tvOS)
        return .tv
        #else
        return width < 500 ? .compact : .regular
        #endif
    }

    func cardWidth(for kind: MediaKind) -> CGFloat {
        kind == .live ? posterWidth * 1.35 : posterWidth
    }

    func cardHeight(for kind: MediaKind) -> CGFloat {
        cardWidth(for: kind) / kind.posterAspect
    }

    /// Rayda bir kartın kapladığı toplam yükseklik.
    func rowItemHeight(for kind: MediaKind) -> CGFloat {
        cardHeight(for: kind) + (showsCardLabels ? 46 : 0)
    }
}
