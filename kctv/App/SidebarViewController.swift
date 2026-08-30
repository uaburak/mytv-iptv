#if os(tvOS)
import UIKit

/// Apple TV kabuğu.
///
/// Ekranda sürekli duran bir menü yok: içerik kenardan kenara. Bulunduğun
/// bölümün adı sol üstte, yalnızca sayfanın en üstündeyken duruyor; aşağı
/// inildiğinde kayboluyor. Menü, odak en sola geldiğinde cam bir panel olarak
/// içeriğin üstüne geliyor ve bir seçim yapılınca kapanıyor — sistem
/// uygulamalarının deseni bu.
///
/// Menünün açılmasını sol kenardaki görünmez ama odaklanabilir bir şerit
/// tetikliyor: odak motoru "bir yönde gidecek bir şey yoksa" haber vermiyor,
/// dolayısıyla kenara dayanmayı yakalamanın tek yolu oraya odaklanabilir bir
/// şey koymak.
final class SidebarViewController: UIViewController {
    private static let panelWidth: CGFloat = 320
    private static let panelInset: CGFloat = 24
    private static let itemSpacing: CGFloat = 4
    /// Sol kenardaki tetikleyici şerit. Görünmez; yalnızca odak için var.
    private static let edgeTriggerWidth: CGFloat = 24

    private let model: AppModel
    private let destinations = AppDestination.sidebar

    private let contentContainer = UIView()
    private let dimView = UIView()
    private let edgeTrigger = SidebarEdgeTrigger()
    private let sectionChip = SectionChipView()

    private var panel: UIVisualEffectView!
    private let menuStack = UIStackView()
    private let profileButton = SidebarProfileButton()

    private var items: [AppDestination: SidebarItemView] = [:]
    /// Ekranlar bir kez kuruluyor; bölüme dönen kullanıcı kaldığı kaydırma
    /// konumunu ve navigasyon yığınını buluyor.
    private var controllers: [AppDestination: UINavigationController] = [:]

    private var selected: AppDestination = .home
    private var isPanelOpen = false
    private var scrollObservation: NSKeyValueObservation?
    private var rightPressRecognizer: UITapGestureRecognizer?
    private var rightSwipeRecognizer: UISwipeGestureRecognizer?
    private var menuPressRecognizer: UITapGestureRecognizer?

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        scrollObservation?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppPalette.background
        buildLayout()
        setupRemoteInteractions()
        select(selected, closingPanel: false)

