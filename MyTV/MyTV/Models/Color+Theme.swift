import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Color {
    /// Uygulama ana marka rengi (#AEFF23)
    public static let brandPrimary = Color(red: 174 / 255.0, green: 255 / 255.0, blue: 35 / 255.0)

    public init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#if canImport(UIKit)
extension UIColor {
    /// Uygulama ana marka rengi (#AEFF23)
    public static let brandPrimary = UIColor(red: 174 / 255.0, green: 255 / 255.0, blue: 35 / 255.0, alpha: 1.0)
}
#endif

