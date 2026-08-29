import Symbols
import UIKit

extension UIScrollView {
    /// Her iki kenarda yumuşak kenar efekti.
    ///
    /// `.automatic` bilerek kullanılmıyor: sabit bir görünüm değil, UIKit
    /// bağlama göre çözüyor. Başlıksız navigation bar'da (anasayfa, detay)
    /// `.soft`'a düşüyor ama başlıklı bir bar'da başlığı okunur kılmak için
    /// `.hard`'a geçiyor — ayırıcı çizgili, kalın bir bulanıklık bandı çıkıyor.
    /// Uygulamanın her ekranında anasayfadaki yumuşak geçiş isteniyor, o yüzden
    /// stil açıkça sabitleniyor.
    func applyNativeScrollEdges() {
        #if os(iOS)
        topEdgeEffect.style = .soft
        bottomEdgeEffect.style = .soft
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

// MARK: - Liquid Glass butonlar

extension UIButton.Configuration {
    /// Uygulamanın cam butonu — arama çubuğundaki sistem camıyla aynı malzeme.
    ///
    /// `baseBackgroundColor` bilerek atanmıyor: cam konfigürasyonlarında bu
    /// alan camın tonu oluyor ve `nil` bırakıldığında UIKit malzemeye uygun
    /// tonsuz camı seçiyor. `.clear` vermek dolguyu tamamen kaldırıyor,
    /// `prominentGlass()` ise tonsuz bırakılınca pencerenin varsayılan mavi
    /// tint'ini alıyor; ikisi de bu koyu hero üzerinde istenmiyor.
    static func appGlass(
        horizontalInset: CGFloat = 18,
        verticalInset: CGFloat = 12,
        fontSize: CGFloat? = nil
    ) -> UIButton.Configuration {
        var config = UIButton.Configuration.glass()
        config.cornerStyle = .capsule
        config.baseForegroundColor = .white
        config.imagePadding = 8
        config.contentInsets = .init(
            top: verticalInset, leading: horizontalInset,
            bottom: verticalInset, trailing: horizontalInset
        )
        if let fontSize {
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: fontSize, weight: .semibold)
                return outgoing
            }
        }
        return config
    }
}

#if os(tvOS)
/// tvOS odak geri bildirimi.
///
/// tvOS'ta dokunma yok: kullanıcı kumandayla odağı gezdiriyor ve hangi öğenin
/// seçili olduğunu yalnızca odak efektinden anlıyor. Efekt tek yerde tanımlı
/// ki bütün ekranlarda aynı his olsun.
extension UIView {
    /// Odak gölgesini bir kez kuruyor. Görünürlüğü `updateFocusAppearance`
    /// yönetiyor; burada yalnızca değişmeyen ayarlar var.
    /// Odaktaki kartın kenarlık kalınlığı.
    ///
    /// Kart odakta büyüdüğü için kenarlık da onunla birlikte kalınlaşıyor;
    /// ekranda 1pt görünmesi için değer ölçeğe bölünüyor.
    static let focusedBorderWidth: CGFloat = 0.5

    func prepareFocusShadow() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 12)
        layer.shadowRadius = 18
        layer.shadowOpacity = 0
    }

    /// Odaklanan öğe hafifçe büyüyüp yükseliyor.
    ///
    /// Sistemin odak geçişi çok kısa; ona bırakıldığında kart bir anda
    /// zıplıyordu. Değişim koordinatörün içinde ama kendi yay eğrisiyle
    /// çalışıyor, böylece hem sistemle aynı anda başlıyor hem yumuşak bitiyor.
    func updateFocusAppearance(
        isFocused: Bool,
        using coordinator: UIFocusAnimationCoordinator,
        scale: CGFloat = 1.08,
        additionalChanges: (() -> Void)? = nil
    ) {
        coordinator.addCoordinatedAnimations {
            UIView.animate(
                withDuration: 0.38,
                delay: 0,
                usingSpringWithDamping: 0.74,
                initialSpringVelocity: 0.2,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.transform = isFocused ? CGAffineTransform(scaleX: scale, y: scale) : .identity
                self.layer.shadowOpacity = isFocused ? 0.55 : 0
                additionalChanges?()
            }
        }
    }
}
#endif

