//
//  CameraView.swift
//  GT ASCII Camera
//
//  Created by Gennaro Tocco
//
//  Main camera interface designed to feel familiar to iOS Camera app users.
//  Features:
//    - Full-screen ASCII art viewfinder (Metal-rendered)
//    - Mode selector (Photo / Video) with swipe gesture
//    - Shutter button with recording state
//    - Camera flip, settings, and gallery access
//    - Palette quick-switch
//

import SwiftUI
import Photos

struct CameraView: View {
    @EnvironmentObject var cameraManager: CameraManager
    @EnvironmentObject var settings: SettingsManager

    @State private var renderer: ASCIIMetalRenderer?
    @State private var showSettings = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showSavedConfirmation = false
    @State private var lastThumbnail: UIImage?
    @State private var animateShutter = false
    @State private var showRecordingIndicator = false

    // Haptic feedback generators
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationFeedback = UINotificationFeedbackGenerator()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top bar
                    topBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    // ASCII Art Viewfinder
                    viewfinder
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)

                    Spacer(minLength: 8)

                    // Mode selector
                    modeSelector
                        .padding(.bottom, 12)

                    // Bottom controls
                    bottomControls
                        .padding(.horizontal, 32)
                        .padding(.bottom, 16)
                }
                .padding(.top, geometry.safeAreaInsets.top > 0 ? 0 : 8)

                // Shutter flash effect
                if animateShutter {
                    Color.white
                        .ignoresSafeArea()
                        .opacity(0.6)
                        .allowsHitTesting(false)
                }

                // Saved confirmation
                if showSavedConfirmation {
                    savedConfirmationOverlay
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .statusBarHidden(true)
        .onAppear {
            setupRenderer()
            cameraManager.configureSession(useFrontCamera: settings.useFrontCamera)
            cameraManager.startSession()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showShareSheet) {
            if !shareItems.isEmpty {
                ShareSheet(items: shareItems)
            }
        }
        .alert(
            String(localized: "error_title", defaultValue: "Error"),
            isPresented: $cameraManager.showError
        ) {
            Button(String(localized: "ok", defaultValue: "OK"), role: .cancel) {}
        } message: {
            Text(cameraManager.errorMessage ?? "")
        }
    }

    // MARK: - Setup

    private func setupRenderer() {
        if renderer == nil {
            renderer = ASCIIMetalRenderer()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Settings button
            Button {
                impactLight.impactOccurred()
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            // Recording indicator
            if cameraManager.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .opacity(showRecordingIndicator ? 1 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                            value: showRecordingIndicator
                        )

                    Text(formattedDuration(cameraManager.recordingDuration))
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.red.opacity(0.3))
                .clipShape(Capsule())
                .onAppear { showRecordingIndicator = true }
                .onDisappear { showRecordingIndicator = false }
            }

            Spacer()

            // Palette quick switch
            Button {
                impactLight.impactOccurred()
                withAnimation(.spring(response: 0.3)) {
                    settings.selectedPalette = settings.selectedPalette == .classic ? .unicode : .classic
                }
            } label: {
                Text(settings.selectedPalette == .classic ? "ABC" : "░▒▓")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Viewfinder

    private var viewfinder: some View {
        Group {
            if let renderer = renderer {
                MetalASCIIView(
                    renderer: renderer,
                    cameraManager: cameraManager,
                    settings: settings
                )
            } else {
                Rectangle()
                    .fill(Color.black)
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
    }

    // MARK: - Mode Selector

    private var modeSelector: some View {
        HStack(spacing: 24) {
            ForEach(CaptureMode.allCases) { mode in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        cameraManager.captureMode = mode
                    }
                    impactLight.impactOccurred()
                } label: {
                    Text(mode.displayName.uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(cameraManager.captureMode == mode ? .yellow : .white.opacity(0.6))
                }
            }
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(alignment: .center) {
            // Gallery thumbnail / last capture
            galleryButton
                .frame(width: 60, height: 60)

            Spacer()

            // Shutter button
            shutterButton
                .frame(width: 76, height: 76)

            Spacer()

            // Camera flip
            Button {
                impactLight.impactOccurred()
                withAnimation(.spring(response: 0.3)) {
                    settings.useFrontCamera.toggle()
                    cameraManager.switchCamera()
                }
            } label: {
                Image(systemName: "camera.rotate.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(.white.opacity(0.15))
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Shutter Button

    private var shutterButton: some View {
        Button {
            handleShutterPress()
        } label: {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 76, height: 76)

                // Inner circle
                Group {
                    if cameraManager.captureMode == .video {
                        if cameraManager.isRecording {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.red)
                                .frame(width: 30, height: 30)
                        } else {
                            Circle()
                                .fill(.red)
                                .frame(width: 64, height: 64)
                        }
                    } else {
                        Circle()
                            .fill(.white)
                            .frame(width: 64, height: 64)
                    }
                }
                .animation(.spring(response: 0.25), value: cameraManager.isRecording)
            }
        }
    }

    // MARK: - Gallery Button

    private var galleryButton: some View {
        Button {
            if let image = lastThumbnail ?? cameraManager.lastCapturedImage {
                shareItems = [image]
                showShareSheet = true
            }
        } label: {
            Group {
                if let thumbnail = lastThumbnail ?? cameraManager.lastCapturedImage {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.white.opacity(0.3), lineWidth: 1.5)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.1))
                        .frame(width: 52, height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.white.opacity(0.3), lineWidth: 1.5)
                        )
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.5))
                        }
                }
            }
        }
    }

    // MARK: - Saved Confirmation Overlay

    private var savedConfirmationOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(String(localized: "saved_confirmation", defaultValue: "Saved to Photos"))
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(.bottom, 120)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .allowsHitTesting(false)
    }

    // MARK: - Actions

    private func handleShutterPress() {
        switch cameraManager.captureMode {
        case .photo:
            impactHeavy.impactOccurred()
            // Flash animation
            withAnimation(.easeOut(duration: 0.15)) {
                animateShutter = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeIn(duration: 0.1)) {
                    animateShutter = false
                }
            }
            cameraManager.capturePhoto()
            notificationFeedback.notificationOccurred(.success)

            // Show confirmation
            withAnimation(.spring()) {
                showSavedConfirmation = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    showSavedConfirmation = false
                }
            }

        case .video:
            if cameraManager.isRecording {
                // Stop recording
                impactHeavy.impactOccurred()
                Task {
                    if let url = await cameraManager.stopRecording() {
                        // Save to library
                        let saved = await cameraManager.saveVideoToLibrary(url: url)

                        // Also make available for sharing
                        shareItems = [url]

                        if saved {
                            notificationFeedback.notificationOccurred(.success)
                            withAnimation(.spring()) {
                                showSavedConfirmation = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation {
                                    showSavedConfirmation = false
                                }
                            }
                        }
                    }
                }
            } else {
                // Start recording
                impactHeavy.impactOccurred()
                let size = CGSize(
                    width: CGFloat(renderer?.outputWidth ?? 1080),
                    height: CGFloat(renderer?.outputHeight ?? 1920)
                )
                cameraManager.startRecording(size: size)
            }
        }
    }

    // MARK: - Helpers

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
