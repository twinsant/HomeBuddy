//
//  HomeBuddyApp.swift
//  HomeBuddy
//
//  Created by Atman An on 2026/8/26.
//

import SwiftUI
import SwiftData
import Darwin

@main
struct HomeBuddyApp: App {
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
        }
        .modelContainer(sharedModelContainer)
        .windowToolbarStyle(.unified(showsTitle: false))

        Settings {
            SettingsView()
        }
    }
}