        NotificationCenter.default.addObserver(
            self, selector: #selector(languageDidChange), name: .appLanguageDidChange, object: nil
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // İlk açılışta odağın yanlışlıkla sol şeride veya rozete düşüp menüyü kendiliğinden
        // açmasını engellemek için tetikleyiciler ancak içerik ekrana yerleştikten sonra devreye girer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.isPanelOpen else { return }
            self.edgeTrigger.isArmed = true
            self.sectionChip.isArmed = true
        }
    }

    private func setupRemoteInteractions() {
        // Sağ yön tuşuna basıldığında (ekranda sağ tarafta odaklanacak bir buton olmasa bile)
        // sidebar'ın anında kapanmasını ve odağın içeriğe dönmesini sağlar.
        let rightPress = UITapGestureRecognizer(target: self, action: #selector(handleRightAction))
        rightPress.allowedPressTypes = [NSNumber(value: UIPress.PressType.rightArrow.rawValue)]
        rightPress.delegate = self
        view.addGestureRecognizer(rightPress)
        self.rightPressRecognizer = rightPress

        // Sağa kaydırma yapıldığında sidebar'ı kapatır.
        let rightSwipe = UISwipeGestureRecognizer(target: self, action: #selector(handleRightAction))
        rightSwipe.direction = .right
        rightSwipe.delegate = self
        view.addGestureRecognizer(rightSwipe)
        self.rightSwipeRecognizer = rightSwipe

        // Menü tuşuna basıldığında açık olan sidebar'ı kapatır.
        let menuPress = UITapGestureRecognizer(target: self, action: #selector(handleMenuAction))
        menuPress.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        menuPress.delegate = self
        view.addGestureRecognizer(menuPress)
        self.menuPressRecognizer = menuPress
    }

    @objc private func languageDidChange() {
        for destination in destinations {
            items[destination]?.title = destination.title
        }
        sectionChip.configure(symbol: selected.symbol, title: selected.title)
    }

    // MARK: - Kurulum

    private func buildLayout() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)

        dimView.backgroundColor = .black
        dimView.alpha = 0
        dimView.isUserInteractionEnabled = false
        dimView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimView)

        sectionChip.onFocus = { [weak self] in
            // Her ekranda ve sekmede (detay dahil) rozetin üzerine gelindiği an sidebar açılır
            self?.openPanel()
        }
        sectionChip.onSelect = { [weak self] in
            self?.openPanel()
        }
        sectionChip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sectionChip)

        edgeTrigger.onFocus = { [weak self] in self?.openPanel() }
        edgeTrigger.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(edgeTrigger)

        buildPanel()

        // İçerikten yukarı / sol üste çıkıldığında odağın sectionChip'e rahatça geçebilmesi için kılavuz
        let chipFocusGuide = UIFocusGuide()
        view.addLayoutGuide(chipFocusGuide)

        NSLayoutConstraint.activate([
            // İçerik kenardan kenara: banner ve afişler menü için yer
            // bırakmıyor, menü zaten ekranda durmuyor.
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sectionChip.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: Self.panelInset
            ),
            sectionChip.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.panelInset),

            chipFocusGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chipFocusGuide.trailingAnchor.constraint(equalTo: sectionChip.trailingAnchor, constant: 120),
            chipFocusGuide.topAnchor.constraint(equalTo: view.topAnchor),
            chipFocusGuide.bottomAnchor.constraint(equalTo: sectionChip.bottomAnchor, constant: 60),

            edgeTrigger.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            edgeTrigger.topAnchor.constraint(equalTo: view.topAnchor),
            edgeTrigger.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            edgeTrigger.widthAnchor.constraint(equalToConstant: Self.edgeTriggerWidth),

            // Panel ekran yüksekliğince ve dört yanında **aynı** pay var:
            // güvenli alana değil ekranın kendi kenarlarına ölçülüyor.
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.panelInset),
            panel.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.panelInset),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Self.panelInset),
            panel.widthAnchor.constraint(equalToConstant: Self.panelWidth),
        ])
        chipFocusGuide.preferredFocusEnvironments = [sectionChip]
    }

    private func buildPanel() {
        // Profil de bir satır: ayarlara açılıyor ve menü öğeleriyle aynı
        // yükseklikte (68pt), ancak büyük avatar için daha az iç boşluk kullanıyor.
        profileButton.onSelect = { [weak self] in self?.select(.settings, closingPanel: true) }

        menuStack.axis = .vertical
        menuStack.spacing = Self.itemSpacing
        menuStack.alignment = .fill

        // Ayarlar hariç üst menü öğeleri
        let topDestinations = destinations.filter { $0 != .settings }
        for destination in topDestinations {
            let item = SidebarItemView()
            item.symbol = destination.symbol
            item.title = destination.title
            item.onSelect = { [weak self] in self?.select(destination, closingPanel: true) }
            items[destination] = item
            menuStack.addArrangedSubview(item)
        }

        // Ayarlar en altta yer alacak
        let settingsItem = SidebarItemView()
        settingsItem.symbol = AppDestination.settings.symbol
        settingsItem.title = AppDestination.settings.title
        settingsItem.onSelect = { [weak self] in self?.select(.settings, closingPanel: true) }
        items[.settings] = settingsItem

        // Panel ekran boyu olduğu için alttaki artan yeri bu boşluk yutuyor;
        // ayarlar butonunu en alta iter.
        let filler = UIView()
        filler.setContentHuggingPriority(.init(1), for: .vertical)
        filler.setContentCompressionResistancePriority(.init(1), for: .vertical)

        let content = UIStackView(arrangedSubviews: [profileButton, menuStack, filler, settingsItem])
        content.axis = .vertical
        content.spacing = 16
        content.setCustomSpacing(20, after: profileButton)
        content.isLayoutMarginsRelativeArrangement = true
        content.insetsLayoutMarginsFromSafeArea = false
        // Dört kenar payı da eşit: sol, üst, alt ve sağ 24pt
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: Self.panelInset,
            leading: Self.panelInset,
            bottom: Self.panelInset,
            trailing: Self.panelInset
        )

        // Panelin zemini uygulamanın her yerindeki cam malzeme.
        panel = UIView.glassSurface(wrapping: content, cornerRadius: 34, interactive: false)
        // Odaklanan satır kendi çerçevesinin dışına büyüyor.
        panel.clipsToBounds = false
        panel.contentView.clipsToBounds = false
        panel.isHidden = true
        view.addSubview(panel)
    }

    // MARK: - Bölüm seçimi

    private func select(_ destination: AppDestination, closingPanel: Bool) {
        let controller: UINavigationController
        if let existing = controllers[destination] {
            controller = existing
        } else {
            controller = UINavigationController.app(root: destination.makeViewController(model: model))
            controller.delegate = self
            controllers[destination] = controller
        }

        if selected != destination || children.isEmpty {
            let previousController = children.first as? UINavigationController
            if let previous = previousController, previous !== controller {
                previous.willMove(toParent: nil)
                addChild(controller)
                controller.view.translatesAutoresizingMaskIntoConstraints = false

                // Sayfa geçişlerinde 300ms yumuşak dissolve animasyonu
                UIView.transition(
                    with: contentContainer,
                    duration: 0.3,
                    options: [.transitionCrossDissolve, .allowUserInteraction]
                ) {
                    previous.view.removeFromSuperview()
                    self.contentContainer.addSubview(controller.view)
                    NSLayoutConstraint.activate([
                        controller.view.leadingAnchor.constraint(equalTo: self.contentContainer.leadingAnchor),
                        controller.view.trailingAnchor.constraint(equalTo: self.contentContainer.trailingAnchor),
                        controller.view.topAnchor.constraint(equalTo: self.contentContainer.topAnchor),
                        controller.view.bottomAnchor.constraint(equalTo: self.contentContainer.bottomAnchor),
                    ])
                    self.contentContainer.layoutIfNeeded()
                } completion: { _ in
                    previous.removeFromParent()
                    controller.didMove(toParent: self)
                }
            } else if children.isEmpty {
                addChild(controller)
                controller.view.translatesAutoresizingMaskIntoConstraints = false
                contentContainer.addSubview(controller.view)
                NSLayoutConstraint.activate([
                    controller.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                    controller.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                    controller.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                    controller.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
                ])
                controller.didMove(toParent: self)
            }
        }

        selected = destination
        for (key, item) in items {
            item.isCurrent = key == destination
        }
        sectionChip.configure(symbol: destination.symbol, title: destination.title)

        // Yeni bölüm önce yerleşiyor: ölçüsü sıfır olan bir görünümde ne
        // odaklanacak bir şey var ne de bulunacak bir kaydırma görünümü.
        view.layoutIfNeeded()
        observeScroll(in: controller)

        guard closingPanel else { return }
        closePanel(returningFocusToContent: true)
    }

    // MARK: - Menü paneli

    private func openPanel() {
        guard !isPanelOpen else { return }
        isPanelOpen = true
        // Şerit veya rozet açıkken odaklanabilir kalırsa panelden sağa çıkmak yeniden
        // paneli açmasın.
        edgeTrigger.isArmed = false
        sectionChip.isArmed = false

        panel.isHidden = false
        panel.alpha = 1
        panel.transform = .identity
        dimView.alpha = 0.5
        sectionChip.alpha = 0
        updateAccount()

        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    private func closePanel(returningFocusToContent: Bool) {
        guard isPanelOpen else { return }
        isPanelOpen = false

        panel.alpha = 0
        panel.isHidden = true
        panel.transform = .identity
        dimView.alpha = 0
        sectionChip.alpha = 1

        // Tetikleyicileri hemen değil, odak yeni ekrana güvenle yerleştikten sonra devreye sokuyoruz.
        edgeTrigger.isArmed = false
        sectionChip.isArmed = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !self.isPanelOpen else { return }
            self.edgeTrigger.isArmed = true
            self.sectionChip.isArmed = true
        }

        guard returningFocusToContent else { return }
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    @objc private func handleRightAction() {
        guard isPanelOpen else { return }
        closePanel(returningFocusToContent: true)
    }

    @objc private func handleMenuAction() {
        guard !isPanelOpen else { return }

        // 1. Eğer navigation yığınında alt ekrandaysak (detay vb.), önce geri dön
        if let currentNav = children.first as? UINavigationController, currentNav.viewControllers.count > 1 {
            currentNav.popViewController(animated: true)
            return
        }

        // 2. Kök ekrandayız: Sayfanın neresinde olursak olalım önce en tepeye yumuşak bir animasyonla scroll at
        if let currentVC = (children.first as? UINavigationController)?.topViewController {
            if Self.scrollToTop(in: currentVC) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    currentVC.setNeedsFocusUpdate()
                    currentVC.updateFocusIfNeeded()
                    self?.setNeedsFocusUpdate()
                    self?.updateFocusIfNeeded()
                }
                return
            }
        }

        // 3. Zaten sayfanın en tepesindeyiz: Bir kez daha geri tuşuna basılınca sidebar açılır
        openPanel()
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if isPanelOpen {
            for press in presses {
                if press.type == .rightArrow {
                    closePanel(returningFocusToContent: true)
                    return
                }
                // Sidebar açıkken Menu tuşuna basıldığında müdahale edilmez;
                // sistem uygulamadan doğrudan çıkar.
            }
        }
        super.pressesEnded(presses, with: event)
    }

    private func updateAccount() {
        profileButton.configure(
            name: model.user?.displayName ?? L10n.guestUser,
            photoURL: model.user?.photoURL
        )
    }

    // MARK: - Odak

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if isPanelOpen, let item = items[selected] {
            return [item]
        }
        if let current = children.first {
            return [current]
        }
        return super.preferredFocusEnvironments
    }

    /// Sidebar açıkken en üstte yukarı basıldığında veya en altta aşağı basıldığında
    /// odak panelin dışına kaçıp menüyü kapatmasın. Odak panelden yalnızca sağa doğru çıkabilir.
    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
        if isPanelOpen {
            if let prev = context.previouslyFocusedView, prev.isDescendant(of: panel),
               let next = context.nextFocusedView, !next.isDescendant(of: panel) {
                // Sadece sağa kaydırma / sağ yön tuşu ile çıkışa izin verilir
                if context.focusHeading.contains(.right) {
                    return true
                }
                // Yukarı, aşağı veya sola basıldığında sidebar içinde kalınır
                return false
            }
        }
        return super.shouldUpdateFocus(in: context)
    }

    /// Odak sağa basılarak panelin dışına çıktığı anda menü kapanır.
    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        guard isPanelOpen else { return }
        // Menü yalnızca odak panelin İÇİNDEN dışarıya çıktığı zaman kapanmalıdır
        guard let prev = context.previouslyFocusedView, prev.isDescendant(of: panel) else { return }
        guard let next = context.nextFocusedView, next !== edgeTrigger, next !== sectionChip, !next.isDescendant(of: sectionChip) else { return }
        guard !next.isDescendant(of: panel) else { return }
        closePanel(returningFocusToContent: false)
    }

    // MARK: - Bölüm rozeti

    /// Rozet sayfanın en üstündeyken (kök veya detay ekranı fark etmeksizin)
    /// görünür: aşağı kaydırıldığında içeriğin önünden çekilir.
    private func observeScroll(in controller: UINavigationController) {
        scrollObservation?.invalidate()
        scrollObservation = nil

        guard let scrollView = Self.findPrimaryScrollView(in: controller.view) else {
            sectionChip.isHidden = false
            return
        }
        scrollObservation = scrollView.observe(\.contentOffset, options: [.initial, .new]) {
            [weak self] scrollView, _ in
            MainActor.assumeIsolated {
                guard let shell = self else { return }
                shell.updateSectionChipVisibility(for: scrollView)
            }
        }
    }

    private func updateSectionChipVisibility(for scrollView: UIScrollView) {
        let top = -scrollView.adjustedContentInset.top
        sectionChip.isHidden = scrollView.contentOffset.y > top + 15
    }

    @discardableResult
    private static func scrollToTop(in viewController: UIViewController) -> Bool {
        guard let scrollView = findPrimaryScrollView(in: viewController.view) else { return false }

        let topOffset = -scrollView.adjustedContentInset.top
        // Eğer zaten en tepedeyse (tolerans: 10pt) scroll işlemi yapılmaz
        guard scrollView.contentOffset.y > topOffset + 10 else { return false }

        if let collectionView = scrollView as? UICollectionView {
            if collectionView.numberOfSections > 0 && collectionView.numberOfItems(inSection: 0) > 0 {
                // UICollectionView'da sayfanın en başındaki ilk öğeye yumuşak ve akıcı animasyonla kay
                collectionView.scrollToItem(
                    at: IndexPath(item: 0, section: 0),
                    at: .top,
                    animated: true
                )
            }
            collectionView.setContentOffset(
                CGPoint(x: -collectionView.adjustedContentInset.left, y: topOffset),
                animated: true
            )
        } else if let tableView = scrollView as? UITableView {
            if tableView.numberOfSections > 0 && tableView.numberOfRows(inSection: 0) > 0 {
                tableView.scrollToRow(
                    at: IndexPath(row: 0, section: 0),
                    at: .top,
                    animated: true
                )
            }
            tableView.setContentOffset(CGPoint(x: 0, y: topOffset), animated: true)
        } else {
            scrollView.setContentOffset(CGPoint(x: 0, y: topOffset), animated: true)
        }

        return true
    }

    private static func findPrimaryScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        // 1. Önce doğrudan alt görünümlere bak (ana koleksiyon doğrudan viewController.view altındadır)
        for subview in view.subviews {
            if let scrollView = subview as? UIScrollView {
                return scrollView
            }
        }
        // 2. Bulunamazsa derinlemesine ara
        for subview in view.subviews {
            if let found = findPrimaryScrollView(in: subview) {
                return found
            }
        }
        return nil
    }
}

