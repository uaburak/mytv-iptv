import KSPlayer
import UIKit

/// Altyazı katmanı.
///
/// KSPlayer altyazıyı ekrana kendisi koymuyor: gömülü akışı çözüp
/// `SubtitlePart` olarak veriyor, çizmek uygulamanın işi. Bu katman video ile
/// kontrollerin arasında duruyor ve iki türü de karşılıyor:
///
/// - **Metin** (SRT/ASS/mov_text): ortalanmış bir etiket. Punto, renk ve şerit
///   `SubtitleSettings`'ten geliyor.
/// - **Görüntü** (PGS/DVB): kare olarak gelen bitmap. Konumu için video
///   karesinin tamamı gerektiğinden katman tam ekran duruyor ve resim
///   KSPlayer'ın kendi `fitRect` kuralıyla alta hizalanıp ölçekleniyor.
///
/// Katman dokunmaları geçiriyor: üstünde durduğu videoya yapılan dokunuş
/// kontrolleri açmaya devam ediyor.
final class SubtitleOverlayView: UIView {
    /// Altyazının alt kenardan uzaklığı. Kontroller açıldığında çubuğun
    /// üstüne çıksın diye oynatıcı burayı canlandırıyor.
    var bottomInset: CGFloat = 0 {
        didSet {
            guard bottomInset != oldValue else { return }
            textBottom.constant = -(bottomInset + Self.margin)
            setNeedsLayout()
        }
    }

    /// Ekrandaki parçalar. Aynı anda birden çok satır gelebiliyor (konuşan
    /// kişi + ekran yazısı); hepsi alt alta tek etikette birleşiyor.
    var parts: [SubtitlePart] = [] {
        didSet { render() }
    }

    #if os(tvOS)
    private static let margin: CGFloat = 60
    private static let sideInset: CGFloat = 120
    #else
    private static let margin: CGFloat = 16
    private static let sideInset: CGFloat = 24
    #endif

    private let backdrop = UIView()
    private let label = UILabel()
    private let imageView = UIImageView()
    private var textBottom: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false

        imageView.contentMode = .scaleToFill
        addSubview(imageView)

        backdrop.layer.cornerRadius = 6
        backdrop.layer.cornerCurve = .continuous
        backdrop.isHidden = true
        addSubview(backdrop)

        label.numberOfLines = 0
        label.textAlignment = .center
        // Şeritsiz kullanımda okunabilirliği bu gölge taşıyor: açık bir
        // sahnede beyaz yazı gölgesiz tamamen kayboluyor.
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOffset = CGSize(width: 0, height: 1)
        label.layer.shadowRadius = 3
        label.layer.shouldRasterize = true
        backdrop.addSubview(label)

        backdrop.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        textBottom = backdrop.bottomAnchor.constraint(
            equalTo: bottomAnchor,
            constant: -Self.margin
        )
        NSLayoutConstraint.activate([
            textBottom,
            backdrop.centerXAnchor.constraint(equalTo: centerXAnchor),
            backdrop.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Self.sideInset),
            backdrop.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.sideInset),

            label.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor, constant: -4),
        ])

        applySettings()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Görüntü altyazısı otomatik yerleşime girmiyor: bitmap'in kendi ölçüsü
    /// var ve kare içinde alta ortalanması gerekiyor.
    override func layoutSubviews() {
        super.layoutSubviews()
        label.layer.rasterizationScale = traitCollection.displayScale
        guard let image = imageView.image else { return }
        var rect = image.fitRect(bounds.size)
        rect.origin.y -= bottomInset + Self.margin
        imageView.frame = rect
    }

    /// Ayarlar değiştiğinde çağrılıyor; menüden dönüşte yazı anında yeni
    /// biçimine geçiyor.
    func applySettings() {
        let background = SubtitleSettings.background
        label.font = SubtitleSettings.font
        label.textColor = SubtitleSettings.textColor.color
        backdrop.backgroundColor = background.color
        label.layer.shadowOpacity = background == .clear ? 0.95 : 0
    }

    private func render() {
        let text = NSMutableAttributedString()
        for part in parts {
            guard let partText = part.text, partText.length > 0 else { continue }
            if text.length > 0 { text.append(NSAttributedString(string: "\n")) }
            text.append(partText)
        }
        label.attributedText = text.length > 0 ? text : nil
        backdrop.isHidden = text.length == 0

        let image = parts.compactMap(\.image).first
        imageView.image = image
        imageView.isHidden = image == nil
        if image != nil { setNeedsLayout() }
    }
}
