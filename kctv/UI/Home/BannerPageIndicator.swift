import UIKit

/// Anasayfa banner'ının sayfa göstergesi.
///
/// `UIPageControl` yerine özel görünüm: Apple'ın öne çıkan içerik
/// bileşenlerindeki gibi, içinde bulunulan sayfanın çubuğu bekleme süresi
/// boyunca soldan sağa doluyor ve dolduğunda sıradaki içeriğe geçiliyor.
/// Çubuklara dokunarak da geçiş yapılabiliyor.
///
/// Görünümün boyunu çubuklar belirliyor; dışarıdan genişlik/yükseklik kısıtı
/// verilmiyor, yalnızca konumlandırılıyor.
final class BannerPageIndicator: UIView {
    /// Bir çubuğa dokunulduğunda o sayfaya geçiş isteniyor.
    var onSelectPage: ((Int) -> Void)?

    private let stack = UIStackView()
    #if os(tvOS)
    private let glassBackground = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    #endif
    private var tracks: [UIView] = []
    private var fills: [UIView] = []
    private var fillWidths: [NSLayoutConstraint] = []
    private var trackWidths: [NSLayoutConstraint] = []

    private(set) var numberOfPages = 0
    private(set) var currentPage = 0

    private static let segmentHeight: CGFloat = 7
    private static let segmentSpacing: CGFloat = 8
    /// İçinde bulunulan sayfa dolan bir çubuk, diğerleri nokta.
    private static let activeWidth: CGFloat = 38
    /// Göstergenin yüksekliği.
    static var preferredHeight: CGFloat {
        #if os(tvOS)
        return segmentHeight + 20
        #else
        return segmentHeight
        #endif
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        #if os(tvOS)
        glassBackground.backgroundColor = UIColor.black.withAlphaComponent(0.40)
        glassBackground.layer.cornerCurve = .continuous
        glassBackground.clipsToBounds = true
        glassBackground.layer.borderWidth = 0.5
        glassBackground.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        glassBackground.isUserInteractionEnabled = false
        glassBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassBackground)

        NSLayoutConstraint.activate([
            glassBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassBackground.topAnchor.constraint(equalTo: topAnchor),
            glassBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        #endif

        stack.axis = .horizontal
        // Genişlikler eşit değil: aktif olan çubuk, diğerleri nokta.
        stack.distribution = .fill
        stack.alignment = .center
        stack.spacing = Self.segmentSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        #if os(tvOS)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            stack.heightAnchor.constraint(equalToConstant: Self.segmentHeight),
        ])
        #else
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.heightAnchor.constraint(equalToConstant: Self.segmentHeight),
        ])
        #endif

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    #if os(tvOS)
    override func layoutSubviews() {
        super.layoutSubviews()
        glassBackground.layer.cornerRadius = bounds.height / 2
    }
    #endif

    /// Çubuklar birkaç punto yüksekliğinde; dokunma alanı görünürden geniş.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -8, dy: -14).contains(point)
    }

    func setPages(_ count: Int) {
        guard count != numberOfPages else { return }
        numberOfPages = count
        currentPage = min(currentPage, max(count - 1, 0))

        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        tracks = []
        fills = []
        fillWidths = []
        trackWidths = []

        for _ in 0..<max(count, 0) {
            let track = UIView()
            track.backgroundColor = UIColor.white.withAlphaComponent(0.32)
            track.layer.cornerRadius = Self.segmentHeight / 2
            track.layer.cornerCurve = .continuous
            track.clipsToBounds = true
            track.translatesAutoresizingMaskIntoConstraints = false

            let fill = UIView()
            fill.backgroundColor = .white
            fill.translatesAutoresizingMaskIntoConstraints = false
            track.addSubview(fill)

            let fillWidth = fill.widthAnchor.constraint(equalToConstant: 0)
            let trackWidth = track.widthAnchor.constraint(equalToConstant: Self.segmentHeight)
            NSLayoutConstraint.activate([
                trackWidth,
                track.heightAnchor.constraint(equalToConstant: Self.segmentHeight),
                fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
                fill.topAnchor.constraint(equalTo: track.topAnchor),
                fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
                fillWidth,
            ])

            stack.addArrangedSubview(track)
            tracks.append(track)
            fills.append(fill)
            fillWidths.append(fillWidth)
            trackWidths.append(trackWidth)
        }

        applyShapes(animated: false)
    }

    /// Dolum animasyonunu durdurup geçilen sayfayı işaretler. Yeni sayfanın
    /// dolumu ayrıca `startProgress` ile başlatılıyor.
    func setCurrentPage(_ index: Int) {
        guard index >= 0, index < numberOfPages else { return }
        currentPage = index
        applyShapes(animated: true)
    }

    /// Aktif sayfa çubuk, diğerleri nokta. Genişlik değişimi animasyonlu ki
    /// sayfa geçişinde gösterge sıçramasın.
    private func applyShapes(animated: Bool) {
        for (index, width) in trackWidths.enumerated() {
            width.constant = index == currentPage ? Self.activeWidth : Self.segmentHeight
        }
        resetFills()
        guard animated else {
            layoutIfNeeded()
            return
        }
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            self.layoutIfNeeded()
        }
    }

    /// İçinde bulunulan sayfanın çubuğunu `duration` boyunca doldurur.
    func startProgress(duration: TimeInterval) {
        resetFills()
        guard currentPage < fillWidths.count else { return }

        layoutIfNeeded()
        let target = Self.activeWidth
        guard tracks[currentPage].bounds.width > 0 else { return }

        fillWidths[currentPage].constant = target
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveLinear, .allowUserInteraction, .beginFromCurrentState]
        ) {
            self.layoutIfNeeded()
        }
    }

    func stopProgress() {
        resetFills()
    }

    /// Dolum yalnızca aktif çubukta anlamlı; noktalar zaten dolu görünüyor.
    private func resetFills() {
        for (index, width) in fillWidths.enumerated() {
            fills[index].layer.removeAllAnimations()
            width.constant = 0
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard numberOfPages > 0 else { return }
        let location = gesture.location(in: stack)
        guard let index = tracks.firstIndex(where: { $0.frame.insetBy(dx: -Self.segmentSpacing / 2, dy: -12).contains(location) })
        else { return }
        onSelectPage?(index)
    }
}
