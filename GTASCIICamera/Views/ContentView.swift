//
//  ContentView.swift
//  GT ASCII Camera
//
//  Created by Gennaro Eduardo Tangari on 27/02/2026.
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var settings: SettingsManager

    @State private var showPermissionView = true

    var body: some View {
        Group {
            if showPermissionView && (!cameraManager.isCameraAuthorized) {
                PermissionView()
            } else {
                CameraView()
            }
        }
        .task {
            await cameraManager.checkAuthorization()
            if cameraManager.isCameraAuthorized {
                showPermissionView = false
            }
        }
        .onChange(of: cameraManager.isCameraAuthorized) { _, authorized in
            if authorized {
                showPermissionView = false
            }
        }
    }
}
