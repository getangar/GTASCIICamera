//
//  SettingsManager.swift
//  GT ASCII Camera
//
//  Created by Gennaro Eduardo Tangari on 27/02/2026.
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

/// Manages persistent user preferences for the ASCII camera.
@MainActor
final class SettingsManager: ObservableObject {

    // MARK: - Published Properties

    /// The currently selected ASCII palette.
    @AppStorage("selectedPalette") var selectedPalette: ASCIIPalette = .classic

    /// Number of ASCII columns (controls detail/resolution of the ASCII art).
    @AppStorage("asciiColumns") var asciiColumns: Int = 80

    /// Font size for rendering ASCII characters in the output.
    @AppStorage("fontSize") var fontSize: Double = 10.0

    /// Whether to use colored ASCII output (tinted characters) vs pure monochrome.
    @AppStorage("coloredOutput") var coloredOutput: Bool = true

    /// Invert luminance mapping (light chars on dark bg vs dark chars on light bg).
    @AppStorage("invertLuminance") var invertLuminance: Bool = false

    /// Background color mode for the rendered output.
    @AppStorage("darkBackground") var darkBackground: Bool = true

    /// Whether to use the front-facing camera.
    @AppStorage("useFrontCamera") var useFrontCamera: Bool = false

    /// Video recording resolution multiplier (1x = screen, 2x = double).
    @AppStorage("recordingQuality") var recordingQuality: Int = 1

    // MARK: - Computed Properties

    /// The foreground color for monochrome ASCII rendering.
    var foregroundColor: Color {
        darkBackground ? .green : .white
    }

    /// The background color for the ASCII canvas.
    var backgroundColor: Color {
        darkBackground ? .black : .black
    }

    /// Computed number of rows based on columns and a typical aspect ratio.
    func asciiRows(forAspectRatio aspectRatio: CGFloat) -> Int {
        // Character cells are roughly twice as tall as wide in monospaced fonts,
        // so we halve the row count to maintain visual aspect ratio.
        let rawRows = Double(asciiColumns) / aspectRatio * 0.55
        return max(1, Int(rawRows))
    }

    // MARK: - Preset Configurations

    /// Apply a "retro terminal" preset.
    func applyRetroPreset() {
        selectedPalette = .classic
        asciiColumns = 80
        fontSize = 10.0
        coloredOutput = false
        invertLuminance = false
        darkBackground = true
    }

    /// Apply a "modern block" preset.
    func applyModernPreset() {
        selectedPalette = .unicode
        asciiColumns = 120
        fontSize = 8.0
        coloredOutput = true
        invertLuminance = false
        darkBackground = true
    }

    /// Apply a "high detail" preset.
    func applyHighDetailPreset() {
        selectedPalette = .classic
        asciiColumns = 160
        fontSize = 6.0
        coloredOutput = true
        invertLuminance = false
        darkBackground = true
    }

    /// Apply a "black & white" preset.
    func applyBlackAndWhitePreset() {
        selectedPalette = .classic
        asciiColumns = 80
        fontSize = 10.0
        coloredOutput = false
        invertLuminance = false
        darkBackground = false // White foreground on black background
    }
}