extension SidebarViewController: UINavigationControllerDelegate {
    /// Yığın değişince rozet hem yeni ekranın kaydırmasını izler hem de
    /// detay ekranında bulunduğu bölümün adını ("‹ Diziler", "‹ Filmler") göstermeye devam eder.
    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        observeScroll(in: navigationController)
        if let scrollView = Self.findPrimaryScrollView(in: viewController.view) {
            updateSectionChipVisibility(for: scrollView)
        } else {
            sectionChip.isHidden = false
        }
    }
}

extension SidebarViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === rightPressRecognizer || gestureRecognizer === rightSwipeRecognizer {
            return isPanelOpen
        }
        if gestureRecognizer === menuPressRecognizer {
            // Sidebar açıkken menu yakalanmaz (sistem doğrudan uygulamadan çıkar)
            if isPanelOpen {
                return false
            }
            // Navigation yığınında geri dönülecek ekran varsa UIKit pop eder
            if let currentNav = children.first as? UINavigationController, currentNav.viewControllers.count > 1 {
                return false
            }
            return true
        }
        return true
    }
}

/// Sol kenardaki görünmez tetikleyici.
///
/// Odak motoru bir yönde gidecek öğe bulamadığında hiçbir bildirim vermiyor;
/// "en sola dayandım" bilgisini almanın tek yolu oraya odaklanabilir bir şey
/// koymak. Şerit saydam: kullanıcı onu görmüyor, yalnızca menünün açıldığını
/// görüyor.
private final class SidebarEdgeTrigger: UIView {
    var onFocus: (() -> Void)?
    var isArmed = false

