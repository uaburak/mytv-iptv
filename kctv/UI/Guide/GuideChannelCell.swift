import UIKit

/// Rehberdeki tek kanal satırı: numara, logo, kanal adı ve o an yayında olan
/// program. Programın ne kadarının geçtiği ince bir çubukla gösteriliyor.
final class GuideChannelCell: UITableViewCell {
    static let reuseID = "GuideChannelCell"

    private let numberLabel = UILabel()
    private let logo = RemoteImageView()
    private let nameLabel = UILabel()
    private let nowLabel = UILabel()
    private let nextLabel = UILabel()
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private var progressWidth: NSLayoutConstraint!

    /// Zoom geçişinin kaynağı.
    var artworkView: UIView { logo }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        backgroundColor = .clear
        let selectedBackground = UIView()
        selectedBackground.backgroundColor = AppPalette.elevated
        selectedBackgroundView = selectedBackground

        // Numaralar alt alta hizalansın diye tabular rakam.
        numberLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        numberLabel.textColor = AppPalette.secondaryText
        numberLabel.textAlignment = .right
        numberLabel.setContentHuggingPriority(.required, for: .horizontal)

        logo.layer.cornerRadius = 6
        logo.layer.cornerCurve = .continuous
        logo.clipsToBounds = true

        nameLabel.textColor = AppPalette.primaryText
        nowLabel.textColor = AppPalette.primaryText
        nowLabel.numberOfLines = 1
        nextLabel.textColor = AppPalette.secondaryText
        nextLabel.numberOfLines = 1

        progressTrack.backgroundColor = AppPalette.separator
        progressTrack.layer.cornerRadius = 1.5
        progressTrack.clipsToBounds = true
        progressFill.backgroundColor = AppPalette.accent

        [numberLabel, logo, nameLabel, nowLabel, nextLabel, progressTrack]
            .forEach { $0.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview($0) }
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.addSubview(progressFill)

        progressWidth = progressFill.widthAnchor.constraint(equalToConstant: 0)

        let bottom = nextLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        bottom.priority = .init(999)

        NSLayoutConstraint.activate([
            numberLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            numberLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            numberLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 34),

            logo.leadingAnchor.constraint(equalTo: numberLabel.trailingAnchor, constant: 12),
            logo.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 72),
            logo.heightAnchor.constraint(equalToConstant: 72 * 9 / 16),

            nameLabel.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: 14),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),

            nowLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            nowLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            nowLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),

            progressTrack.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            progressTrack.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            progressTrack.topAnchor.constraint(equalTo: nowLabel.bottomAnchor, constant: 6),
            progressTrack.heightAnchor.constraint(equalToConstant: 3),

            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            progressWidth,

            nextLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            nextLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            nextLabel.topAnchor.constraint(equalTo: progressTrack.topAnchor, constant: 10),
            bottom,
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        logo.prepareForReuse()
        setPrograms(nil, metrics: nil)
    }

    func configure(item: MediaItem, metrics: AppMetrics) {
        numberLabel.font = .monospacedDigitSystemFont(
            ofSize: metrics.listSubtitleFont.pointSize, weight: .medium
        )
        numberLabel.text = item.channelNumber.map(String.init) ?? "—"
        nameLabel.font = metrics.listTitleFont
        nowLabel.font = metrics.listSubtitleFont
        nextLabel.font = .systemFont(ofSize: metrics.listSubtitleFont.pointSize - 1)

        nameLabel.text = item.title
        // Logolar birbirini tutmayan oranlarda geliyor; kırpmadan sığdırılıyor.
        logo.imageContentMode = .scaleAspectFit
        logo.configure(url: item.posterURL, title: item.title, displayWidth: 72)
    }

    /// Yayın akışı geldiğinde çağrılıyor. `nil` gelmesi "bilgi yok" demek —
    /// satır yine de kanal adıyla çalışır durumda kalıyor.
    func setPrograms(_ entries: [EPGEntry]?, metrics: AppMetrics?) {
        guard let entries, let now = entries.first(where: \.isLive) ?? entries.first else {
            nowLabel.text = entries == nil ? " " : L10n.noProgramInfo
            nextLabel.text = nil
            nextLabel.isHidden = true
            progressTrack.isHidden = true
            return
        }

        let formatter = Self.timeFormatter
        nowLabel.text = "\(formatter.string(from: now.start))  \(now.title)"

        if let next = entries.first(where: { $0.start > now.start }) {
            nextLabel.text = "\(L10n.nextUp) \(formatter.string(from: next.start))  \(next.title)"
            nextLabel.isHidden = false
        } else {
            nextLabel.text = nil
            nextLabel.isHidden = true
        }

        // İlerleme yalnızca şu an yayında olan program için anlamlı.
        let span = now.end.timeIntervalSince(now.start)
        guard now.isLive, span > 0 else {
            progressTrack.isHidden = true
            return
        }
        progressTrack.isHidden = false
        let elapsed = Date().timeIntervalSince(now.start) / span
        layoutIfNeeded()
        progressWidth.constant = progressTrack.bounds.width * min(max(elapsed, 0), 1)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
