//
//  vidajaryApp.swift
//  vidajary
//
//  Created by Vacuumlabs on 09/04/2026.
//

import SwiftUI
import SwiftData

@main
struct VidajaryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Project.self, Clip.self])
    }
}
