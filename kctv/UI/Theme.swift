import AudioToolbox
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

    /// Hazır arama kartlarının zemin renkleri.
    ///
    /// Bu kartlarda afiş yok — kimliği renk veriyor. Her geçiş açık tondan koyu
    /// tona iniyor: kartın alt ucu koyulaştığı için başlık bulanık bir şeride
    /// gerek kalmadan okunuyor. Paletin bir bölümü tek rengin açık/koyu
    /// tonundan, bir bölümü iki ayrı renkten oluşuyor; deste tekdüze görünmesin
    /// diye ikisi dönüşümlü sıralanıyor.
    ///
    /// Renk kartın destedeki sırasından seçiliyor, adından değil: yan yana
    /// duran iki kart hiçbir zaman aynı renge düşmüyor.
    static func suggestionGradient(at index: Int) -> [UIColor] {
        let palette: [(UIColor, UIColor)] = [
            // kırmızı → koyu bordo
            (UIColor(red: 0.96, green: 0.42, blue: 0.38, alpha: 1), UIColor(red: 0.34, green: 0.04, blue: 0.10, alpha: 1)),
            // turuncu → mor
            (UIColor(red: 0.99, green: 0.68, blue: 0.30, alpha: 1), UIColor(red: 0.26, green: 0.07, blue: 0.42, alpha: 1)),
            // açık mavi → gece mavisi
            (UIColor(red: 0.44, green: 0.72, blue: 0.99, alpha: 1), UIColor(red: 0.04, green: 0.10, blue: 0.36, alpha: 1)),
            // pembe → mor
            (UIColor(red: 0.99, green: 0.52, blue: 0.74, alpha: 1), UIColor(red: 0.24, green: 0.05, blue: 0.36, alpha: 1)),
            // nane yeşili → koyu çam
            (UIColor(red: 0.52, green: 0.90, blue: 0.62, alpha: 1), UIColor(red: 0.02, green: 0.20, blue: 0.14, alpha: 1)),
            // sarı → kiremit kırmızısı
            (UIColor(red: 0.99, green: 0.84, blue: 0.40, alpha: 1), UIColor(red: 0.40, green: 0.08, blue: 0.06, alpha: 1)),
            // lila → koyu mor
            (UIColor(red: 0.76, green: 0.66, blue: 0.99, alpha: 1), UIColor(red: 0.14, green: 0.06, blue: 0.32, alpha: 1)),
            // turkuaz → lacivert
            (UIColor(red: 0.42, green: 0.88, blue: 0.86, alpha: 1), UIColor(red: 0.04, green: 0.12, blue: 0.34, alpha: 1)),
            // şeftali → koyu kahve
            (UIColor(red: 0.99, green: 0.72, blue: 0.58, alpha: 1), UIColor(red: 0.28, green: 0.12, blue: 0.06, alpha: 1)),
            // gök mavisi → koyu petrol
            (UIColor(red: 0.60, green: 0.84, blue: 0.96, alpha: 1), UIColor(red: 0.02, green: 0.18, blue: 0.26, alpha: 1)),
            // mercan → menekşe
            (UIColor(red: 0.99, green: 0.56, blue: 0.48, alpha: 1), UIColor(red: 0.20, green: 0.06, blue: 0.34, alpha: 1)),
            // fıstık yeşili → koyu turkuaz
            (UIColor(red: 0.78, green: 0.92, blue: 0.50, alpha: 1), UIColor(red: 0.03, green: 0.19, blue: 0.24, alpha: 1)),
        ]
        let pair = palette[((index % palette.count) + palette.count) % palette.count]
        return [pair.0, pair.1]
    }

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

    /// Öne çıkan birincil aksiyon: düz beyaz zemin, siyah yazı ve simge.
    ///
    /// Telefonda cam buton görselin üstünde siliniyor ve birincil aksiyon
    /// (oynat, daha fazla bilgi) ikincillerden ayırt edilemiyor. Dolu beyaz
    /// buton hem her zeminde okunuyor hem de hangi aksiyonun ana aksiyon
    /// olduğunu tek bakışta söylüyor.
    static func appProminent(
        horizontalInset: CGFloat = 24,
        verticalInset: CGFloat = 12,
        fontSize: CGFloat = 16
    ) -> UIButton.Configuration {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .white
        config.baseForegroundColor = .black
        config.imagePadding = 8
        config.contentInsets = .init(
            top: verticalInset, leading: horizontalInset,
            bottom: verticalInset, trailing: horizontalInset
        )
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: fontSize, weight: .semibold)
            return outgoing
        }
        return config
    }

    /// Seçilebilir çip: tür süzgeci, son aramalar, sezon seçici.
    ///
    /// Seçili çip düz beyaz zemin ve siyah metin, seçili olmayan cam. Cam
    /// konfigürasyonda `baseBackgroundColor` camın **tonu** oluyor; beyaz
    /// verilince saydam kalıyor ve zemin değişmiş gibi görünmüyordu — seçili
    /// çip bu yüzden cam değil dolu.
    ///
    /// Odakta/hover'da beyaza dönmeyi sistem kendisi yapıyor; koşulu, düğmenin
    /// odağı **kendisinin** alması. Bir koleksiyon hücresinin içindeyse hücre
    /// odaklanabilir olmamalı, yoksa odak düğmeye hiç gelmiyor ve düğme
    /// tepkisiz görünüyor.
    static func appChip(
        isSelected: Bool,
        horizontalInset: CGFloat,
        verticalInset: CGFloat,
        fontSize: CGFloat
    ) -> UIButton.Configuration {
        guard isSelected else {
            return .appGlass(
                horizontalInset: horizontalInset,
                verticalInset: verticalInset,
                fontSize: fontSize
            )
        }
        return .appProminent(
            horizontalInset: horizontalInset,
            verticalInset: verticalInset,
            fontSize: fontSize
        )
    }
}

