import UIKit

/// Poster/logo görünümü.
///
/// Yükleme `ImageLoader` üzerinden: bellek önbelleği ve hedef boyuta indirme
/// olmadan kaydırma sırasında kareler düşüyordu. Bağlantısı ölü görseller için
/// başlığın baş harfleriyle üretilmiş bir yer tutucuya düşer — kart hiç boş kalmaz.
final class RemoteImageView: UIView {
    private let imageView = UIImageView()
    private let initialsLabel = UILabel()
    private let gradientLayer = CAGradientLayer()

    /// Görselin ekranda kaplayacağı yaklaşık genişlik (punto).
    var displayWidth: CGFloat = 200

    /// Kartlarda başlığın baş harfleri yer tutucu olarak gösteriliyor.
    /// Detay hero'sunda kapalı: orada yalnızca bulanık bir zemin isteniyor.
    var showsInitials = true {
        didSet { initialsLabel.isHidden = !showsInitials }
    }

    /// Görünüm daireye yuvarlanıyor. Yarıçapı çağıranın hesaplaması güvenilir
    /// değildi: hücrenin düzen turunda görünümün son boyutu henüz oturmamış
    /// olabiliyor ve daire kare kalıyordu.
    var isCircular = false {
        didSet { setNeedsLayout() }
    }

    private var currentURL: URL?
    private var loadTask: Task<Void, Never>?


    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        clipsToBounds = true
        layer.addSublayer(gradientLayer)

        initialsLabel.textAlignment = .center
        initialsLabel.font = .systemFont(ofSize: 30, weight: .semibold)
        initialsLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        initialsLabel.adjustsFontSizeToFitWidth = true
        initialsLabel.minimumScaleFactor = 0.5
        initialsLabel.numberOfLines = 2

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true

        for subview in [initialsLabel, imageView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
            NSLayoutConstraint.activate([
                subview.leadingAnchor.constraint(equalTo: leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: trailingAnchor),
                subview.topAnchor.constraint(equalTo: topAnchor),
                subview.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        if isCircular {
            layer.cornerRadius = min(bounds.width, bounds.height) / 2
        }
    }

    func configure(url: URL?, title: String, displayWidth: CGFloat) {
        self.displayWidth = displayWidth
        applyPlaceholder(title: title)

        guard currentURL != url || imageView.image == nil else { return }
        currentURL = url
        loadTask?.cancel()
        imageView.image = nil
        imageView.alpha = 0

        guard let url else { return }
        let scale = window?.windowScene?.screen.scale ?? traitCollection.displayScale
        let effectiveScale = scale > 0 ? scale : 3.0
        let maxPixelSize = displayWidth * max(2, effectiveScale)

        loadTask = Task { [weak self] in
            // Önbellekte varsa ilk karede göster.
            if let cached = await ImageLoader.shared.cached(url: url, maxPixelSize: maxPixelSize) {
                self?.apply(cached, animated: false, for: url)
                return
            }
            let image = await ImageLoader.shared.image(for: url, maxPixelSize: maxPixelSize)
            guard let image else { return }
            self?.apply(image, animated: true, for: url)
        }
    }

    private func apply(_ image: UIImage, animated: Bool, for url: URL) {
        guard !Task.isCancelled, currentURL == url else { return }
        imageView.image = image
        guard animated else {
            imageView.alpha = 1
            return
        }
        UIView.animate(withDuration: 0.18) { self.imageView.alpha = 1 }
    }

    /// Başlıktan türetilen sabit renk. `hashValue` her süreçte değiştiği için
    /// kullanılmıyor; bu toplama her açılışta aynı sonucu veriyor.
    private func applyPlaceholder(title: String) {
        guard showsInitials else {
            initialsLabel.text = ""
            gradientLayer.colors = [
                UIColor.black.cgColor,
                UIColor.black.cgColor,
            ]
            return
        }

        let words = title.split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first)
        initialsLabel.text = letters.isEmpty ? "?" : String(letters).uppercased()

        let seed = title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }
        let hue = CGFloat(seed) / 360
        let base = UIColor(hue: hue, saturation: 0.45, brightness: 0.55, alpha: 1)
        gradientLayer.colors = [
            base.withAlphaComponent(0.75).cgColor,
            base.withAlphaComponent(0.35).cgColor,
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
    }

    func prepareForReuse() {
        loadTask?.cancel()
        loadTask = nil
        currentURL = nil
        imageView.image = nil
        imageView.alpha = 0
    }
}
