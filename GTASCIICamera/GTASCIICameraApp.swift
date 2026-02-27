//
//  GTASCIICameraApp.swift
//  GT ASCII Camera
//
//  Created by Gennaro Eduardo Tangari on 27/02/2026.
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import SwiftUI

@main
struct GTASCIICameraApp: App {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var settingsManager = SettingsManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cameraManager)
                .environmentObject(settingsManager)
        }
    }
}
