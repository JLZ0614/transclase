import SwiftUI

/// Floating glass control surface pinned to the bottom edge — one single row,
/// deliberately thin so it never eats caption space.
struct ControlDock: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 9) {
            LanguageMenu()

            LevelBars(level: model.level, height: 13)

            Text(statusLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            StartStopButton()

            ShareLink(item: model.translationMarkdown) {
                DockIcon(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .disabled(model.captions.isEmpty)
            .opacity(model.captions.isEmpty ? 0.35 : 1)
            .accessibilityLabel("导出逐字稿")

            SessionMenu()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .frame(maxWidth: 460)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }

    private var statusLine: String {
        var text = model.statusText
        if !model.captions.isEmpty {
            text += " · \(model.captions.count) 段"
        }
        return text
    }
}

private struct DockIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 32, height: 32)
            .glassEffect(.regular.interactive(), in: .circle)
    }
}

struct StartStopButton: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button {
            Task { await model.toggle() }
        } label: {
            ZStack {
                if model.isPreparing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: model.isRunning ? "stop.fill" : "mic.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(model.isRunning ? Color.red : Color.accentColor)
        .disabled(model.isPreparing)
        .accessibilityLabel(model.isRunning ? "停止" : "开始")
    }
}

struct LanguageMenu: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Menu {
            Picker("识别语言", selection: $model.settings.sourceLanguageID) {
                ForEach(model.speechOptions) { option in
                    Text(option.displayName).tag(option.id)
                }
            }
            Picker("翻译成", selection: $model.settings.targetLanguageID) {
                ForEach(model.translationOptions) { option in
                    Text(option.displayName).tag(option.id)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 10, weight: .semibold))
                Text(shortPair)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(model.isRunning || model.isPreparing)
        .opacity(model.isRunning ? 0.55 : 1)
    }

    private var shortPair: String {
        let source = model.settings.sourceLanguageID
            .split(separator: "-").first.map { String($0).uppercased() } ?? "—"
        let target = model.settings.targetLanguageID
        let shortTarget: String
        if target.hasPrefix("zh") {
            shortTarget = "中文"
        } else {
            shortTarget = target.split(separator: "-").first.map { String($0).uppercased() } ?? "—"
        }
        return "\(source) → \(shortTarget)"
    }
}

struct SessionMenu: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Menu {
            Button {
                Clipboard.copy(model.plainText)
            } label: {
                Label("复制全文", systemImage: "doc.on.doc")
            }

            Button {
                Clipboard.copy(model.translationMarkdown)
            } label: {
                Label("复制为 Markdown", systemImage: "text.badge.checkmark")
            }

            Divider()

            Button(role: .destructive) {
                model.requestClear()
            } label: {
                Label("清空字幕", systemImage: "trash")
            }
        } label: {
            DockIcon(systemName: "ellipsis")
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(model.captions.isEmpty)
        .opacity(model.captions.isEmpty ? 0.35 : 1)
    }
}
