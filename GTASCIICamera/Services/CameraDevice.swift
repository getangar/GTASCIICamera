//
//  CameraDevice.swift
//  GT ASCII Camera
//
//  Created by Gennaro Eduardo Tangari on 03/03/2026.
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import AVFoundation
import UIKit

/// Represents a physical camera device with its characteristics.
struct CameraDeviceInfo: Identifiable {
    let id: String
    let device: AVCaptureDevice
    let deviceType: AVCaptureDevice.DeviceType
    let position: AVCaptureDevice.Position
    let minZoomFactor: CGFloat
    let maxZoomFactor: CGFloat
    
    /// The "marketing" zoom level (e.g., 0.5x, 1x, 2x, 3x)
    var displayZoomFactor: CGFloat {
        switch deviceType {
        case .builtInUltraWideCamera:
            return 0.5
        case .builtInWideAngleCamera:
            return 1.0
        case .builtInTelephotoCamera:
            // Detect if this is a 2x or 3x telephoto
            // iPhone 15/16/17 Pro models typically have 3x telephoto (starts at ~3.0x)
            // Older models have 2x telephoto (starts at ~2.0x)
            // Check the minimum zoom factor to determine which type
            if device.minAvailableVideoZoomFactor >= 2.5 {
                return 3.0
            } else if device.minAvailableVideoZoomFactor >= 1.5 {
                return 2.0
            } else {
                // Fallback: check virtual device zoom capabilities
                return CGFloat(device.virtualDeviceSwitchOverVideoZoomFactors.first ?? 2.0)
            }
        case .builtInTripleCamera, .builtInDualCamera, .builtInDualWideCamera:
            return 1.0
        default:
            return 1.0
        }
    }
    
    var displayName: String {
        switch deviceType {
        case .builtInUltraWideCamera:
            return "Ultra Wide (0.5x)"
        case .builtInWideAngleCamera:
            return "Wide (1x)"
        case .builtInTelephotoCamera:
            // Dynamically show 2x or 3x based on actual zoom
            let zoomLevel = displayZoomFactor
            return "Telephoto (\(Int(zoomLevel))x)"
        case .builtInTripleCamera:
            return "Triple Camera"
        case .builtInDualCamera:
            return "Dual Camera"
        case .builtInDualWideCamera:
            return "Dual Wide"
        default:
            return "Camera"
        }
    }
}

/// Manages discovery and selection of available camera devices.
@MainActor
final class CameraDeviceManager: ObservableObject {
    
    @Published var availableDevices: [CameraDeviceInfo] = []
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var currentDevice: CameraDeviceInfo?
    
    private(set) var backDevices: [CameraDeviceInfo] = []
    private(set) var frontDevices: [CameraDeviceInfo] = []
    
    /// Discover all available camera devices for a given position.
    func discoverDevices(for position: AVCaptureDevice.Position) {
        // Only discover individual physical cameras, not virtual multi-camera devices
        // This allows us to control each lens separately
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInUltraWideCamera,
            .builtInWideAngleCamera,
            .builtInTelephotoCamera
        ]
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position
        )
        
        var devices: [CameraDeviceInfo] = []
        
        for device in discoverySession.devices {
            let info = CameraDeviceInfo(
                id: device.uniqueID,
                device: device,
                deviceType: device.deviceType,
                position: device.position,
                minZoomFactor: device.minAvailableVideoZoomFactor,
                maxZoomFactor: device.maxAvailableVideoZoomFactor
            )
            devices.append(info)
            
            // Debug logging
            print("📷 Found camera: \(info.displayName)")
            print("   Device Type: \(device.deviceType.rawValue)")
            print("   Display Zoom: \(info.displayZoomFactor)x")
            print("   Zoom Range: \(info.minZoomFactor)x - \(info.maxZoomFactor)x")
        }
        
        // Sort by display zoom factor for consistent ordering
        devices.sort { $0.displayZoomFactor < $1.displayZoomFactor }
        
        if position == .back {
            backDevices = devices
        } else {
            frontDevices = devices
        }
        
        availableDevices = devices
        
        print("📷 Total devices discovered for \(position == .back ? "back" : "front"): \(devices.count)")
        print("📷 Available zoom factors: \(availableZoomFactors(for: position))")
    }
    
    /// Get the preferred device for a given zoom level.
    /// This mimics the behavior of the native Camera app.
    func preferredDevice(forZoomFactor zoomFactor: CGFloat, position: AVCaptureDevice.Position) -> CameraDeviceInfo? {
        let devices = position == .back ? backDevices : frontDevices
        
        guard !devices.isEmpty else { return nil }
        
        // Find the best matching device based on zoom factor
        // Match to the closest available lens based on their native zoom levels
        
        var bestMatch: CameraDeviceInfo?
        var smallestDifference: CGFloat = .greatestFiniteMagnitude
        
        for device in devices {
            let difference = abs(device.displayZoomFactor - zoomFactor)
            if difference < smallestDifference {
                smallestDifference = difference
                bestMatch = device
            }
        }
        
        return bestMatch ?? devices.first
    }
    
    /// Get all distinct zoom factors available (for quick buttons)
    func availableZoomFactors(for position: AVCaptureDevice.Position) -> [CGFloat] {
        let devices = position == .back ? backDevices : frontDevices
        
        var factors = Set<CGFloat>()
        
        for device in devices {
            // Add the native zoom level for each lens
            factors.insert(device.displayZoomFactor)
        }
        
        // Add intermediate common zoom levels if supported by any device
        // For example, 3x if there's a telephoto that supports it
        for device in devices {
            if device.deviceType == .builtInTelephotoCamera {
                // Some telephoto lenses are 2x, others are 3x
                if device.displayZoomFactor >= 2.5 {
                    factors.insert(3.0)
                } else if device.displayZoomFactor >= 1.8 {
                    factors.insert(2.0)
                }
            }
            
            // Add 5x if any device can support it
            if device.maxZoomFactor >= 5.0 {
                factors.insert(5.0)
            }
        }
        
        return factors.sorted()
    }
}
