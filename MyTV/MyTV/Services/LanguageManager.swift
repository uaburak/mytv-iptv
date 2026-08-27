import SwiftUI
import Combine

public enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case turkish = "tr"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .turkish: return "Türkçe"
        }
    }
}

@MainActor
public final class LanguageManager: ObservableObject {
    public static let shared = LanguageManager()

    @AppStorage("appLanguage") public var currentLanguage: String = "en" {
        didSet {
            objectWillChange.send()
        }
    }

    public var isTurkish: Bool {
        currentLanguage == "tr"
    }

    private init() {}

    public func setLanguage(_ lang: AppLanguage) {
        self.currentLanguage = lang.rawValue
    }
}
