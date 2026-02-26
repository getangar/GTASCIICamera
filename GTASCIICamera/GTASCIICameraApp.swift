//
//  GTASCIICameraApp.swift
//  GT ASCII Camera
//
//  Created by Gennaro Tocco
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
