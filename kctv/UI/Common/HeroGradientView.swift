import UIKit

/// `layerClass`'ı `CAGradientLayer` olan yerel UIKit gradient bileşeni.
///
/// Katmanın kendisi görünümün katmanı olduğu için çerçevesi görünümle
/// birlikte hareket ediyor: karartma, üstünde durduğu görsel esnerken ya da
/// geri çekilirken bir kare geriden gelmiyor ve düzen turlarında çerçeve
/// hesaplamak gerekmiyor.
final class HeroGradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }

    var colors: [UIColor] = [] {
        didSet { gradientLayer.colors = colors.map(\.cgColor) }
    }

    var locations: [NSNumber]? {
        get { gradientLayer.locations }
        set { gradientLayer.locations = newValue }
    }

    /// Varsayılan dikey; soldan sağa karartma için yatay kullanılıyor.
    func setDirection(start: CGPoint, end: CGPoint) {
        gradientLayer.startPoint = start
        gradientLayer.endPoint = end
    }
}