/// Kapsül düğmelerin ölçüsü tek yerde.
///
/// Aynı çip arama süzgecinde, katalog şeridinde, detaydaki sezon seçicide ve
/// oynatıcı denetimlerinde kullanılıyor. Ölçüler daha önce her ekranda ayrı
/// yazıldığı için birbirinden ayrışmıştı — özellikle tvOS'ta: kullanıcı ekrana
/// üç metre uzaktan bakıyor, telefon puntosu orada okunmuyor ve hedef de küçük
/// kalıyor.
enum AppChipSize {
    /// Süzgeç ve seçici çipler.
    case regular
    /// Başlık yanındaki ikincil eylem — "Temizle" gibi.
    case small

    #if os(tvOS)
    var horizontalInset: CGFloat { self == .regular ? 34 : 22 }
    var verticalInset: CGFloat { self == .regular ? 18 : 10 }
    var fontSize: CGFloat { self == .regular ? 26 : 24 }
    #else
    var horizontalInset: CGFloat { self == .regular ? 20 : 14 }
    var verticalInset: CGFloat { self == .regular ? 11 : 6 }
    var fontSize: CGFloat { self == .regular ? 15 : 13 }
    #endif

    /// Bir çipin toplam yüksekliği; düzenler sabit ölçü istiyor.
    var height: CGFloat { (fontSize * 1.3).rounded() + verticalInset * 2 }
}

extension UIButton.Configuration {
    /// Ölçüsü platformdan gelen çip. Çağıran taraf punto ve iç boşluk
    /// seçmiyor: aynı çip her ekranda aynı boyda duruyor.
    static func appChip(isSelected: Bool, size: AppChipSize = .regular) -> UIButton.Configuration {
        appChip(
            isSelected: isSelected,
            horizontalInset: size.horizontalInset,
            verticalInset: size.verticalInset,
            fontSize: size.fontSize
        )
    }

    /// Ölçüsü platformdan gelen birincil (dolu beyaz) buton.
    static func appProminent(size: AppChipSize) -> UIButton.Configuration {
        appProminent(
            horizontalInset: size.horizontalInset,
            verticalInset: size.verticalInset,
            fontSize: size.fontSize
        )
    }