    override var canBecomeFocused: Bool { isArmed }

    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        guard isFocused else { return }
        onFocus?()
    }
}

/// Sol üstteki bölüm rozeti: "‹ ⌂ Ana Sayfa", "‹ 🍿 Filmler", "‹ 📺 Diziler" vb.
///
/// Odaklanabilir — kumanda ile üstüne gelindiğinde kök ekranda sidebar'ı otomatik açar,
/// detay ekranında ise tıklandığında önceki ekrana ("‹ Diziler") geri döner.
private final class SectionChipView: FocusableControl {
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.left"))
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private var capsuleView: UIVisualEffectView!

    var onFocus: (() -> Void)?
    var onSelect: (() -> Void)?
    var isArmed = false

    override var canBecomeFocused: Bool { isArmed && alpha > 0.1 && !isHidden }
    override var focusScale: CGFloat { 1.06 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        chevron.tintColor = AppPalette.secondaryText
        chevron.preferredSymbolConfiguration = symbolConfiguration
        chevron.contentMode = .center

        iconView.tintColor = AppPalette.primaryText
        iconView.preferredSymbolConfiguration = symbolConfiguration
        iconView.contentMode = .center

        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = AppPalette.primaryText

        let capsuleContent = UIStackView(arrangedSubviews: [iconView, titleLabel])
        capsuleContent.axis = .horizontal
        capsuleContent.alignment = .center
        capsuleContent.spacing = 12
        capsuleContent.isLayoutMarginsRelativeArrangement = true
        // Panelde olduğu gibi: güvenli alan payı kenar boşluğuna eklenmemeli.
        capsuleContent.insetsLayoutMarginsFromSafeArea = false
        capsuleContent.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 12, leading: 22, bottom: 12, trailing: 26
        )

