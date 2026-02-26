//
//  RenderingConfig.swift
//  GT ASCII Camera
//
//  Created by Gennaro Tocco
//

import Foundation
import simd

/// Configuration parameters passed to the Metal rendering pipeline.
/// Matches the layout of the `RenderUniforms` struct in the Metal shader.
struct RenderUniforms {
    /// Number of character columns in the ASCII grid.
    var columns: UInt32
    /// Number of character rows in the ASCII grid.
    var rows: UInt32
    /// Number of characters in the active palette.
    var paletteSize: UInt32
    /// Source texture width in pixels.
    var textureWidth: UInt32
    /// Source texture height in pixels.
    var textureHeight: UInt32
    /// Whether to invert luminance (dark-on-light vs light-on-dark).
    var invertLuminance: UInt32
    /// Font size used for rendering characters (affects cell dimensions).
    var fontSize: Float
    /// Padding/reserved for alignment.
    var padding: Float
}

/// Precomputed ASCII grid dimensions based on the output resolution and font metrics.
struct ASCIIGridConfig {
    let columns: Int
    let rows: Int
    let cellWidth: Float
    let cellHeight: Float

    /// Computes grid dimensions for a given output size and approximate character cell size.
    static func compute(
        outputWidth: Int,
        outputHeight: Int,
        cellWidth: Float,
        cellHeight: Float
    ) -> ASCIIGridConfig {
        let cols = max(1, Int(Float(outputWidth) / cellWidth))
        let rows = max(1, Int(Float(outputHeight) / cellHeight))
        return ASCIIGridConfig(
            columns: cols,
            rows: rows,
            cellWidth: cellWidth,
            cellHeight: cellHeight
        )
    }
}
