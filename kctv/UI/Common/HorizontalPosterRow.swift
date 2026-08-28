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

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        onSelect(items[indexPath.item], collectionView.cellForItem(at: indexPath))
    }
}
