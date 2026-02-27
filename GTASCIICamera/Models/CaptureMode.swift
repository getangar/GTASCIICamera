//
//  CaptureMode.swift
//  GT ASCII Camera
//
//  Created by Gennaro Eduardo Tangari on 27/02/2026.
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation

/// The current capture mode, mirroring the native Camera app's photo/video toggle.
enum CaptureMode: String, CaseIterable, Identifiable {
    case photo
    case video

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .photo:
            return String(localized: "mode_photo", defaultValue: "Photo")
        case .video:
            return String(localized: "mode_video", defaultValue: "Video")
        }
    }

    var systemImageName: String {
        switch self {
        case .photo:
            return "camera.fill"
        case .video:
            return "video.fill"
        }
    }
}
