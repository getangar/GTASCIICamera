//
//  CameraManager.swift
//  GT ASCII Camera
//
//  Created by Gennaro Eduardo Tangari on 27/02/2026.
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
@preconcurrency import AVFoundation
import Combine
import UIKit
import Photos

/// Manages the AVFoundation capture session, providing real-time camera frames
/// and coordinating photo/video capture for the ASCII art pipeline.
@MainActor
final class CameraManager: NSObject, ObservableObject {
    
    // MARK: - Published State
    
    @Published var isSessionRunning = false
    @Published var isRecording = false
    @Published var captureMode: CaptureMode = .photo
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var lastCapturedImage: UIImage?
    @Published var recordingDuration: TimeInterval = 0
    @Published var isCameraAuthorized = false
    @Published var isMicrophoneAuthorized = false
    
    // MARK: - Zoom & Device Management
    
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var availableZoomFactors: [CGFloat] = [1.0]
    @Published var minZoomFactor: CGFloat = 1.0
    @Published var maxZoomFactor: CGFloat = 1.0
    
    let deviceManager = CameraDeviceManager()
    
    // MARK: - Capture Session
    
    nonisolated(unsafe) let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.gtasciicamera.session", qos: .userInteractive)
    nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private let audioOutput = AVCaptureAudioDataOutput()
    private var currentVideoInput: AVCaptureDeviceInput?
    
    // MARK: - Video Recording
    
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var recordingStartTime: CMTime?
    private var recordingURL: URL?
    private var recordingTimer: Timer?
    
    // MARK: - Frame Delivery
    
    /// Callback invoked on the session queue with each new video sample buffer.
    nonisolated(unsafe) var onNewFrame: ((CMSampleBuffer) -> Void)?
    
    /// Callback for delivering rendered frames during recording.
    var onRenderedFrame: ((CVPixelBuffer, CMTime) -> Void)?
    
    // MARK: - Configuration
    
    private var useFrontCamera = false
    private var isReconfiguring = false
    
    // MARK: - Lifecycle
    
    override init() {
        super.init()
    }
    
    // MARK: - Authorization
    
    func checkAuthorization() async {
        // Camera
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isCameraAuthorized = true
        case .notDetermined:
            isCameraAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            isCameraAuthorized = false
        }
        
