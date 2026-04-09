//
//  vidajaryApp.swift
//  vidajary
//
//  Created by Vacuumlabs on 09/04/2026.
//

import SwiftUI
import SwiftData

@main
struct vidajaryApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Project.self, Clip.self])
    }
}