        capsuleView = UIView.glassSurface(wrapping: capsuleContent, cornerRadius: 30)
        let row = UIStackView(arrangedSubviews: [chevron, capsuleView])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        addAction(UIAction { [weak self] _ in self?.onSelect?() }, for: .primaryActionTriggered)
    }

    override func applyFocusStyle(isFocused: Bool) {
        if isFocused {
            chevron.tintColor = .white
            iconView.tintColor = .white
            titleLabel.textColor = .white
        } else {
            chevron.tintColor = AppPalette.secondaryText
            iconView.tintColor = AppPalette.primaryText
            titleLabel.textColor = AppPalette.primaryText
        }
    }

    override func didUpdateFocus(
        in context: UIFocusUpdateContext,
        with coordinator: UIFocusAnimationCoordinator
    ) {
        super.didUpdateFocus(in: context, with: coordinator)
        if isFocused && isArmed {
            // Rozetin üstüne kumanda ile gelindiği anda işlem tetiklenir
            onFocus?()
        }
    }

    func configure(symbol: String, title: String) {
        iconView.image = UIImage(systemName: symbol)
        titleLabel.text = title
    }
}

/// Menü panelindeki tek satır: solda simge, yanında adı.
///
/// Odak ve seçim geri bildirimi uygulamanın çipleriyle aynı dili konuşuyor —
/// odaktaki satır dolu beyaz zemin + siyah yazı. Büyüme ve gölge
/// `FocusableControl`'den geliyor, animasyon ikinci kez yazılmıyor.
private final class SidebarItemView: FocusableControl {
    private let highlight = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    var onSelect: (() -> Void)?

