//
//  ASCIIMetalRenderer.swift
//  GT ASCII Camera
//
//  Created by Gennaro Tocco
//
//  Manages the Metal rendering pipeline for real-time ASCII art conversion.
//  Responsibilities:
//    - Device and command queue setup
//    - Glyph atlas generation (Core Text → Metal texture)
//    - Compute pipeline state management
//    - Per-frame rendering: camera texture → ASCII art texture
//

import Foundation
import Metal
import MetalKit
import CoreVideo
import CoreMedia
import CoreGraphics
import CoreText
import UIKit

final class ASCIIMetalRenderer {

    // MARK: - Metal Core

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private var coloredPipelineState: MTLComputePipelineState?
    private var monochromePipelineState: MTLComputePipelineState?

    // MARK: - Textures

    private var glyphAtlasTexture: MTLTexture?
    private var outputTexture: MTLTexture?
    private var textureCache: CVMetalTextureCache?

    // MARK: - Configuration

    private(set) var currentPalette: ASCIIPalette = .classic
    private(set) var outputWidth: Int = 1080
    private(set) var outputHeight: Int = 1920

    // MARK: - Thread Safety

    private let renderQueue = DispatchQueue(label: "com.gtasciicamera.render", qos: .userInteractive)

    // MARK: - Init

    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return nil
        }

        guard let commandQueue = device.makeCommandQueue() else {
            print("Failed to create Metal command queue")
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue

        // Create texture cache for efficient CVPixelBuffer → MTLTexture conversion
        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        if status == kCVReturnSuccess {
            textureCache = cache
        }

        setupPipelines()
        generateGlyphAtlas(for: .classic, fontSize: 16)
    }

    // MARK: - Pipeline Setup

    private func setupPipelines() {
        guard let library = device.makeDefaultLibrary() else {
            print("Failed to load Metal shader library")
            return
        }

        // Colored kernel
        if let coloredFunc = library.makeFunction(name: "asciiArtKernel") {
            do {
                coloredPipelineState = try device.makeComputePipelineState(function: coloredFunc)
            } catch {
                print("Failed to create colored pipeline: \(error)")
            }
        }

        // Monochrome kernel
        if let monoFunc = library.makeFunction(name: "asciiArtMonochromeKernel") {
            do {
                monochromePipelineState = try device.makeComputePipelineState(function: monoFunc)
            } catch {
                print("Failed to create monochrome pipeline: \(error)")
            }
        }
    }

    // MARK: - Glyph Atlas Generation

    /// Generates a horizontal strip texture containing all glyphs in the palette,
    /// rendered with Core Text into a CGContext, then uploaded to a Metal texture.
    func generateGlyphAtlas(for palette: ASCIIPalette, fontSize: CGFloat) {
        currentPalette = palette
        let chars = palette.characters

        // Use Menlo as our monospaced font (available on all iOS versions)
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, fontSize, nil)

        // Measure maximum glyph dimensions
        var maxWidth: CGFloat = 0
        var maxHeight: CGFloat = 0

        var _: [(CGImage, CGSize)] = []

        for char in chars {
            let attrString = NSAttributedString(
                string: String(char),
                attributes: [
                    .font: font as Any,
                    .foregroundColor: UIColor.white.cgColor
                ]
            )

            let line = CTLineCreateWithAttributedString(attrString)
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

            let cellW = max(ceil(bounds.width) + 4, ceil(fontSize * 0.7))
            let cellH = max(ceil(bounds.height) + 4, ceil(fontSize * 1.2))

            maxWidth = max(maxWidth, cellW)
            maxHeight = max(maxHeight, cellH)
        }

        // Ensure even dimensions
        let cellWidth = Int(ceil(maxWidth))
        let cellHeight = Int(ceil(maxHeight))
        let atlasWidth = cellWidth * chars.count
        let atlasHeight = cellHeight

        // Create CGContext for the atlas
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: atlasWidth,
            height: atlasHeight,
            bitsPerComponent: 8,
            bytesPerRow: atlasWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("Failed to create CGContext for glyph atlas")
            return
        }

        // Clear to transparent black
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
        context.fill(CGRect(x: 0, y: 0, width: atlasWidth, height: atlasHeight))

        // Render each glyph
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))

        for (index, char) in chars.enumerated() {
            let attrString = NSAttributedString(
                string: String(char),
                attributes: [
                    .font: font as Any,
                    .foregroundColor: UIColor.white
                ]
            )

            let line = CTLineCreateWithAttributedString(attrString)
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

            let x = CGFloat(index * cellWidth) + (CGFloat(cellWidth) - bounds.width) / 2.0 - bounds.origin.x
            let y = (CGFloat(cellHeight) - bounds.height) / 2.0 - bounds.origin.y

            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(line, context)
        }

        // Create Metal texture from the atlas
        guard let cgImage = context.makeImage() else {
            print("Failed to create CGImage from glyph atlas context")
            return
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: atlasWidth,
            height: atlasHeight,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            print("Failed to create glyph atlas texture")
            return
        }

        // Upload pixel data
        if let data = cgImage.dataProvider?.data,
           let bytes = CFDataGetBytePtr(data) {
            texture.replace(
                region: MTLRegionMake2D(0, 0, atlasWidth, atlasHeight),
                mipmapLevel: 0,
                withBytes: bytes,
                bytesPerRow: cgImage.bytesPerRow
            )
        }

        glyphAtlasTexture = texture
    }

    // MARK: - Output Texture Management

    func updateOutputSize(width: Int, height: Int) {
        guard width != outputWidth || height != outputHeight else { return }
        outputWidth = width
        outputHeight = height
        outputTexture = nil // Will be recreated on next render
    }

    private func ensureOutputTexture() -> MTLTexture? {
        if let existing = outputTexture,
           existing.width == outputWidth,
           existing.height == outputHeight {
            return existing
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: outputWidth,
            height: outputHeight,
            mipmapped: false
        )
        descriptor.usage = [.shaderWrite, .shaderRead]
        descriptor.storageMode = .shared

        outputTexture = device.makeTexture(descriptor: descriptor)
        return outputTexture
    }

    // MARK: - Pixel Buffer → Metal Texture

    func texture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let cache = textureCache else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var metalTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &metalTexture
        )

        guard status == kCVReturnSuccess, let cvTexture = metalTexture else {
            return nil
        }

        return CVMetalTextureGetTexture(cvTexture)
    }

    // MARK: - Render ASCII Frame

    /// Renders one frame of ASCII art from the source camera pixel buffer.
    /// Returns the rendered output texture (shared storage, readable from CPU).
    func renderASCIIFrame(
        from pixelBuffer: CVPixelBuffer,
        columns: Int,
        rows: Int,
        palette: ASCIIPalette,
        colored: Bool,
        invertLuminance: Bool,
        foregroundColor: SIMD4<Float> = SIMD4<Float>(0, 1, 0, 1),
        backgroundColor: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1)
    ) -> MTLTexture? {

        // Regenerate atlas if palette changed
        if palette != currentPalette {
            generateGlyphAtlas(for: palette, fontSize: 16)
        }

        guard let sourceTexture = texture(from: pixelBuffer),
              let glyphAtlas = glyphAtlasTexture,
              let output = ensureOutputTexture(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return nil
        }

        let pipeline = colored ? coloredPipelineState : monochromePipelineState
        guard let pipelineState = pipeline else { return nil }

        encoder.setComputePipelineState(pipelineState)

        // Textures
        encoder.setTexture(sourceTexture, index: 0)
        encoder.setTexture(glyphAtlas, index: 1)
        encoder.setTexture(output, index: 2)

        // Uniforms
        var uniforms = RenderUniforms(
            columns: UInt32(columns),
            rows: UInt32(rows),
            paletteSize: UInt32(palette.levels),
            textureWidth: UInt32(sourceTexture.width),
            textureHeight: UInt32(sourceTexture.height),
            invertLuminance: invertLuminance ? 1 : 0,
            fontSize: 16.0,
            padding: 0.0
        )
        encoder.setBytes(&uniforms, length: MemoryLayout<RenderUniforms>.size, index: 0)

        // For monochrome mode, pass foreground and background colors
        if !colored {
            var fg = foregroundColor
            var bg = backgroundColor
            encoder.setBytes(&fg, length: MemoryLayout<SIMD4<Float>>.size, index: 1)
            encoder.setBytes(&bg, length: MemoryLayout<SIMD4<Float>>.size, index: 2)
        }

        // Dispatch threads
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let gridSize = MTLSize(width: outputWidth, height: outputHeight, depth: 1)

        if device.supportsFamily(.apple4) {
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
        } else {
            let threadGroupCount = MTLSize(
                width: (outputWidth + threadGroupSize.width - 1) / threadGroupSize.width,
                height: (outputHeight + threadGroupSize.height - 1) / threadGroupSize.height,
                depth: 1
            )
            encoder.dispatchThreadgroups(threadGroupCount, threadsPerThreadgroup: threadGroupSize)
        }

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return output
    }

    // MARK: - Snapshot to UIImage

    func textureToImage(_ texture: MTLTexture) -> UIImage? {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        let totalBytes = bytesPerRow * height

        var pixelData = [UInt8](repeating: 0, count: totalBytes)
        texture.getBytes(
            &pixelData,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )

        // BGRA → RGBA swap
        for i in stride(from: 0, to: totalBytes, by: 4) {
            let b = pixelData[i]
            pixelData[i] = pixelData[i + 2]
            pixelData[i + 2] = b
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let cgImage = context.makeImage() else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    // MARK: - Snapshot to CVPixelBuffer (for recording)

    func textureToPixelBuffer(_ texture: MTLTexture) -> CVPixelBuffer? {
        let width = texture.width
        let height = texture.height

        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        let status = CVPixelBufferCreate(
            nil,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        texture.getBytes(
            baseAddress,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )

        return buffer
    }
}
