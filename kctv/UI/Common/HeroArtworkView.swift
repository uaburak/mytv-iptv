import UIKit

/// Hero görsellerinin ortak zemini: arka plan görseli ve üzerindeki açılış
/// yükleme katmanı.
///
/// Kural detay ekranından geliyor ve anasayfa banner'ında da aynısı geçerli:
/// arka plana **yalnızca gerçek 16:9 backdrop** basılıyor. Dikey afiş asla
/// arka plan olmuyor — kırpıldığında bozuk ve amatör görünüyor. Backdrop
/// gelene kadar üstte koyu blur ve nabız duruyor, görsel yerleştiğinde
/// yumuşakça açılıyor.
final class HeroArtworkView: UIView {
    private let imageView = RemoteImageView()

    /// İlk açılışta gerçek görsel gelene kadar duran geçiş katmanı.
    /// `systemMaterialDark` tvOS'ta yok; orada düz koyu blur kullanılıyor.
    #if os(iOS)
    private let loadingBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    #else
    private let loadingBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    #endif
    private let pulseOverlay = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        clipsToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.clipsToBounds = true
        // Hero'da baş harf yer tutucusu istenmiyor; yalnızca koyu bir zemin.
        imageView.showsInitials = false
        addSubview(imageView)

        loadingBlurView.translatesAutoresizingMaskIntoConstraints = false
        loadingBlurView.alpha = 0
        loadingBlurView.isHidden = true
        addSubview(loadingBlurView)

        pulseOverlay.translatesAutoresizingMaskIntoConstraints = false
        pulseOverlay.backgroundColor = UIColor.white.withAlphaComponent(0.05)
        loadingBlurView.contentView.addSubview(pulseOverlay)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            loadingBlurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            loadingBlurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            loadingBlurView.topAnchor.constraint(equalTo: topAnchor),
            loadingBlurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            pulseOverlay.leadingAnchor.constraint(equalTo: loadingBlurView.contentView.leadingAnchor),
            pulseOverlay.trailingAnchor.constraint(equalTo: loadingBlurView.contentView.trailingAnchor),
            pulseOverlay.topAnchor.constraint(equalTo: loadingBlurView.contentView.topAnchor),
            pulseOverlay.bottomAnchor.constraint(equalTo: loadingBlurView.contentView.bottomAnchor),
        ])
    }

    /// `backdropURL` yalnızca yatay sinematik görsel olmalı. `nil` verilirse
    /// görsel boş kalıyor; afişe düşülmüyor.
    func configure(backdropURL: URL?, title: String, displayWidth: CGFloat) {
        imageView.configure(url: backdropURL, title: title, displayWidth: displayWidth)
    }

    func startLoading() {
        loadingBlurView.layer.removeAllAnimations()
        loadingBlurView.isHidden = false
        loadingBlurView.alpha = 1
        pulseOverlay.layer.removeAllAnimations()

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.2
        pulse.toValue = 0.9
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulseOverlay.layer.add(pulse, forKey: "pulse")
    }

    func stopLoading(animated: Bool = true) {
        pulseOverlay.layer.removeAllAnimations()
        guard !loadingBlurView.isHidden, loadingBlurView.alpha > 0 else { return }
        guard animated else {
            loadingBlurView.layer.removeAllAnimations()
            loadingBlurView.alpha = 0
            loadingBlurView.isHidden = true
            return
        }
        UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            self.loadingBlurView.alpha = 0
        } completion: { finished in
            guard finished else { return }
            self.loadingBlurView.isHidden = true
        }
    }

    func prepareForReuse() {
        imageView.prepareForReuse()
        stopLoading(animated: false)
    }
}
