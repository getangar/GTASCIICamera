//
//  MetalASCIIView.swift
//  GT ASCII Camera
//
//  Created by Gennaro Eduardo Tangari on 27/02/2026.
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//
//  A SwiftUI wrapper around MTKView that displays the real-time ASCII art
//  output from the Metal compute pipeline. The Coordinator handles frame
//  delivery from the camera and drives the render loop.
//

import SwiftUI
import MetalKit
import CoreMedia
import CoreVideo

struct MetalASCIIView: UIViewRepresentable {
    let renderer: ASCIIMetalRenderer
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var settings: SettingsManager

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer, cameraManager: cameraManager, settings: settings)
    }

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView(frame: .zero, device: renderer.device)
        mtkView.delegate = context.coordinator
        mtkView.framebufferOnly = false
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.preferredFramesPerSecond = 30
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.backgroundColor = .black
        mtkView.autoResizeDrawable = true

        // Connect camera frame delivery
        context.coordinator.mtkView = mtkView
        context.coordinator.startReceivingFrames()

        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.settings = settings
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MTKViewDelegate {
        let renderer: ASCIIMetalRenderer
        let cameraManager: CameraManager
        var settings: SettingsManager
        weak var mtkView: MTKView?

        private var latestPixelBuffer: CVPixelBuffer?
        private var latestPresentationTime: CMTime = .zero
        private let bufferLock = NSLock()

        init(renderer: ASCIIMetalRenderer, cameraManager: CameraManager, settings: SettingsManager) {
            self.renderer = renderer
            self.cameraManager = cameraManager
            self.settings = settings
            super.init()
        }

        @MainActor func startReceivingFrames() {
            cameraManager.onNewFrame = { [weak self] sampleBuffer in
                guard let self = self,
                      let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

                let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                self.bufferLock.lock()
                self.latestPixelBuffer = pixelBuffer
                self.latestPresentationTime = time
                self.bufferLock.unlock()
            }
        }

        // MARK: - MTKViewDelegate

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            renderer.updateOutputSize(
                width: Int(size.width),
                height: Int(size.height)
            )
        }

        func draw(in view: MTKView) {
            bufferLock.lock()
            guard let pixelBuffer = latestPixelBuffer else {
                bufferLock.unlock()
                return
            }
            let presentationTime = latestPresentationTime
            bufferLock.unlock()

            let aspectRatio = CGFloat(CVPixelBufferGetWidth(pixelBuffer)) /
                              CGFloat(CVPixelBufferGetHeight(pixelBuffer))
            let columns = settings.asciiColumns
            let rows = settings.asciiRows(forAspectRatio: aspectRatio)

            // Determine foreground/background colors for monochrome mode
            let fgColor: SIMD4<Float>
            let bgColor: SIMD4<Float>

            if settings.darkBackground {
                fgColor = SIMD4<Float>(0, 1, 0, 1) // Classic green for retro terminal
                bgColor = SIMD4<Float>(0, 0, 0, 1)
            } else {
                fgColor = SIMD4<Float>(1, 1, 1, 1) // White for black & white mode
                bgColor = SIMD4<Float>(0, 0, 0, 1) // Black background
            }

            guard let outputTexture = renderer.renderASCIIFrame(
                from: pixelBuffer,
                columns: columns,
                rows: rows,
                palette: settings.selectedPalette,
                colored: settings.coloredOutput,
                invertLuminance: settings.invertLuminance,
                foregroundColor: fgColor,
                backgroundColor: bgColor
            ) else { return }

            // Blit rendered texture to the drawable
            guard let drawable = view.currentDrawable,
                  let commandBuffer = renderer.commandQueue.makeCommandBuffer(),
                  let blitEncoder = commandBuffer.makeBlitCommandEncoder()
            else { return }

            let srcSize = MTLSize(
                width: min(outputTexture.width, drawable.texture.width),
                height: min(outputTexture.height, drawable.texture.height),
                depth: 1
            )

            blitEncoder.copy(
                from: outputTexture,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: srcSize,
                to: drawable.texture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blitEncoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()

            // Handle photo capture
            Task { @MainActor in
                if cameraManager.capturePhotoRequested {
                    cameraManager.capturePhotoRequested = false
                    if let image = renderer.textureToImage(outputTexture) {
                        cameraManager.savePhoto(image)
                    }
                }
            }

            // Handle video recording: append rendered frame
            Task { @MainActor in
                if cameraManager.isRecording {
                    if let pb = renderer.textureToPixelBuffer(outputTexture) {
                        cameraManager.appendVideoFrame(pb, at: presentationTime)
                    }
                }
            }
        }
    }
}
