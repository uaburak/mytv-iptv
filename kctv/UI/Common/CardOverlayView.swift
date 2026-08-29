import UIKit

/// Kartın alt kenarındaki bilgi katmanı: oynat işareti, ilerleme çubuğu,
/// başlık ve süre.
///
/// Bulanıklığın sert bir kenarı yok: yukarıdan aşağı açılan bir maskeyle
/// görselin içinden yumuşakça beliriyor, altına da okunabilirlik için karartma
/// biniyor. Sert kenarlı bir şerit kartı ikiye bölünmüş gibi gösteriyordu.
///
/// Dört durum var; hepsi `progress` ve `focused` ikilisinden türüyor:
///
/// | durum | yerleşim |
/// |---|---|
/// | oynatılmış, odak yok | `▶ ▬▬ Başlık` |
/// | oynatılmış, odakta | başlık kendi satırında; altında `▶ ▬▬▬▬ süre` |
/// | başlanmamış, odak yok | yalnızca başlık, oynat işareti yok |
/// | başlanmamış, odakta | yalnızca başlık |
///
/// Punto durumlar arasında değişmiyor; büyüme kartın ölçeğinden geliyor.
final class CardOverlayView: UIView {
    private let blur = UIVisualEffectView(effect: nil)
    private let blurMask = CAGradientLayer()
    private let scrim = CAGradientLayer()

    private let playIcon = UIImageView()
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private let titleLabel = UILabel()
    private let durationLabel = UILabel()

    private let compactRow = UIStackView()
    private let wideStack = UIStackView()
    private let wideBottomRow = UIStackView()

    private var progressWidth: NSLayoutConstraint!
    private var compactProgressWidth: NSLayoutConstraint!
    private var progressHeight: NSLayoutConstraint!
    private var layoutConstraints: [NSLayoutConstraint] = []
    private var fraction: Double = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        isUserInteractionEnabled = false

        #if os(iOS)
        blur.effect = UIBlurEffect(style: .systemThinMaterialDark)
        #else
        blur.effect = UIBlurEffect(style: .dark)
        #endif
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)

        // Maske siyah olduğu yerde görünür: üstte tamamen şeffaf, aşağı
        // indikçe bulanıklık açılıyor.
        blurMask.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.6).cgColor,
            UIColor.black.cgColor,
        ]
        blurMask.locations = [0, 0.45, 0.85]
        blur.layer.mask = blurMask

        // Bulanıklık tek başına metni taşımıyor; altına hafif karartma.
        scrim.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.45).cgColor,
        ]
        scrim.locations = [0, 0.9]
        layer.insertSublayer(scrim, above: blur.layer)

        playIcon.image = UIImage(systemName: "play.fill")
        playIcon.tintColor = .white
        playIcon.contentMode = .scaleAspectFit
        playIcon.setContentHuggingPriority(.required, for: .horizontal)
        playIcon.setContentCompressionResistancePriority(.required, for: .horizontal)

        progressTrack.backgroundColor = UIColor.white.withAlphaComponent(0.35)
        progressTrack.clipsToBounds = true
        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        progressFill.backgroundColor = .white
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.addSubview(progressFill)

        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1

        durationLabel.textColor = .white
        durationLabel.textAlignment = .right
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)
        durationLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        progressWidth = progressFill.widthAnchor.constraint(equalToConstant: 0)
        compactProgressWidth = progressTrack.widthAnchor.constraint(equalToConstant: 44)
        progressHeight = progressTrack.heightAnchor.constraint(equalToConstant: 4)

        compactRow.axis = .horizontal
        compactRow.alignment = .center
        compactRow.spacing = 8
        compactRow.translatesAutoresizingMaskIntoConstraints = false

        wideBottomRow.axis = .horizontal
        wideBottomRow.alignment = .center
        wideBottomRow.spacing = 12

        wideStack.axis = .vertical
        wideStack.alignment = .fill
        wideStack.spacing = 10
        wideStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(compactRow)
        addSubview(wideStack)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),

            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            progressWidth,
            progressHeight,
        ])
    }

    /// - Parameters:
    ///   - progress: `nil` ise içerik hiç başlanmamış demek.
    ///   - focused: kart odakta (tvOS) ya da vurgulu.
    func configure(
        title: String,
        durationText: String?,
        progress: Double?,
        focused: Bool,
        metrics: AppMetrics
    ) {
        fraction = progress ?? 0

        // Oynat işareti yalnızca başlanmış içerikte; hiç açılmamış bölümde
        // "devam et" çağrışımı yaptığı için gösterilmiyor.
        let showsPlayIcon = progress != nil
        // İki satırlı yerleşim yalnızca başlanmış içerik odaktayken.
        let wide = progress != nil && focused

        // Punto odakta artırılmıyor: kartın ölçek dönüşümü zaten içindeki her
        // şeyi büyütüyor. Ayrıca punto eklemek metni kartın iki katı oranında
        // büyütüyordu.
        let size = metrics.cardOverlayFontSize
        titleLabel.font = .systemFont(ofSize: size, weight: .semibold)
        durationLabel.font = .systemFont(ofSize: size - 1, weight: .semibold)
        titleLabel.text = title
        durationLabel.text = durationText

        playIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: size * 0.95, weight: .bold
        )
        playIcon.isHidden = !showsPlayIcon

        let barHeight = max(size * 0.26, 4)
        progressHeight.constant = barHeight
        progressTrack.layer.cornerRadius = barHeight / 2
        progressFill.layer.cornerRadius = barHeight / 2
        compactProgressWidth.constant = size * 3.2

        // Yerleşim değişiminde alt görünümler yeniden dağıtılıyor.
        [compactRow, wideBottomRow, wideStack].forEach { stack in
            stack.arrangedSubviews.forEach {
                stack.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
        }
        compactProgressWidth.isActive = false

        if wide {
            compactRow.isHidden = true
            wideStack.isHidden = false
            wideStack.addArrangedSubview(titleLabel)
            wideBottomRow.addArrangedSubview(playIcon)
            wideBottomRow.addArrangedSubview(progressTrack)
            if durationText != nil { wideBottomRow.addArrangedSubview(durationLabel) }
            wideStack.addArrangedSubview(wideBottomRow)
        } else {
            wideStack.isHidden = true
            compactRow.isHidden = false
            if showsPlayIcon { compactRow.addArrangedSubview(playIcon) }
            if progress != nil {
                compactRow.addArrangedSubview(progressTrack)
                compactProgressWidth.isActive = true
            }
            compactRow.addArrangedSubview(titleLabel)
        }

        applyContentConstraints(wide: wide, padding: metrics.cardOverlayPadding)
        setNeedsLayout()
    }

    /// İçerik alta yaslı; üstte bulanıklığın açılması için pay bırakılıyor.
    private func applyContentConstraints(wide: Bool, padding: CGFloat) {
        NSLayoutConstraint.deactivate(layoutConstraints)
        let container = wide ? wideStack : compactRow
        layoutConstraints = [
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding * 0.85),
            container.topAnchor.constraint(equalTo: topAnchor, constant: padding * 1.9),
        ]
        NSLayoutConstraint.activate(layoutConstraints)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Katman ağacı Auto Layout dışında; çerçeveler elle veriliyor.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        blurMask.frame = bounds
        scrim.frame = bounds
        CATransaction.commit()

        progressWidth.constant = progressTrack.bounds.width * min(max(fraction, 0), 1)
    }
}