    /// Ölçüsü platformdan gelen cam buton.
    static func appGlass(size: AppChipSize) -> UIButton.Configuration {
        appGlass(
            horizontalInset: size.horizontalInset,
            verticalInset: size.verticalInset,
            fontSize: size.fontSize
        )
    }
}

extension UINavigationController {
    /// Uygulamanın navigasyon yığını: saydam çubuk, beyaz başlık, vurgu rengi.
    ///
    /// Sekme çubuğu (iOS) ve kenar çubuğu (tvOS) aynı yığını kuruyor; görünüm
    /// ayarları iki yerde tekrarlandığında platformlar arasında ayrışıyordu.
    ///
    /// `UIBarAppearance` ailesi tvOS başlıklarında tanımlı olduğu için
    /// **derleniyor**, ama tvOS onu çalışma zamanında reddediyor:
    /// "New Bar Appearance API is not supported on this version of tvOS."
    /// Bu yüzden orada eski (legacy) özelleştirme kullanılıyor.
    static func app(root: UIViewController) -> UINavigationController {
        let nav = UINavigationController(rootViewController: root)

        #if os(iOS)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        #else
        nav.navigationBar.setBackgroundImage(UIImage(), for: .default)
        nav.navigationBar.shadowImage = UIImage()
        nav.navigationBar.isTranslucent = true
        nav.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.white]
        #endif

        nav.navigationBar.tintColor = AppPalette.accent
        return nav
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
class FocusableControl: UIControl {
    /// Odakta uygulanan büyüme. Alt sınıflar kendi ölçüsünü verebiliyor.
    var focusScale: CGFloat { 1.04 }

    /// Odakla birlikte değişen renk/dolgu gibi süsler. Ortak animasyonun
    /// **içinde** çağrılıyor: alt sınıf kendi geçişini kurmak zorunda kalmıyor
    /// ve süs ile ölçek aynı eğriyle hareket ediyor.
    func applyFocusStyle(isFocused: Bool) {}

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
        updateFocusAppearance(isFocused: isFocused, using: coordinator, scale: focusScale) {
            [weak self] in
            guard let self else { return }
            applyFocusStyle(isFocused: self.isFocused)
        }
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

/// Kumanda geri bildirimi.
///
/// tvOS'ta odak bir öğeden diğerine geçtiğinde sistem bir ses çalıyor.
/// Banner'da içerik değiştirmek odağı yerinden oynatmıyor ama kullanıcı için
/// aynı hareket ve aynı sesi bekliyor.
///
/// Sesi tetikleyen bir API yok: `UIFocusSoundIdentifier` yalnızca
/// **gerçekleşen** bir odak hareketinde hangi sesin çalacağını seçtiriyor. Bu
/// yüzden sistemin kendi ses dosyası doğrudan çalınıyor — uydurma bir ses
/// değil, odak hareketinde duyulanın aynısı.
enum RemoteFeedback {
    #if os(tvOS)
    /// Sistemin odak sesi. Bir kez kaydediliyor; dosya bulunamazsa (ileride
    /// yeri değişirse) sessiz kalıyor.
    private static let focusSound: SystemSoundID? = {
        let url = URL(fileURLWithPath: "/System/Library/Audio/UISounds/focus_change_small.caf")
        var identifier: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &identifier)
        return status == kAudioServicesNoError ? identifier : nil
    }()
    #endif

    /// Odak bir butona geldiğinde çıkan sesin aynısı.
    static func focusChange() {
        #if os(tvOS)
        guard let focusSound else { return }
        AudioServicesPlaySystemSound(focusSound)
        #endif
    }
}

extension UIView {
    /// Yan yana duran cam butonları tek bir cam yüzeyde toplar; öğeler
    /// birbirine yaklaştıkça Apple'ın birleşme/ayrılma geçişi devreye giriyor.
    static func glassContainer(wrapping content: UIView, spacing: CGFloat) -> UIView {
        let effect = UIGlassContainerEffect()
        effect.spacing = spacing
        return wrap(content, in: UIVisualEffectView(effect: effect))
    }

