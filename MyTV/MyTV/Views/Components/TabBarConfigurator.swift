//
//  TabBarConfigurator.swift
//  MyTV
//
//  UITabBar'ı window view hiyerarşisinde bulup her UITabBarItem'a
//  image (outline) ve selectedImage (fill) set eder.
//  iOS liquid glass efekti bu iki variant arasında morph yapar.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Tab Tanımları
public enum AppTab: String, CaseIterable, Identifiable {
    case home      = "home"
    case favorites = "family"
    case playlists = "add"
    case search    = "analysis"
    case profile   = "setting"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home:      return "Anasayfa"
        case .favorites: return "Favoriler"
        case .playlists: return "Listeler"
        case .search:    return "Arama"
        case .profile:   return "Profil"
        }
    }

    public func iconName(isActive: Bool) -> String {
        "tab-\(rawValue)-\(isActive ? "fill" : "outline")"
    }
}

// MARK: - Tab Bar Item Konfigüratörü
public enum TabBarConfigurator {

    /// Tüm window'ları tarayarak UITabBar'ı bulur ve selectedImage set eder.
    /// Bulamazsa otomatik retry yapar (max 10 deneme).
    public static func configure(tabs: [AppTab], attempt: Int = 0) {
        #if canImport(UIKit) && !os(watchOS) && !os(tvOS)
        guard attempt < 10 else { return }

        let delay = attempt == 0 ? 0.2 : 0.4
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            for scene in UIApplication.shared.connectedScenes {
                guard let ws = scene as? UIWindowScene else { continue }
                for window in ws.windows {
                    if let tabBar = findTabBar(in: window) {
                        applyImages(to: tabBar, tabs: tabs)
                        return
                    }
                }
            }
            configure(tabs: tabs, attempt: attempt + 1)
        }
        #endif
    }

    #if canImport(UIKit) && !os(watchOS) && !os(tvOS)
    private static func applyImages(to tabBar: UITabBar, tabs: [AppTab]) {
        guard let items = tabBar.items else { return }

        for (index, tab) in tabs.enumerated() where index < items.count {
            items[index].image = UIImage(named: tab.iconName(isActive: false))?
                .withRenderingMode(.alwaysTemplate)
            items[index].selectedImage = UIImage(named: tab.iconName(isActive: true))?
                .withRenderingMode(.alwaysTemplate)
        }
    }

    private static func findTabBar(in view: UIView) -> UITabBar? {
        if let tabBar = view as? UITabBar { return tabBar }
        for sub in view.subviews {
            if let found = findTabBar(in: sub) { return found }
        }
        return nil
    }
    #endif
}
