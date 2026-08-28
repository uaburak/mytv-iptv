import UIKit

extension UIViewController {
    /// Detay ekranını, dokunulan afişten büyüyerek açar.
    ///
    /// UIKit'in kendi zoom geçişi (Photos'un kullandığı) kesilebilir: animasyon
    /// sürerken etkileşim açık kalıyor ve kullanıcı ortasında parmağını basıp
    /// geçişi yakalayabiliyor. SwiftUI'ın `NavigationStack` sarmalayıcısı bu
    /// davranışı dışarı açmadığı için 866 ms boyunca bütün dokunmalar
    /// yutuluyordu — ölçüm bunu gösterdi, geçiş bu yüzden UIKit tarafında.
    func applyZoomTransition(from sourceView: UIView?) {
        #if os(iOS)
        guard let sourceView else { return }
        preferredTransition = .zoom { _ in sourceView }
        #endif
    }
}