#if os(tvOS)
extension UICollectionView {
    /// Odaklanan hücre kendi çerçevesinin dışına büyüyor. Hücre ile koleksiyon
    /// arasındaki katmanlar kırpma yaparsa efektin üstü kesiliyor ve kart
    /// büyümüyormuş gibi görünüyor. Ortogonal (yatay) bölümlerde araya
    /// UIKit'in kendi kaydırma görünümü giriyor, o yüzden zincir yürünüyor.
    func unclipFocusGrowth(around cell: UICollectionViewCell) {
        clipsToBounds = false
        var ancestor = cell.superview
        while let view = ancestor, view !== self {
            view.clipsToBounds = false
            ancestor = view.superview
        }
    }
}
#endif

/// Dokunulabilir satır/kart sarmalayıcısı.
///
/// tvOS'ta odaklanabiliyor ve odak geri bildirimi veriyor; iOS'ta düz bir
/// `UIControl`'den farkı yok.
final class FocusableControl: UIControl {
    #if os(tvOS)
    override var canBecomeFocused: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        prepareFocusShadow()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        updateFocusAppearance(isFocused: isFocused, using: coordinator, scale: 1.04)
    }

    /// `UIButton` seçildiğinde `.primaryActionTriggered` gönderiyor ama özel
    /// `UIControl` alt sınıfları göndermiyor; kumandanın seçim tuşu burada
    /// elle eyleme çevriliyor.
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .select }) {
            sendActions(for: .primaryActionTriggered)
            return
        }
        super.pressesEnded(presses, with: event)
    }
    #endif
}

extension UINavigationItem {
    /// Büyük başlık tvOS'ta yok (`largeTitleDisplayMode` orada kullanılamıyor);
    /// çağrı sessizce yutuluyor. Çağıran taraf her yerde `#if` yazmasın diye.
    func setPrefersLargeTitle(_ prefersLarge: Bool) {
        #if os(iOS)
        largeTitleDisplayMode = prefersLarge ? .always : .never
        #endif
    }
}

/// Dokunsal geri bildirim. tvOS'ta titreşim donanımı yok, orada sessizce
/// atlanıyor; çağıran taraf her yerde `#if` yazmak zorunda kalmıyor.
enum Haptics {
    enum Strength {
        case light
        case medium
    }

    @MainActor
    static func impact(_ strength: Strength) {
        #if os(iOS)
        let style: UIImpactFeedbackGenerator.FeedbackStyle = strength == .light ? .light : .medium
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
}

extension UIView {
    /// Yan yana duran cam butonları tek bir cam yüzeyde toplar; öğeler
    /// birbirine yaklaştıkça Apple'ın birleşme/ayrılma geçişi devreye giriyor.
    ///
    /// `UIGlassContainerEffect` yalnızca iOS'ta var. tvOS'ta içerik
    /// sarmalanmadan olduğu gibi dönüyor: butonlar yine cam, yalnızca
    /// birleşme animasyonu olmuyor.
    static func glassContainer(wrapping content: UIView, spacing: CGFloat) -> UIView {
        #if os(iOS)
        let effect = UIGlassContainerEffect()
        effect.spacing = spacing
        let container = UIVisualEffectView(effect: effect)
        container.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        container.contentView.addSubview(content)
        // Kısıtlar `contentView`'e değil efekt görünümüne bağlanıyor:
        // `contentView` autoresizing ile boyutlandığı için ona pinlemek
        // boyutu yukarı taşımıyor ve kapsayıcı sıfıra çöküyor.
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        return container
        #else
        return content
        #endif
    }
}

extension UIButton {
    /// Sembolü varsayılan `replace` geçişiyle değiştirir.
    func setSymbol(_ systemName: String, animated: Bool = true) {
        setSymbol(systemName, transition: .replace.offUp, animated: animated)
    }

