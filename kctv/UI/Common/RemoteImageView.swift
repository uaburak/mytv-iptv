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

    /// Görselin sığdırılma kuralı (`.scaleAspectFill` varsayılan, `.scaleAspectFit` oran koruyan logolar için).
    var imageContentMode: UIView.ContentMode {
        get { imageView.contentMode }
        set { imageView.contentMode = newValue }
    }

    /// Arka planda degrade yer tutucunun gösterilip gösterilmeyeceği.
    var showsPlaceholderBackground: Bool = true {
        didSet { gradientLayer.isHidden = !showsPlaceholderBackground }
    }

    /// Odaktaki büyüme payı; kartların ölçek katsayısıyla aynı.
    private static let focusHeadroom: CGFloat = 1.1

    /// Bir görselin kaç piksele çözüleceği.
    ///
    /// Kural ortak: aynı görseli farklı ölçüyle isteyen iki taraf
    /// `ImageLoader` önbelleğinde iki ayrı kayıt açıyor ve aynı backdrop
    /// bellekte iki kez duruyor. Banner yüklemesini kendi yaptığı için hesabı
    /// buradan alıyor.
    static func pixelSize(displayWidth: CGFloat, scale: CGFloat) -> CGFloat {
        displayWidth * max(2, scale > 0 ? scale : 3) * focusHeadroom
    }

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
        loadTask?.cancel()
        currentURL = url

        guard let url else {
            imageView.image = nil
            imageView.alpha = 0
            return
        }

        let scale = window?.windowScene?.screen.scale ?? traitCollection.displayScale
        // Kart odakta büyüyor; görsel dinlenme boyutuna göre indirilirse
        // büyürken yumuşuyor. Büyüme payı baştan hesaba katılıyor.
        let maxPixelSize = Self.pixelSize(displayWidth: displayWidth, scale: scale)

        // Önbellek **senkron** okunuyor: hazır bir görsel için tek bir kare
        // bile boş geçmiyor. Eski kod önce görüntüyü siliyor, sonra aktöre
        // gidip aynı kareyi geri koyuyordu; kaydırırken ve ekranlar arası
        // gidip gelirken her kart bir anlığına yer tutucuya düşüyordu.
        if let cached = ImageLoader.cachedImage(url: url, maxPixelSize: maxPixelSize) {
            imageView.image = cached
            imageView.alpha = 1
            return
        }

        imageView.image = nil
        imageView.alpha = 0

        loadTask = Task { [weak self] in
            let image = await ImageLoader.shared.image(for: url, maxPixelSize: maxPixelSize)
            guard let image else { return }
            self?.apply(image, animated: true, for: url)
        }
    }

    /// Bu görünümün ölçüsüyle görseli önceden çözer; ekran açıldığında
    /// bellekten gelsin diye.
    static func prefetch(_ urls: [URL], displayWidth: CGFloat, scale: CGFloat = 3) {
        ImageLoader.shared.prefetch(
            urls, maxPixelSize: pixelSize(displayWidth: displayWidth, scale: scale)
        )
    }

    /// Önceden çözülmüş görseli doğrudan basar; ağa çıkmaz.
    ///
    /// Anasayfa banner'ı geçişi kendisi yönetiyor: görsel çapraz geçiş
    /// başlamadan **önce** hazır olmalı. `configure` ile URL verildiğinde
    /// resim bir-iki kare sonra düşüyor ve geçiş ikiye bölünüyordu.
    func setImage(_ image: UIImage?) {
        loadTask?.cancel()
        loadTask = nil
        currentURL = nil
        imageView.image = image
        imageView.alpha = image == nil ? 0 : 1
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
        guard showsPlaceholderBackground else {
            gradientLayer.isHidden = true
            initialsLabel.text = ""
            return
        }
        gradientLayer.isHidden = false
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
