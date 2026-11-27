import SwiftUI

/// One flat list of built-in providers — no nested menus.
struct PresetPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (ProviderPreset) -> Void

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
            .navigationTitle(L("添加供应商"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { dismiss() }
                }
            }
        }
    }
}
