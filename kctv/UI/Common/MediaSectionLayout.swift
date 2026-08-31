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

    /// Dikey kaydırılan afiş ızgarası: satıra sığdığı kadar kart, kalanı alt
    /// satıra. Kartlar arasındaki boşluk yatayda ve dikeyde **aynı**.
    static func posterGrid(
        kind: MediaKind,
        containerWidth: CGFloat,
        metrics: AppMetrics,
        showsHeader: Bool = false
    ) -> NSCollectionLayoutSection {
        let spacing = gridSpacing(metrics: metrics)
        let columns = gridColumns(kind: kind, containerWidth: containerWidth, metrics: metrics)
        let itemWidth = gridItemWidth(kind: kind, containerWidth: containerWidth, metrics: metrics)
        let itemHeight = itemWidth / kind.posterAspect

        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .absolute(itemWidth),
                heightDimension: .absolute(itemHeight)
            )
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(itemHeight)
            ),
            repeatingSubitem: item,
            count: columns
        )
        group.interItemSpacing = .fixed(spacing)

        let section = NSCollectionLayoutSection(group: group)
        // Dikey boşluk yatayla aynı: kartların arası her yönde eşit.
        section.interGroupSpacing = spacing
        section.contentInsets = NSDirectionalEdgeInsets(
            top: metrics.rowHeaderGap * 0.5,
            leading: metrics.screenPadding,
            bottom: metrics.rowSpacing * 0.5,
            trailing: metrics.screenPadding
        )
        if showsHeader {
            section.boundarySupplementaryItems = [rowHeader(metrics: metrics)]
        }
        return section
    }

    /// Kartlar arasındaki boşluk. tvOS'ta ray aralığından biraz daha geniş:
    /// odaklanan kart büyüyor, komşusuna yapışmamalı.
    static func gridSpacing(metrics: AppMetrics) -> CGFloat {
        #if os(tvOS)
        metrics.cardSpacing * 1.25
        #else
        metrics.cardSpacing
        #endif
    }

    /// Apple TV'de ekranın nokta cinsinden genişliği — 4K'da da 1920.
    /// Sütunun hedef genişliği buradan çıkıyor.
    private static let fullScreenWidth: CGFloat = 1920

    /// Izgaranın sütun sayısı.
    ///
    /// tvOS'ta sabit olan sütun sayısı değil, **kartın genişliği**. Tam ekran
    /// bir sayfada satıra yedi afiş (yatay 16:9 kartlarda dört) sığıyor; sabit
    /// yedi yazıldığında, solunda gömülü menü olan sayfalarda ızgaraya ~1390pt
    /// kalıyor ve aynı yedi sütuna bölününce kartlar yarı yarıya inceliyordu.
    /// Artık kart tam ekrandaki ölçüsünü koruyor, satıra kaç tane sığıyorsa o
    /// kadar sütun açılıyor — menülü sayfada beş.
    ///
    /// iOS'ta kart raylardaki ölçüsüne yakın kalıyor — iPhone'da üç sütun.
    static func gridColumns(
        kind: MediaKind,
        containerWidth: CGFloat,
        metrics: AppMetrics
    ) -> Int {
        #if os(tvOS)
        let spacing = gridSpacing(metrics: metrics)
        let fullScreenColumns: CGFloat = kind == .live ? 4 : 7
        let fullScreenAvailable = fullScreenWidth - metrics.screenPadding * 2
        let targetWidth =
            (fullScreenAvailable - spacing * (fullScreenColumns - 1)) / fullScreenColumns

        let available = max(containerWidth - metrics.screenPadding * 2, 1)
        let fitting = ((available + spacing) / (targetWidth + spacing)).rounded()
        return max(Int(fitting), 2)
        #else
        let available = max(containerWidth - metrics.screenPadding * 2, 1)
        let target = max(metrics.cardWidth(for: kind) + metrics.cardSpacing, 1)
        let fitting = Int((available + metrics.cardSpacing) / target)
        return min(max(fitting, kind == .live ? 2 : 3), 10)
        #endif
    }

    /// Bir sütunun genişliği. Artan yer sütunlara paylaştırılıyor.
    ///
    /// Hücreyi kuran taraf **aynı** genişliği kullanmak zorunda: düzen güvenli
    /// alan düşülmüş genişlikten, hücre `view.bounds.width`'ten hesaplayınca
    /// afiş hücresinden taşıyor ve alt satırdaki kartın üstüne biniyordu.
    static func gridItemWidth(
        kind: MediaKind,
        containerWidth: CGFloat,
        metrics: AppMetrics
    ) -> CGFloat {
        let available = max(containerWidth - metrics.screenPadding * 2, 1)
        let columns = CGFloat(gridColumns(kind: kind, containerWidth: containerWidth, metrics: metrics))
        return max((available - gridSpacing(metrics: metrics) * (columns - 1)) / columns, 1)
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
