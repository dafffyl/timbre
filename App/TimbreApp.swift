//
//  TimbreApp.swift
//  Timbre
//
//  Created by David Fourneau on 26/08/2026.
//

import SwiftUI

@main
struct TimbreApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