        // Microphone
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            isMicrophoneAuthorized = true
        case .notDetermined:
            isMicrophoneAuthorized = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            isMicrophoneAuthorized = false
        }
    }
    
    // MARK: - Session Setup
    
    func configureSession(useFrontCamera: Bool = false) {
        // Prevent concurrent reconfigurations
        guard !isReconfiguring else {
            print("⚠️ Already reconfiguring session, ignoring request")
            return
        }
        
        self.useFrontCamera = useFrontCamera
        isReconfiguring = true
        
        // Always reconfigure on the session queue
        sessionQueue.async { [weak self] in
            guard let self else { return }
            
            // Stop the session if it's running
            let wasRunning = self.captureSession.isRunning
            if wasRunning {
                self.captureSession.stopRunning()
            }
            
            // Small delay to ensure session has fully stopped
            Thread.sleep(forTimeInterval: 0.1)
            
            // Reconfigure
            self.setupSessionOnQueue()
            
            // Restart if it was running before
            if wasRunning {
                self.captureSession.startRunning()
                Task { @MainActor in
                    self.isSessionRunning = true
                }
            }
            
            // Mark as done
            Task { @MainActor in
                self.isReconfiguring = false
            }
        }
    }
    
    nonisolated private func setupSessionOnQueue() {
        Task { @MainActor in
            self.setupSession()
        }
    }
    
    private func setupSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1920x1080
        
        // Make copies of inputs/outputs arrays before removing to avoid mutation during enumeration
        let currentInputs = captureSession.inputs
        let currentOutputs = captureSession.outputs
        
        // Removing current input and outputs
        currentInputs.forEach { captureSession.removeInput($0) }
        currentOutputs.forEach { captureSession.removeOutput($0) }
        
        // Discover available devices
        let position: AVCaptureDevice.Position = useFrontCamera ? .front : .back
        deviceManager.discoverDevices(for: position)
        
        // Get preferred device for current zoom (or default to first available)
        let preferredDevice = deviceManager.preferredDevice(
            forZoomFactor: currentZoomFactor,
            position: position
        )
        
        guard let deviceInfo = preferredDevice else {
            handleError("No camera available")
            captureSession.commitConfiguration()
            return
        }
        
        let videoDevice = deviceInfo.device
        
        // Update zoom constraints to reflect ALL available lenses
        // This allows continuous zoom across all physical cameras
        Task { @MainActor in
            let allDevices = position == .back ? deviceManager.backDevices : deviceManager.frontDevices
            
            // Find the absolute min/max across all lenses
            minZoomFactor = allDevices.map { $0.displayZoomFactor }.min() ?? 0.5
            maxZoomFactor = allDevices.map { $0.maxZoomFactor }.max() ?? 10.0
            
            availableZoomFactors = deviceManager.availableZoomFactors(for: position)
            deviceManager.currentDevice = deviceInfo
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
                currentVideoInput = videoInput
            }
            
            // When switching cameras, use the native 1.0x zoom of the new physical camera
            // The "logical" zoom (e.g., 0.5x for ultra wide) is represented by which camera we use
            try videoDevice.lockForConfiguration()
            videoDevice.videoZoomFactor = 1.0  // Always use native zoom on physical camera
            videoDevice.unlockForConfiguration()
            
            // Update the current zoom factor to reflect the display zoom
            Task { @MainActor in
                currentZoomFactor = deviceInfo.displayZoomFactor
            }
            
        } catch {
            handleError(error.localizedDescription)
            captureSession.commitConfiguration()
            return
        }
        
        // Configuring Video Output
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
                
        if let connection = videoOutput.connection(with: .video) {
            
            // Set the initial angle rotation
            let rotationAngle: CGFloat = 90
            
            if connection.isVideoRotationAngleSupported(rotationAngle) {
                connection.videoRotationAngle = rotationAngle
            }
            
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = useFrontCamera
            }
            
            // Correct the rotation in case of frontal camera
            if useFrontCamera && connection.isVideoRotationAngleSupported(0) {
                connection.videoRotationAngle = 0
            }
        }
        // --------------------------------------------------
        
        // Configuring Audio
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            do {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if captureSession.canAddInput(audioInput) {
                    captureSession.addInput(audioInput)
                }
            } catch {
                print("Audio input unavailable: \(error)")
            }
        }
        
        audioOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        if captureSession.canAddOutput(audioOutput) {
            captureSession.addOutput(audioOutput)
        }
        
        captureSession.commitConfiguration()
    }
    
    // MARK: - Session Control
    
    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                Task { @MainActor in
                    self.isSessionRunning = true
                }
            }
        }
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                Task { @MainActor in
                    self.isSessionRunning = false
                }
            }
        }
    }
    
    // MARK: - Camera Switching
    
    func switchCamera() {
        useFrontCamera.toggle()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.setupSessionOnQueue()
        }
    }
    
    // MARK: - Zoom Control
    
    /// Sets the zoom factor, optionally switching to a different lens if needed
    func setZoom(_ factor: CGFloat, animated: Bool = true) {
        let position: AVCaptureDevice.Position = useFrontCamera ? .front : .back
        
        print("🔍 setZoom called with factor: \(factor)")
        
        // If we're recording, we can't switch cameras - only do digital zoom on current lens
        if isRecording {
            print("⚠️ Recording in progress - using digital zoom only")
            guard let device = currentVideoInput?.device else {
                print("❌ No current video input device")
                return
            }
            
            // Clamp to current device's capabilities
            let deviceTargetZoom = min(max(factor, device.minAvailableVideoZoomFactor),
                                      device.maxAvailableVideoZoomFactor)
            
            print("🔍 Digital zoom on current device to: \(deviceTargetZoom)x")
            
            sessionQueue.async { [weak self] in
                guard let self else { return }
                do {
                    try device.lockForConfiguration()
                    
                    if animated {
                        device.ramp(toVideoZoomFactor: deviceTargetZoom, withRate: 4.0)
                    } else {
                        device.videoZoomFactor = deviceTargetZoom
                    }
                    
                    device.unlockForConfiguration()
                    
                    Task { @MainActor in
                        self.currentZoomFactor = deviceTargetZoom
                    }
                } catch {
                    print("❌ Error setting zoom: \(error)")
                }
            }
            return
        }
        
        // Determine which physical lens should be used for this zoom level
        guard let preferredDevice = deviceManager.preferredDevice(forZoomFactor: factor, position: position) else {
            print("❌ No preferred device found for zoom \(factor)")
            return
        }
        
        print("🔍 Preferred device for \(factor)x: \(preferredDevice.displayName)")
        
        // Get the absolute min/max across all available lenses using displayZoomFactor
        // (not minZoomFactor which is always 1.0 for each physical camera)
        let absoluteMin = deviceManager.availableDevices.map(\.displayZoomFactor).min() ?? 1.0
        let absoluteMax = deviceManager.availableDevices.map(\.maxZoomFactor).max() ?? 10.0
        let targetZoom = min(max(factor, absoluteMin), absoluteMax)
        
        print("🔍 Absolute zoom range: \(absoluteMin)x - \(absoluteMax)x, Target: \(targetZoom)x")
        
        // Check if we need to switch to a different physical lens
        if let currentDevice = currentVideoInput?.device,
           preferredDevice.device.uniqueID != currentDevice.uniqueID {
            // Need to switch camera device
            print("🔄 Switching from \(currentDevice.deviceType.rawValue) to \(preferredDevice.deviceType.rawValue)")
            currentZoomFactor = targetZoom
            configureSession(useFrontCamera: useFrontCamera)
            return
        }
        
        // Just adjust zoom on current device
        guard let device = currentVideoInput?.device else { 
            print("❌ No current video input device")
            return 
        }
        
        // Clamp to the current device's capabilities
        let deviceTargetZoom = min(max(targetZoom, device.minAvailableVideoZoomFactor), 
                                   device.maxAvailableVideoZoomFactor)
        
        print("🔍 Adjusting zoom on current device to: \(deviceTargetZoom)x")
        
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try device.lockForConfiguration()
                
                if animated {
                    device.ramp(toVideoZoomFactor: deviceTargetZoom, withRate: 4.0)
                } else {
                    device.videoZoomFactor = deviceTargetZoom
                }
                
                device.unlockForConfiguration()
                
                Task { @MainActor in
                    self.currentZoomFactor = deviceTargetZoom
                }
            } catch {
                print("❌ Error setting zoom: \(error)")
            }
        }
    }
    
    /// Quick zoom to a preset factor (like 0.5x, 1x, 2x buttons)
    func quickZoom(to factor: CGFloat) {
        setZoom(factor, animated: true)
    }
    
    /// Adjust zoom by a relative amount (for pinch gestures)
    func adjustZoom(by scale: CGFloat) {
        let newZoom = currentZoomFactor * scale
        setZoom(newZoom, animated: false)
    }
    
    /// Reset zoom to 1x
    func resetZoom() {
        setZoom(1.0, animated: true)
    }
    
    // MARK: - Photo Capture
    
    @Published var capturePhotoRequested = false
    
    func capturePhoto() {
        capturePhotoRequested = true
    }
    
    func savePhoto(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    self.handleError("Photo library access denied")
                }
                return
            }
            
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                Task { @MainActor in
                    if success {
                        self.lastCapturedImage = image
                    } else if let error = error {
                        self.handleError(error.localizedDescription)
                    }
                }
            }
        }
    }
    
    // MARK: - Video Recording
    
    func startRecording(size: CGSize) {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "GTASCIICamera_\(Date().timeIntervalSince1970).mp4"
        let url = tempDir.appendingPathComponent(fileName)
        recordingURL = url
        
        do {
            assetWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            handleError(error.localizedDescription)
            return
        }
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        
        videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriterInput?.expectsMediaDataInRealTime = true
        videoWriterInput?.transform = .identity
        
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput!,
            sourcePixelBufferAttributes: attributes
        )
        
        if assetWriter!.canAdd(videoWriterInput!) {
            assetWriter!.add(videoWriterInput!)
        }
        
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000
        ]
        
        audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioWriterInput?.expectsMediaDataInRealTime = true
        
        if assetWriter!.canAdd(audioWriterInput!) {
            assetWriter!.add(audioWriterInput!)
        }
        
        assetWriter!.startWriting()
        recordingStartTime = nil
        isRecording = true
        recordingDuration = 0
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isRecording else { return }
                self.recordingDuration += 0.1
            }
        }
    }
    
    func stopRecording() async -> URL? {
        guard isRecording, let writer = assetWriter else { return nil }
        
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        videoWriterInput?.markAsFinished()
        audioWriterInput?.markAsFinished()
        
        let recordingURLCopy = recordingURL
        
        return await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume(returning: recordingURLCopy)
            }
        }
    }
    
    func appendVideoFrame(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        guard isRecording,
              let writer = assetWriter,
              let input = videoWriterInput,
              let adaptor = pixelBufferAdaptor else { return }
        
        if recordingStartTime == nil {
            recordingStartTime = time
            writer.startSession(atSourceTime: time)
        }
        
        if input.isReadyForMoreMediaData {
            adaptor.append(pixelBuffer, withPresentationTime: time)
        }
    }
    
    func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording,
              let input = audioWriterInput,
              recordingStartTime != nil,
              input.isReadyForMoreMediaData else { return }
        
        input.append(sampleBuffer)
    }
    
    func saveVideoToLibrary(url: URL) async -> Bool {
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    continuation.resume(returning: false)
                    return
                }
                
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } completionHandler: { success, _ in
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    private func handleError(_ message: String) {
        Task { @MainActor in
            errorMessage = message
            showError = true
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate,
                         AVCaptureAudioDataOutputSampleBufferDelegate {
    
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let isVideo = (output == videoOutput)
        
        if isVideo {
            onNewFrame?(sampleBuffer)
        } else {
            // Nota: Se appendAudioSample causa lag, considera di spostare
            // la logica della registrazione video su una coda non-MainActor.
            Task { @MainActor in
                self.appendAudioSample(sampleBuffer)
            }
        }
    }
    
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) { }
}
