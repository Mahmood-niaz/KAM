import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("Capture Mode", selection: $viewModel.captureMode) {
                        ForEach(CaptureMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Text(viewModel.captureMode.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Capture Mode")
                }

                // Auto-Capture Section
                Section {
                    Toggle("Enable Auto-Capture", isOn: $viewModel.autoCaptureEnabled)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Minimum Score: \(Int(viewModel.minimumScoreThreshold * 100))%")
                            .font(.subheadline)

                        Slider(
                            value: $viewModel.minimumScoreThreshold,
                            in: 0.5...0.95,
                            step: 0.05
                        )
                        .onChange(of: viewModel.minimumScoreThreshold) { _, _ in
                            viewModel.updateSettings()
                        }

                        Text("Higher values require better composition before auto-capture")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Picker("Cooldown Between Captures", selection: $viewModel.captureCooldown) {
                        Text("1 second").tag(1.0 as TimeInterval)
                        Text("2 seconds").tag(2.0 as TimeInterval)
                        Text("3 seconds").tag(3.0 as TimeInterval)
                        Text("5 seconds").tag(5.0 as TimeInterval)
                    }
                    .onChange(of: viewModel.captureCooldown) { _, _ in
                        viewModel.updateSettings()
                    }
                } header: {
                    Text("Auto-Capture")
                }

                // Aspect Ratio Section
                Section {
                    Picker("Crop Aspect Ratio", selection: $viewModel.selectedAspectRatio) {
                        ForEach(AspectRatio.allCases) { ratio in
                            HStack {
                                Text(ratio.displayName)
                                Spacer()
                                Text(ratio.description)
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .tag(ratio)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Text("The viewfinder shows this crop frame; Claude uses it when suggesting crops")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Crop Settings")
                }

                // Display Section
                Section {
                    Toggle("Show Grid Overlay", isOn: $viewModel.showGrid)
                    Toggle("Show Level Indicator", isOn: $viewModel.showLevelIndicator)

                    Picker("Grid Type", selection: $viewModel.gridType) {
                        ForEach(GridType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .disabled(!viewModel.showGrid)

                    Toggle("Show Score Details", isOn: $viewModel.showScoreDetails)

                    Toggle("Haptic Feedback", isOn: $viewModel.hapticEnabled)
                } header: {
                    Text("Display")
                }

                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Photos Captured")
                        Spacer()
                        Text("\(viewModel.captureCount)")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView(viewModel: CameraViewModel())
}
