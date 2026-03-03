//
//  ZoomControlView.swift
//  GT ASCII Camera
//
//  Created by Gennaro Eduardo Tangari on 03/03/2026.
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import SwiftUI

/// Quick zoom buttons and slider for camera zoom control.
struct ZoomControlView: View {
    @EnvironmentObject var cameraManager: CameraManager
    
    @State private var showSlider = false
    @State private var sliderValue: Double = 1.0
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        VStack(spacing: 12) {
            // Quick zoom buttons
            HStack(spacing: 16) {
                ForEach(cameraManager.availableZoomFactors, id: \.self) { factor in
                    ZoomButton(
                        factor: factor,
                        isSelected: abs(cameraManager.currentZoomFactor - factor) < 0.1,
                        isRecording: cameraManager.isRecording,
                        action: {
                            impactLight.impactOccurred()
                            cameraManager.quickZoom(to: factor)
                        }
                    )
                }
            }
            
            // Recording warning
            if cameraManager.isRecording {
                Text("Digital zoom only while recording")
                    .font(.caption2)
                    .foregroundColor(.yellow.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.5))
                    .clipShape(Capsule())
            }
            
            // Zoom slider (appears on tap)
            if showSlider {
                VStack(spacing: 8) {
                    Slider(
                        value: $sliderValue,
                        in: Double(cameraManager.minZoomFactor)...Double(cameraManager.maxZoomFactor)
                    )
                    .tint(.yellow)
                    .frame(width: 200)
                    .onChange(of: sliderValue) { _, newValue in
                        cameraManager.setZoom(CGFloat(newValue), animated: false)
                    }
                    
                    Text(String(format: "%.1fx", cameraManager.currentZoomFactor))
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            sliderValue = Double(cameraManager.currentZoomFactor)
        }
        .onChange(of: cameraManager.currentZoomFactor) { _, newValue in
            sliderValue = Double(newValue)
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.3)) {
                showSlider.toggle()
            }
        }
    }
}

/// Individual zoom button (0.5x, 1x, 2x, etc.)
struct ZoomButton: View {
    let factor: CGFloat
    let isSelected: Bool
    let isRecording: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(formatZoomFactor(factor))
                .font(.system(size: 14, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundColor(isSelected ? .black : .white)
                .frame(minWidth: 44, minHeight: 32)
                .padding(.horizontal, 8)
                .background(isSelected ? .yellow : .white.opacity(0.2))
                .clipShape(Capsule())
        }
        .opacity(isRecording && !isSelected ? 0.5 : 1.0)
    }
    
    private func formatZoomFactor(_ factor: CGFloat) -> String {
        if factor < 1 {
            return String(format: ".%.1fx", factor).replacingOccurrences(of: "0.", with: ".")
        } else if factor.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(factor))x"
        } else {
            return String(format: "%.1fx", factor)
        }
    }
}

/// Pinch-to-zoom gesture overlay
struct PinchToZoomView: View {
    @EnvironmentObject var cameraManager: CameraManager
    
    @State private var lastScale: CGFloat = 1.0
    
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastScale
                        lastScale = value
                        cameraManager.adjustZoom(by: delta)
                    }
                    .onEnded { _ in
                        lastScale = 1.0
                    }
            )
    }
}
