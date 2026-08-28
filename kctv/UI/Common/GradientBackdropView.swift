import UIKit

/// Üstte şeffaftan başlayıp aşağı doğru düz renge geçen arka plan.
///
/// Detay ekranında, hero görselinin üzerinden kayan içerik bloğunun altına
/// konuyor: siyah zemin birden bitmek yerine yumuşak bir geçişle başlıyor.
final class GradientBackdropView: UIView {
    private let gradient = CAGradientLayer()
    /// Geçişin tamamlandığı yükseklik (punto).
    var rampHeight: CGFloat = 140 {
        didSet { setNeedsLayout() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradient.colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(0.85).cgColor,
            UIColor.black.cgColor,
        ]
        layer.addSublayer(gradient)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        // Rampa yüksekliği sabit; kalan alan düz renk.
        let ramp = bounds.height > 0 ? min(1, rampHeight / bounds.height) : 1
        gradient.locations = [0, NSNumber(value: Double(ramp * 0.7)), NSNumber(value: Double(ramp))]
        CATransaction.commit()
    }
}
