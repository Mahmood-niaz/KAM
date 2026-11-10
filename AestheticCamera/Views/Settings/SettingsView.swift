import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
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

                Toggle("Show Grid Overlay", isOn: $viewModel.showGrid)
                Toggle("Show Level Indicator", isOn: $viewModel.showLevelIndicator)

                Picker("Grid Type", selection: $viewModel.gridType) {
                    ForEach(GridType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .disabled(!viewModel.showGrid)

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