    /// Konfigürasyonlu butonlarda sembolü Apple'ın kendi geçiş animasyonuyla
    /// değiştirir. Konfigürasyonu doğrudan güncellemek `imageView`'e resmi
    /// anında yazdığı ve animasyonu kestiği için konfigürasyon ancak geçiş
    /// tamamlandığında eşitleniyor.
    func setSymbol(
        _ systemName: String,
        transition: some ContentTransitionSymbolEffect & SymbolEffect,
        animated: Bool = true
    ) {
        guard let image = UIImage(systemName: systemName) else { return }
        guard animated, let imageView, imageView.image != nil, window != nil else {
            configuration?.image = image
            return
        }
        imageView.setSymbolImage(image, contentTransition: transition) { [weak self] _ in
            self?.configuration?.image = image
        }
    }

    /// Basılırken hafifçe küçülüp bırakınca yaylanan dokunma geri bildirimi.
    ///
    /// tvOS'ta dokunma olayları yok — orada geri bildirimi sistemin kendi odak
    /// efekti veriyor, bu yüzden hiçbir şey bağlanmıyor.
    func addSpringPressFeedback(scale: CGFloat = 0.94) {
        #if os(iOS)
        addAction(
            UIAction { [weak self] _ in self?.animatePress(to: scale) },
            for: [.touchDown, .touchDragEnter]
        )
        addAction(
            UIAction { [weak self] _ in self?.animatePress(to: 1) },
            for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
        )
        #endif
    }

