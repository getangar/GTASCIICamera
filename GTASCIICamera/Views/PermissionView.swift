//
//  PermissionView.swift
//  GT ASCII Camera
//
//  Created by Gennaro Tocco
//

import SwiftUI

/// Displayed when camera permission has not yet been granted.
/// Follows iOS design conventions with a clear call-to-action.
struct PermissionView: View {
    @EnvironmentObject var cameraManager: CameraManager

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon / illustration
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 80, weight: .thin))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .repeating)

            VStack(spacing: 12) {
                Text("permission_title")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("permission_message")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                Task {
                    await cameraManager.checkAuthorization()
                    if !cameraManager.isCameraAuthorized {
                        // If still denied, open Settings
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            await UIApplication.shared.open(url)
                        }
                    }
                }
            } label: {
                Text("permission_button")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .padding(.horizontal, 48)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