    var symbol: String = "" {
        didSet { iconView.image = UIImage(systemName: symbol) }
    }

    var title: String = "" {
        didSet {
            titleLabel.text = title
            accessibilityLabel = title
        }
    }

    /// Seçili bölüm; odaktan bağımsız.
    var isCurrent = false {
        didSet { applyFocusStyle(isFocused: isFocused) }
    }

    override var focusScale: CGFloat { 1.03 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        highlight.layer.cornerRadius = SidebarRowGeometry.itemHeight / 2
        highlight.layer.cornerCurve = .continuous
        highlight.isUserInteractionEnabled = false
        highlight.translatesAutoresizingMaskIntoConstraints = false

        iconView.contentMode = .center
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 24, weight: .semibold
        )
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 26, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(highlight)
        addSubview(iconView)
        addSubview(titleLabel)

        addAction(UIAction { [weak self] _ in self?.onSelect?() }, for: .primaryActionTriggered)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: SidebarRowGeometry.itemHeight),

            highlight.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor),
            highlight.topAnchor.constraint(equalTo: topAnchor),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconView.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: SidebarRowGeometry.slotLeading
            ),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: SidebarRowGeometry.slotSize),
            iconView.heightAnchor.constraint(equalToConstant: SidebarRowGeometry.slotSize),

            titleLabel.leadingAnchor.constraint(
                equalTo: iconView.trailingAnchor, constant: SidebarRowGeometry.textGap
            ),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor, constant: -14
            ),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        applyFocusStyle(isFocused: false)
    }

    override func applyFocusStyle(isFocused: Bool) {
        if isFocused {
            highlight.backgroundColor = .white
            iconView.tintColor = .black
            titleLabel.textColor = .black
        } else if isCurrent {
            highlight.backgroundColor = AppPalette.elevated
            iconView.tintColor = AppPalette.primaryText
            titleLabel.textColor = AppPalette.primaryText
        } else {
            highlight.backgroundColor = .clear
            iconView.tintColor = AppPalette.secondaryText
            titleLabel.textColor = AppPalette.secondaryText
        }
    }
}

