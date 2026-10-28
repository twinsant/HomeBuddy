//
//  HomeBuddyApp.swift
//  HomeBuddy
//
//  Created by Atman An on 2026/8/26.
//

import SwiftUI
import SwiftData
import Darwin

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    var locale: Locale {
        self == .system ? .current : Locale(identifier: rawValue)
    }
}

enum AppLocalization {
    private static let languageKey = "preferredAppLanguage"
    private static let englishBundle: Bundle = {
        guard let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }()

    static var locale: Locale {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: languageKey) ?? "")?.locale ?? .current
    }

    static func string(_ key: String) -> String {
        let choice = AppLanguage(rawValue: UserDefaults.standard.string(forKey: languageKey) ?? "") ?? .system
        if choice == .simplifiedChinese || (choice == .system && Locale.current.language.languageCode?.identifier == "zh") {
            return key
        }
        return englishBundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func localizedString(_ key: String, comment: String = "") -> String {
        string(key)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }
}

@main
struct HomeBuddyApp: App {
    @AppStorage("preferredAppLanguage") private var preferredAppLanguage = AppLanguage.system.rawValue

    init() {
        // Avoid ggml Metal residency-set teardown asserting during process exit.
        setenv("GGML_METAL_NO_RESIDENCY", "1", 1)

        // Create the metadata cache before the first photo is opened.
        _ = PhotoMetadataCache.shared
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, selectedLocale)
        }
        .modelContainer(sharedModelContainer)

        Settings {
            SettingsView()
                .environment(\.locale, selectedLocale)
        }
    }

    private var selectedLocale: Locale {
        AppLanguage(rawValue: preferredAppLanguage)?.locale ?? .current
    }
}
