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

    /// Görselin kenarlardan payı — görünümün **kısa** kenarına oran.
    ///
    /// `.scaleAspectFit` ile anlamlı: kırpmadan sığdırılan bir logo kartın
    /// kenarlarına dayanıyor ve olduğundan büyük duruyor. Pay, kartın oranı ne
    /// olursa olsun logonun etrafında aynı kalınlıkta bir boşluk bırakıyor —
    /// yatay ve dikey ayrı ayrı hesaplansaydı geniş kartta yanlarda kalın,
    /// üstte ince bir çerçeve çıkardı.
    var imageInsetRatio: CGFloat = 0 {
        didSet { setNeedsLayout() }
    }

    /// Kanal logolarının kart içindeki payı. Tek yerden okunuyor: aynı logo
    /// ızgarada da katalogda da aynı büyüklükte durmalı.
    static let logoInsetRatio: CGFloat = 0.15

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

    /// Görselin yerine adın baş harfleri.
    ///
    /// Varsayılan **kapalı**. Afişi olmayan ya da henüz inmemiş bir kartta
    /// beliren iki-üç harf hiçbir şey anlatmıyordu; üstelik afiş düşer düşmez
    /// kayboluyordu, yani her kart yüklenirken içinde bir yazı yanıp sönüyordu.
    /// Afiş yoksa yapacak bir şey de yok: degrade zemin yeterli.
    ///
    /// Kişi görsellerinde (profil avatarı, oyuncu fotoğrafları) açılıyor —
    /// orada baş harfler eksik bir görselin yerini tutmuyor, kişinin adının
    /// kısaltması oluyor.
    var showsInitials = false {
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
    /// `imageInsetRatio` bunların sabitini sürüyor.
    private var imageEdges: [NSLayoutConstraint] = []


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

        initialsLabel.isHidden = true
        initialsLabel.textAlignment = .center
        initialsLabel.font = .systemFont(ofSize: 30, weight: .semibold)
        initialsLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        initialsLabel.adjustsFontSizeToFitWidth = true
        initialsLabel.minimumScaleFactor = 0.5
        initialsLabel.numberOfLines = 2

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true

        initialsLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(initialsLabel)
        NSLayoutConstraint.activate([
            initialsLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            initialsLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            initialsLabel.topAnchor.constraint(equalTo: topAnchor),
            initialsLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        // Sabitleri `layoutSubviews` sürüyor; pay yokken dördü de sıfır ve
        // görsel eskisi gibi kenardan kenara.
        imageEdges = [
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
        ]
        NSLayoutConstraint.activate(imageEdges)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
        if isCircular {
            layer.cornerRadius = min(bounds.width, bounds.height) / 2
        }

        // Pay görünümün ölçüsünden çıkıyor, o yüzden burada. Değişmediyse
        // sabite dokunulmuyor: her düzen turunda kısıt güncellemek bir tur
        // daha düzen istiyor ve iş sonu gelmeyen bir döngüye dönüyor.
        let inset = (min(bounds.width, bounds.height) * imageInsetRatio).rounded()
        guard imageEdges.first?.constant != inset else { return }
        for edge in imageEdges { edge.constant = inset }
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