    /// İçeriği cam bir yüzeyin üstüne oturtur. Kartlarda kullanılıyor:
    /// kenarda kırılma ve parlama halkası oluşuyor, içerik olduğu gibi kalıyor.
    /// Görselin **üstüne** konan cam katman.
    ///
    /// `glassSurface` malzemeyi içeriğin arkasına koyuyor; afiş gibi opak bir
    /// içerik onu tamamen örtüyor ve cam görünmüyor. Bu katman ise içeriğin
    /// üstünde duruyor, dolayısıyla malzeme afişi kırıyor: kenarlarda lens
    /// etkisi ve parlama, ortada berrak.
    ///
    /// Stil `.clear`: `.regular` buzlu bir malzeme ve afişin tamamını
    /// kapladığında görüntüyü tanınmaz hâle getiriyor. `.clear` tam da
    /// görselin üstüne konmak için var — kırılmayı ve parlamayı veriyor ama
    /// altındakini bulanıklaştırmıyor.
    /// `intensity` malzemenin baskınlığı. `.clear` bile afişin üstünde hafif
    /// bir yumuşama bırakıyor; kartlarda kısık tutulunca kırılma ve parlama
    /// duruyor ama görüntü net kalıyor.
    static func glassOverlay(
        cornerRadius: CGFloat,
        intensity: CGFloat = 1,
        interactive: Bool = false
    ) -> UIVisualEffectView {
        let effect = UIGlassEffect(style: .clear)
        effect.isInteractive = interactive

        let overlay = UIVisualEffectView(effect: effect)
        overlay.cornerConfiguration = .uniformCorners(radius: .fixed(cornerRadius))
        overlay.alpha = intensity
        overlay.isUserInteractionEnabled = false
        overlay.translatesAutoresizingMaskIntoConstraints = false
        return overlay
    }

    /// İçeriği cam bir yüzeyin **üstüne** oturtur: malzeme arkada kalıyor.
    /// Afiş gibi opak bir içerikte cam görünmez, orada `glassOverlay` gerekiyor;
    /// bu yüzey simge ve yazı gibi zeminin göründüğü içerikler için.
    static func glassSurface(
        wrapping content: UIView,
        cornerRadius: CGFloat,
        tint: UIColor? = nil,
        interactive: Bool = true
    ) -> UIVisualEffectView {
        let effect = UIGlassEffect(style: .regular)
        // Dokunma/odak anında camın "sıvı" tepkisi.
        effect.isInteractive = interactive
        effect.tintColor = tint

        let surface = UIVisualEffectView(effect: effect)
        surface.cornerConfiguration = .uniformCorners(radius: .fixed(cornerRadius))
        return wrap(content, in: surface)
    }

