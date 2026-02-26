//
//  ASCIIPalette.swift
//  GT ASCII Camera
//
//  Created by Gennaro Tocco
//

import Foundation

/// Defines the available ASCII art character palettes.
/// Each palette maps luminance values to characters ordered by visual weight.
enum ASCIIPalette: String, CaseIterable, Identifiable, Codable {
    case classic
    case unicode

    var id: String { rawValue }

    /// Characters ordered by ascending visual weight (lightest → heaviest).
    var characters: [Character] {
        switch self {
        case .classic:
            return Array(" .:-=+*#%@")
        case .unicode:
            return Array(" ░▒▓█")
        }
    }

    /// The character string for passing to Metal shader as a lookup.
    var characterString: String {
        return String(characters)
    }

    /// Number of distinct luminance levels in this palette.
    var levels: Int {
        return characters.count
    }

    /// Localized display name for the palette selector UI.
    var displayName: String {
        switch self {
        case .classic:
            return String(localized: "palette_classic", defaultValue: "Classic")
        case .unicode:
            return String(localized: "palette_unicode", defaultValue: "Unicode Blocks")
        }
    }

    /// Preview string showing the palette characters.
    var preview: String {
        return characterString
    }

    /// Maps a normalized luminance value (0.0–1.0) to a character.
    func character(forLuminance luminance: Float) -> Character {
        let clamped = max(0.0, min(1.0, luminance))
        let index = Int(clamped * Float(levels - 1))
        return characters[index]
    }
}
