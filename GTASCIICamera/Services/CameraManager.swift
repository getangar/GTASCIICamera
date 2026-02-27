//
//
//  CameraManager.swift
//  GT ASCII Camera
//
//  Created by Gennaro Eduardo Tangari on 27/02/2026.
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import AVFoundation
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
        self.useFrontCamera = useFrontCamera
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.setupSessionOnQueue()
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

        // Remove existing inputs
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }

        // Video input
        let position: AVCaptureDevice.Position = useFrontCamera ? .front : .back
        guard let videoDevice = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: position
        ) else {
            handleError("No camera available")
            captureSession.commitConfiguration()
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
                currentVideoInput = videoInput
            }
        } catch {
            handleError(error.localizedDescription)
            captureSession.commitConfiguration()
            return
        }

        // Video output
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // Set video orientation
        if let connection = videoOutput.connection(with: .video) {
            // Front and back cameras need different rotation angles due to sensor orientation
            let rotationAngle: CGFloat = useFrontCamera ? 0.0 : 90
            
            if connection.isVideoRotationAngleSupported(rotationAngle) {
                connection.videoRotationAngle = rotationAngle
            }
            
            // DO NOT mirror at the connection level - we'll handle it in the video writer
            // This way the pixel buffers are always unmirrored for recording
        }

        // Audio input (for video recording)
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            do {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if captureSession.canAddInput(audioInput) {
                    captureSession.addInput(audioInput)
                }
            } catch {
                // Audio is optional; continue without it
                print("Audio input unavailable: \(error)")
            }
        }

        // Audio output
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

    // MARK: - Photo Capture

    /// Captures the current ASCII-rendered frame as a UIImage.
    /// The actual rendering is done by the Metal pipeline; this just signals
    /// that the next rendered frame should be saved.
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

        // Video writer input
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        videoWriterInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoSettings
        )
        videoWriterInput?.expectsMediaDataInRealTime = true
        
        // The frames are already rotated to portrait by the video connection (90 degrees)
        // No additional transform needed - the pixel buffers are correct for recording
        videoWriterInput?.transform = .identity

        // Pixel buffer adaptor for writing rendered ASCII frames
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

        // Audio writer input
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000
        ]

        audioWriterInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: audioSettings
        )
        audioWriterInput?.expectsMediaDataInRealTime = true

        if assetWriter!.canAdd(audioWriterInput!) {
            assetWriter!.add(audioWriterInput!)
        }

        assetWriter!.startWriting()
        recordingStartTime = nil
        isRecording = true
        recordingDuration = 0

        // Update recording duration on a timer
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

    /// Appends a rendered ASCII pixel buffer to the recording.
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

    /// Appends an audio sample buffer to the recording.
    func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording,
              let input = audioWriterInput,
              recordingStartTime != nil,
              input.isReadyForMoreMediaData else { return }

        input.append(sampleBuffer)
    }

    /// Saves a recorded video to the photo library.
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

    // MARK: - Error Handling

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
        // Capture callback - already on sessionQueue
        let isVideo = (output == videoOutput)
        let callback = onNewFrame
        
        if isVideo {
            callback?(sampleBuffer)
        } else {
            // Audio sample - needs main actor for recording state
            Task { @MainActor in
                self.appendAudioSample(sampleBuffer)
            }
        }
    }

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Frame dropped — acceptable under heavy load
    }
}
