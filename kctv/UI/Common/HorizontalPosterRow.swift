import UIKit

/// Yatay kaydırmalı poster şeridi. Detay ekranındaki "Benzer İçerikler" gibi
/// koleksiyon görünümü kurmaya değmeyen yerlerde kullanılıyor.
final class HorizontalPosterRow: UIView {
    private let items: [MediaItem]
    private let metrics: AppMetrics
    private let onSelect: (MediaItem, UIView?) -> Void
    private var collectionView: UICollectionView!

    init(items: [MediaItem], metrics: AppMetrics, onSelect: @escaping (MediaItem, UIView?) -> Void) {
        self.items = items
        self.metrics = metrics
        self.onSelect = onSelect
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = metrics.cardSpacing
        layout.sectionInset = UIEdgeInsets(
            top: 0, left: metrics.screenPadding, bottom: 0, right: metrics.screenPadding
        )

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        // Kenar payı yalnızca `sectionInset`'ten gelsin; güvenli alan üstüne
        // eklenirse ray diğer bölümlerle aynı hizada başlamıyor.
        collectionView.contentInsetAdjustmentBehavior = .never
        // Odaklanan kart kendi hücresinin dışına büyüyor; kırpma açık kalırsa
        // efektin üstü kesiliyor.
        #if os(tvOS)
        collectionView.clipsToBounds = false
        #endif
        collectionView.applyNativeScrollEdges()
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PosterCell.self, forCellWithReuseIdentifier: PosterCell.reuseID)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}

extension HorizontalPosterRow: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: PosterCell.reuseID, for: indexPath
        ) as! PosterCell
        cell.configure(item: items[indexPath.item], metrics: metrics, progress: nil)
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let kind = items[indexPath.item].kind
        return CGSize(width: metrics.cardWidth(for: kind), height: metrics.rowItemHeight(for: kind))
    }

    #if os(tvOS)
    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        collectionView.unclipFocusGrowth(around: cell)
    }
    #endif

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        onSelect(items[indexPath.item], collectionView.cellForItem(at: indexPath))
    }
}

/// Seri filmler için yatay afiş şeridi.
/// Katalogda var olan ve olmayan (yalnızca TMDB'de kayıtlı olan) tüm seri parçalarını gösterir.
final class HorizontalFranchiseRow: UIView {
    private let items: [FranchiseEntry]
    private let metrics: AppMetrics
    private let onSelect: (FranchiseEntry, UIView?) -> Void
    private var collectionView: UICollectionView!

    init(items: [FranchiseEntry], metrics: AppMetrics, onSelect: @escaping (FranchiseEntry, UIView?) -> Void) {
        self.items = items
        self.metrics = metrics
        self.onSelect = onSelect
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = metrics.cardSpacing
        layout.sectionInset = UIEdgeInsets(
            top: 0, left: metrics.screenPadding, bottom: 0, right: metrics.screenPadding
        )

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        #if os(tvOS)
        collectionView.clipsToBounds = false
        #endif
        collectionView.applyNativeScrollEdges()
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PosterCell.self, forCellWithReuseIdentifier: PosterCell.reuseID)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}

extension HorizontalFranchiseRow: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: PosterCell.reuseID, for: indexPath
        ) as! PosterCell
        let item = items[indexPath.item]
        cell.configure(
            item: item.effectiveItem,
            metrics: metrics,
            progress: nil,
            badgeText: item.isAvailableInCatalog ? nil : L10n.notInCatalog,
            isAvailable: item.isAvailableInCatalog
        )
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let kind = MediaKind.movie
        return CGSize(width: metrics.cardWidth(for: kind), height: metrics.rowItemHeight(for: kind))
    }

    #if os(tvOS)
    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        collectionView.unclipFocusGrowth(around: cell)
    }
    #endif

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        onSelect(items[indexPath.item], collectionView.cellForItem(at: indexPath))
    }
}

/// Seri filmler yüklenirken gösterilen parlama/nabız efektli iskelet kartlar.
final class FranchiseSkeletonRow: UIView {
    private let metrics: AppMetrics
    private let stack = UIStackView()
    private var cards: [UIView] = []

    init(metrics: AppMetrics) {
        self.metrics = metrics
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        stack.axis = .horizontal
        stack.spacing = metrics.cardSpacing
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: metrics.screenPadding),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -metrics.screenPadding),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let cardWidth = metrics.cardWidth(for: .movie)
        let count = 4

        for _ in 0..<count {
            let card = UIView()
            card.layer.cornerRadius = metrics.cardCornerRadius
            card.layer.cornerCurve = .continuous
            card.clipsToBounds = true
            card.backgroundColor = UIColor.white.withAlphaComponent(0.08)
            card.translatesAutoresizingMaskIntoConstraints = false
            card.widthAnchor.constraint(equalToConstant: cardWidth).isActive = true

            let shimmer = CABasicAnimation(keyPath: "opacity")
            shimmer.fromValue = 0.3
            shimmer.toValue = 0.8
            shimmer.duration = 0.9
            shimmer.autoreverses = true
            shimmer.repeatCount = .infinity
            shimmer.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            card.layer.add(shimmer, forKey: "shimmer")

            stack.addArrangedSubview(card)
            cards.append(card)
        }
    }
}
