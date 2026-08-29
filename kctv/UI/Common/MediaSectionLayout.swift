import UIKit

/// Ray düzenleri tek yerde.
///
/// Anasayfa, Film/Dizi gezinme ve detaydaki raylar aynı ölçülerle çiziliyor;
/// her ekran kendi bölümünü ayrı tanımladığında boşluklar ve başlık yükseklikleri
/// birbirinden ayrı düşüyordu.
enum MediaSectionLayout {
    /// Ray başlığı. Bölümün kendi girintisi zaten uygulandığı için burada
    /// tekrar verilmiyor; verilseydi başlık kartlardan iki kat içeri kayardı.
    static func rowHeader(metrics: AppMetrics) -> NSCollectionLayoutBoundarySupplementaryItem {
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(metrics.rowHeaderHeight)
            ),
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        header.contentInsets = .zero
        return header
    }

    /// Dikey afiş kartlı ray.
    static func posterRow(
        kind: MediaKind,
        metrics: AppMetrics,
        showsHeader: Bool = true
    ) -> NSCollectionLayoutSection {
        row(
            cardSize: CGSize(
                width: metrics.cardWidth(for: kind),
                height: metrics.rowItemHeight(for: kind)
            ),
            metrics: metrics,
            showsHeader: showsHeader
        )
    }

    /// Yatay (16:9) kartlı ray — bölümler ve "izlemeye devam et".
    static func clipRow(
        metrics: AppMetrics,
        showsHeader: Bool = true
    ) -> NSCollectionLayoutSection {
        let width = metrics.clipCardWidth
        return row(
            cardSize: CGSize(width: width, height: width * 9 / 16),
            metrics: metrics,
            showsHeader: showsHeader
        )
    }

    private static func row(
        cardSize: CGSize,
        metrics: AppMetrics,
        showsHeader: Bool
    ) -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(
            widthDimension: .absolute(cardSize.width),
            heightDimension: .absolute(cardSize.height)
        )
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = metrics.cardSpacing
        section.orthogonalScrollingBehavior = .continuous
        section.contentInsets = NSDirectionalEdgeInsets(
            top: showsHeader ? metrics.rowHeaderGap : 0,
            leading: metrics.screenPadding,
            bottom: metrics.rowSpacing * 0.5,
            trailing: metrics.screenPadding
        )
        if showsHeader {
            section.boundarySupplementaryItems = [rowHeader(metrics: metrics)]
        }
        return section
    }
}
