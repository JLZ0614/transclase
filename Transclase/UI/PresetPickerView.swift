import SwiftUI

/// One flat list of built-in providers.
struct PresetPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (ProviderPreset) -> Void
    /// Called when the user wants an endpoint that is not in the list.
    var onCustom: () -> Void = {}

    var body: some View {
        NavigationStack {
            List(ProviderPreset.all) { preset in
                Button {
                    onPick(preset)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name)
                            .foregroundStyle(.primary)
                        Text(preset.baseURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(L("添加模型供应商"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("自定义")) {
                        onCustom()
                    }
                }
            }
        }
    }
}