    /// Kısıtlar `contentView`'e değil efekt görünümüne bağlanıyor:
    /// `contentView` autoresizing ile boyutlandığı için ona pinlemek boyutu
    /// yukarı taşımıyor ve kapsayıcı sıfıra çöküyor.
    @discardableResult
    private static func wrap(_ content: UIView, in container: UIVisualEffectView) -> UIVisualEffectView {
        container.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        container.contentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        return container
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

    /// iPad ölçüleri.
    ///
    /// Bu kademe olmadan 13" bir iPad yatayda (1366pt) iPhone ile **aynı**
    /// 152pt afişi alıyordu: satırda sekiz kart, minik yazı, her yanda boşluk.
    /// Ölçüler tv ile regular arasında duruyor — kullanıcı ekrana kucağından
    /// bakıyor, kanepeden değil.
    static let large = AppMetrics(
        posterWidth: 200,
        rowSpacing: 48,
        cardSpacing: 22,
        screenPadding: 44,
        heroHeight: 660,
        heroImageWidth: 1600,
        mainCardWidth: 340,
        titleFont: .systemFont(ofSize: 40, weight: .bold),
        rowTitleFont: .systemFont(ofSize: 22, weight: .semibold),
        cardTitleFont: .systemFont(ofSize: 17, weight: .medium),
        listTitleFont: .systemFont(ofSize: 19),
        listSubtitleFont: .systemFont(ofSize: 16),
        mainCardTitleFont: .systemFont(ofSize: 26, weight: .semibold),
        mainCardCountFont: .systemFont(ofSize: 16),
        cardCornerRadius: 12,
        rowHeaderGap: 18,
        rowHeaderHeight: 34,
        clipCardWidth: 340,
        clipCardTextHeight: 0,
        castPhotoWidth: 160,
        detailSectionSpacing: 52,
        cardOverlayPadding: 16,
        cardOverlayFontSize: 14,
        cornerRadius: 12
    )

    /// Genişlik + metin boyutu kombinasyonu başına çözülmüş ölçüler.
    ///
    /// `metrics(for:)` hücre döngüsünün içinden çağrılıyor ve her çağrıda on
    /// küsur `UIFont` içeren bir yapı kuruyordu. Sonuç yalnızca bu iki girdiye
    /// bağlı olduğu için saklanabiliyor.
    private struct MetricsKey: Hashable {
        var widthBucket: Int
        var contentSize: String
    }

    nonisolated(unsafe) private static var cache: [MetricsKey: AppMetrics] = [:]

    /// Görünümün kendi genişliğine göre doğru ölçü setini seçer.
    ///
    /// iOS/iPadOS'ta ana kategori kartlarının genişliği sabit değil, ekrandan
    /// hesaplanıyor: üçü birden ekrana sığmalı, kaydırmaya gerek kalmamalı.
    @MainActor
    static func metrics(for width: CGFloat) -> AppMetrics {
        // Genişlik kaydırma sırasında piksel piksel oynayabiliyor; kovaya
        // yuvarlanınca önbellek gerçekten tutuyor.
        let key = MetricsKey(
            widthBucket: Int((width / 8).rounded()),
            contentSize: UIApplication.shared.preferredContentSizeCategory.rawValue
        )
        if let cached = cache[key] { return cached }

        let resolved = resolve(for: width)
        // Sınırsız büyümesin: dönme ve metin boyutu birkaç kombinasyon üretir,
        // beklenmedik bir dağılımda önbellek baştan kurulur.
        if cache.count > 32 { cache.removeAll(keepingCapacity: true) }
        cache[key] = resolved
        return resolved
    }

    private static func resolve(for width: CGFloat) -> AppMetrics {
        #if os(tvOS)
        var metrics = AppMetrics.tv
        #else
        // iPhone / bölünmüş iPad penceresi / iPad tam ekran.
        var metrics: AppMetrics
        if width < 500 {
            metrics = .compact
        } else if width < 1000 {
            metrics = .regular
        } else {
            metrics = .large
        }
        metrics.scaleFontsForContentSize()
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

    #if os(iOS)
    /// Yazıları kullanıcının metin boyutu tercihine göre ölçekler.
    ///
    /// Kart ve ray yükseklikleri sabit puntoya göre hesaplandığı için ölçek
    /// serbest bırakılmıyor: erişilebilirlik boyutlarında yazı kartın dışına
    /// taşıyor ve satırlar üst üste biniyordu. Üst sınır, düzeni bozmadan
    /// anlamlı bir büyüme bırakıyor.
    private mutating func scaleFontsForContentSize() {
        func scaled(_ font: UIFont, _ style: UIFont.TextStyle, max maximum: CGFloat) -> UIFont {
            UIFontMetrics(forTextStyle: style).scaledFont(for: font, maximumPointSize: maximum)
        }

        titleFont = scaled(titleFont, .largeTitle, max: titleFont.pointSize * 1.3)
        rowTitleFont = scaled(rowTitleFont, .headline, max: rowTitleFont.pointSize * 1.4)
        cardTitleFont = scaled(cardTitleFont, .subheadline, max: cardTitleFont.pointSize * 1.3)
        listTitleFont = scaled(listTitleFont, .body, max: listTitleFont.pointSize * 1.6)
        listSubtitleFont = scaled(listSubtitleFont, .subheadline, max: listSubtitleFont.pointSize * 1.6)
        mainCardTitleFont = scaled(mainCardTitleFont, .title3, max: mainCardTitleFont.pointSize * 1.3)
        mainCardCountFont = scaled(mainCardCountFont, .footnote, max: mainCardCountFont.pointSize * 1.4)
    }
    #endif

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