    private func animatePress(to scale: CGFloat) {
        UIView.animate(
            withDuration: scale < 1 ? 0.18 : 0.42,
            delay: 0,
            usingSpringWithDamping: scale < 1 ? 1 : 0.58,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.transform = scale == 1 ? .identity : CGAffineTransform(scaleX: scale, y: scale)
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
    var titleFont: UIFont
    var rowTitleFont: UIFont
    var cardTitleFont: UIFont
    /// Liste satırlarındaki başlık ve alt satır (katalog, favoriler, arama).
    var listTitleFont: UIFont
    var listSubtitleFont: UIFont
    /// Anasayfadaki "Canlı / Film / Dizi" kartları.
    var mainCardTitleFont: UIFont
    var mainCardCountFont: UIFont
    /// Afiş kartlarının köşe yarıçapı.
    var cardCornerRadius: CGFloat
    /// Ray başlığı ile kartlar arasındaki boşluk ve başlık yüksekliği.
    var rowHeaderGap: CGFloat
    var rowHeaderHeight: CGFloat
    /// Bölüm/fragman kartının genişliği ve altındaki metin bloğunun yüksekliği.
    var clipCardWidth: CGFloat
    var clipCardTextHeight: CGFloat
    /// Oyuncu dairesinin çapı.
    var castPhotoWidth: CGFloat
    /// Detay ekranındaki bölümler (bölümler, oyuncular, künye) arası boşluk.
    var detailSectionSpacing: CGFloat
    /// Kart üzerindeki bilgi katmanının iç boşluğu ve yazı ölçüsü.
    var cardOverlayPadding: CGFloat
    var cardOverlayFontSize: CGFloat
    var cornerRadius: CGFloat

    static let tv = AppMetrics(
        posterWidth: 240,
        rowSpacing: 84,
        cardSpacing: 32,
        screenPadding: 60,
        heroHeight: 720,
        heroImageWidth: 1920,
        mainCardWidth: 380,
        // tvOS'ta afiş kendi başına yeterli; başlık/alt satır kalabalık yapıyor.
        titleFont: .systemFont(ofSize: 56, weight: .bold),
        rowTitleFont: .systemFont(ofSize: 26, weight: .semibold),
        cardTitleFont: .systemFont(ofSize: 22, weight: .medium),
        listTitleFont: .systemFont(ofSize: 30),
        listSubtitleFont: .systemFont(ofSize: 26),
        mainCardTitleFont: .systemFont(ofSize: 34, weight: .semibold),
        mainCardCountFont: .systemFont(ofSize: 22),
        cardCornerRadius: 20,
        // 10 feet mesafede başlık kartlara yapışık durmamalı.
        rowHeaderGap: 28,
        rowHeaderHeight: 44,
        clipCardWidth: 420,
        // Metin görselin üstünde; kartın altında ayrı bir blok yok.
        clipCardTextHeight: 0,
        castPhotoWidth: 240,
        detailSectionSpacing: 64,
        cardOverlayPadding: 20,
        cardOverlayFontSize: 17,
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
        titleFont: .systemFont(ofSize: 34, weight: .bold),
        rowTitleFont: .systemFont(ofSize: 18, weight: .semibold),
        cardTitleFont: .systemFont(ofSize: 15, weight: .medium),
        listTitleFont: .systemFont(ofSize: 17),
        listSubtitleFont: .systemFont(ofSize: 15),
        mainCardTitleFont: .systemFont(ofSize: 22, weight: .semibold),
        mainCardCountFont: .systemFont(ofSize: 14),
        cardCornerRadius: 8,
        rowHeaderGap: 12,
        rowHeaderHeight: 28,
        clipCardWidth: 260,
        clipCardTextHeight: 0,
        castPhotoWidth: 124,
        detailSectionSpacing: 40,
        cardOverlayPadding: 12,
        cardOverlayFontSize: 12,
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
        titleFont: .systemFont(ofSize: 28, weight: .bold),
        rowTitleFont: .systemFont(ofSize: 16, weight: .semibold),
        cardTitleFont: .systemFont(ofSize: 13, weight: .medium),
        listTitleFont: .systemFont(ofSize: 17),
        listSubtitleFont: .systemFont(ofSize: 15),
        mainCardTitleFont: .systemFont(ofSize: 22, weight: .semibold),
        mainCardCountFont: .systemFont(ofSize: 14),
        cardCornerRadius: 8,
        rowHeaderGap: 12,
        rowHeaderHeight: 28,
        clipCardWidth: 210,
        clipCardTextHeight: 0,
        castPhotoWidth: 100,
        detailSectionSpacing: 36,
        cardOverlayPadding: 10,
        cardOverlayFontSize: 11,
        cornerRadius: 8
    )

    /// Görünümün kendi genişliğine göre doğru ölçü setini seçer.
    ///
    /// iOS/iPadOS'ta ana kategori kartlarının genişliği sabit değil, ekrandan
    /// hesaplanıyor: üçü birden ekrana sığmalı, kaydırmaya gerek kalmamalı.
    static func metrics(for width: CGFloat) -> AppMetrics {
        #if os(tvOS)
        var metrics = AppMetrics.tv
        #else
        var metrics = width < 500 ? AppMetrics.compact : .regular
        #endif

        // Ana kategori kartlarının genişliği sabit değil, ekrandan
        // hesaplanıyor: üçü birden yan yana sığmalı, kaydırmaya gerek kalmamalı.
        guard width > 0 else { return metrics }
        let cardCount = CGFloat(MediaKind.allCases.count)
        let gaps = metrics.cardSpacing * (cardCount - 1)
        let available = width - metrics.screenPadding * 2 - gaps
        metrics.mainCardWidth = max(available / cardCount, 1)
        return metrics
    }

    func cardWidth(for kind: MediaKind) -> CGFloat {
        kind == .live ? posterWidth * 1.35 : posterWidth
    }

    func cardHeight(for kind: MediaKind) -> CGFloat {
        cardWidth(for: kind) / kind.posterAspect
    }

    /// Rayda bir kartın kapladığı toplam yükseklik.
    ///
    /// Başlık artık afişin üstündeki şeritte; kartın altında yer tutan bir
    /// etiket yok, dolayısıyla ray yüksekliği afişin kendisi kadar.
    func rowItemHeight(for kind: MediaKind) -> CGFloat {
        cardHeight(for: kind)
    }
}
