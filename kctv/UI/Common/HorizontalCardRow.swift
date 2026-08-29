import UIKit

/// Yatay kart şeridi. Detay ekranındaki bölümler, fragmanlar ve oyuncular
/// aynı düzeni paylaşıyor: sabit genişlikte kartlar, tek satır, yatay kaydırma.
///
/// `HorizontalPosterRow`'dan ayrı duruyor çünkü orası yalnızca afiş kartı
/// çiziyor; burada hücreyi çağıran dolduruyor.
final class HorizontalCardRow<Cell: UICollectionViewCell, Value>: UIView,
    UICollectionViewDataSource, UICollectionViewDelegate {

    private let values: [Value]
    private let cardSize: CGSize
    private let spacing: CGFloat
    private let configureCell: (Cell, Value) -> Void
    private let onSelect: ((Value, UIView?) -> Void)?

    private var collectionView: UICollectionView!

    init(
        values: [Value],
        cardSize: CGSize,
        spacing: CGFloat,
        contentInset: CGFloat,
        reuseID: String,
        configureCell: @escaping (Cell, Value) -> Void,
        onSelect: ((Value, UIView?) -> Void)? = nil
    ) {
        self.values = values
        self.cardSize = cardSize
        self.spacing = spacing
        self.configureCell = configureCell
        self.onSelect = onSelect
        super.init(frame: .zero)
        build(contentInset: contentInset, reuseID: reuseID)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var reuseID = ""

    private func build(contentInset: CGFloat, reuseID: String) {
        self.reuseID = reuseID

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = spacing
        layout.itemSize = cardSize
        layout.sectionInset = UIEdgeInsets(top: 0, left: contentInset, bottom: 0, right: contentInset)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.applyNativeScrollEdges()
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(Cell.self, forCellWithReuseIdentifier: reuseID)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        // Odaklanan kart kendi çerçevesinin dışına büyüyor.
        #if os(tvOS)
        collectionView.clipsToBounds = false
        #endif
        addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(equalToConstant: cardSize.height),
        ])
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        values.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: reuseID, for: indexPath
        ) as! Cell
        configureCell(cell, values[indexPath.item])
        return cell
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
        onSelect?(values[indexPath.item], collectionView.cellForItem(at: indexPath))
    }
}
