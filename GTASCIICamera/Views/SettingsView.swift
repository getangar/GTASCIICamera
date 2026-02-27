//
//  SettingsView.swift
//  GT ASCII Camera
//
//  Created by Gennaro Eduardo Tangari on 27/02/2026.
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//

import SwiftUI

/// Settings panel presented as a sheet from the camera view.
/// Organized into logical sections following iOS Settings conventions.
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Palette Section
                Section {
                    ForEach(ASCIIPalette.allCases) { palette in
                        Button {
                            settings.selectedPalette = palette
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(palette.displayName)
                                        .foregroundColor(.primary)

                                    Text(palette.preview)
                                        .font(.system(size: 16, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if settings.selectedPalette == palette {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Character Palette")
                } footer: {
                    Text("Classic uses traditional ASCII characters. Unicode Blocks provide a denser, more modern look.")
                }

                // MARK: - Resolution Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Columns")
                            Spacer()
                            Text("\(settings.asciiColumns)")
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }

                        Slider(
                            value: Binding(
                                get: { Double(settings.asciiColumns) },
                                set: { settings.asciiColumns = Int($0) }
                            ),
                            in: 40...200,
                            step: 10
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Font Size")
                            Spacer()
                            Text(String(format: "%.0f pt", settings.fontSize))
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }

                        Slider(
                            value: $settings.fontSize,
                            in: 4...24,
                            step: 1
                        )
                    }
                } header: {
                    Text("Resolution")
                } footer: {
                    Text("More columns means finer detail but smaller characters. Adjust font size for readability.")
                }

                // MARK: - Appearance Section
                Section {
                    Toggle(isOn: $settings.coloredOutput) {
                        Label {
                            Text("Colored Output")
                        } icon: {
                            Image(systemName: "paintpalette.fill")
                                .foregroundColor(.orange)
                        }
                    }

                    Toggle(isOn: $settings.invertLuminance) {
                        Label {
                            Text("Invert Luminance")
                        } icon: {
                            Image(systemName: "circle.lefthalf.filled")
                                .foregroundColor(.purple)
                        }
                    }

                    Toggle(isOn: $settings.darkBackground) {
                        Label {
                            Text("Dark Background")
                        } icon: {
                            Image(systemName: "moon.fill")
                                .foregroundColor(.indigo)
                        }
                    }
                } header: {
                    Text("Appearance")
                }

                // MARK: - Presets Section
                Section {
                    Button {
                        withAnimation { settings.applyRetroPreset() }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Retro Terminal")
                                Text("Green on black, classic ASCII, 80 columns")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "terminal.fill")
                                .foregroundColor(.green)
                        }
                    }

                    Button {
                        withAnimation { settings.applyModernPreset() }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Modern Blocks")
                                Text("Unicode blocks, colored, 120 columns")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "square.grid.3x3.fill")
                                .foregroundColor(.cyan)
                        }
                    }

                    Button {
                        withAnimation { settings.applyHighDetailPreset() }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("High Detail")
                                Text("Classic ASCII, colored, 160 columns")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "sparkles")
                                .foregroundColor(.yellow)
                        }
                    }

                    Button {
                        withAnimation { settings.applyBlackAndWhitePreset() }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Black & White")
                                Text("White on black, classic ASCII, 80 columns")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "circle.fill")
                                .foregroundColor(.white)
                        }
                    }
                } header: {
                    Text("Quick Presets")
                }

                // MARK: - About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Author")
                        Spacer()
                        Text("Gennaro Eduardo Tangari")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Copyright")
                        Spacer()
                        Text("(c) 2026 Gennaro Eduardo Tangari")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