/// Menü satırlarının ve profil butonunun ortak ölçüleri.
private enum SidebarRowGeometry {
    /// Vurgu kapsülünün panel kenarına uzaklığı — iki yanda da aynı.
    static let pillInset: CGFloat = 20
    static let itemHeight: CGFloat = 68

    /// İkon ve avatar yuvasının sol kenar mesafesi
    static let slotLeading: CGFloat = 7
    /// İkon ve avatar yuvasının boyutu (ikon 54x54 alanın ortasında durur, avatar bu alanı doldurur)
    static let slotSize: CGFloat = 54
    /// Yuva ile metin arasındaki boşluk
    static let textGap: CGFloat = 14
}

/// Panelin en üstündeki profil satırı: avatar ve kullanıcı adı.
///
/// Menü butonlarıyla aynı geometriyi ve yuva ölçülerini paylaşır.
private final class SidebarProfileButton: FocusableControl {
    private let highlight = UIView()
    private let avatarView = RemoteImageView()
    private let nameLabel = UILabel()

    var onSelect: (() -> Void)?

    override var focusScale: CGFloat { 1.03 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        highlight.layer.cornerRadius = SidebarRowGeometry.itemHeight / 2
        highlight.layer.cornerCurve = .continuous
        highlight.isUserInteractionEnabled = false
        highlight.translatesAutoresizingMaskIntoConstraints = false

        avatarView.isCircular = true
        avatarView.clipsToBounds = true
        avatarView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(highlight)
        addSubview(avatarView)
        addSubview(nameLabel)

        addAction(UIAction { [weak self] _ in self?.onSelect?() }, for: .primaryActionTriggered)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: SidebarRowGeometry.itemHeight),

            highlight.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor),
            highlight.topAnchor.constraint(equalTo: topAnchor),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor),

            avatarView.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: SidebarRowGeometry.slotLeading
            ),
            avatarView.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: SidebarRowGeometry.slotSize),
            avatarView.heightAnchor.constraint(equalToConstant: SidebarRowGeometry.slotSize),

            nameLabel.leadingAnchor.constraint(
                equalTo: avatarView.trailingAnchor, constant: SidebarRowGeometry.textGap
            ),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor, constant: -14
            ),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        applyFocusStyle(isFocused: false)
    }

    func configure(name: String, photoURL: URL?) {
        nameLabel.text = name
        accessibilityLabel = name
        avatarView.configure(
            url: photoURL, title: name, displayWidth: SidebarRowGeometry.slotSize
        )
    }

    override func applyFocusStyle(isFocused: Bool) {
        highlight.backgroundColor = isFocused ? .white : .clear
        nameLabel.textColor = isFocused ? .black : AppPalette.primaryText
    }
}
#endif
