import SwiftUI

/// Floating glass control surface pinned to the bottom edge — one single row,
/// deliberately thin so it never eats caption space.
struct ControlDock: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// On a phone the dock only has room for the essentials.
    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        #if os(iOS)
        if isCompact { compactDock } else { deskDock }
        #else
        deskDock
        #endif
    }

    /// iPhone: a capsule for context plus a circle for the primary action,
    /// mirroring the split Apple Music uses for its mini player.
    private var compactDock: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                LanguageMenu()

                Text(statusLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 2)

                ShareLink(item: model.translationMarkdown) {
                    DockIcon(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .disabled(model.captions.isEmpty)
                .opacity(model.captions.isEmpty ? 0.35 : 1)

                SessionMenu()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)

            StartStopButton()
                .glassEffect(.regular, in: .circle)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// macOS / iPad: the original single-row bar.
    private var deskDock: some View {
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
            .accessibilityLabel(L("导出逐字稿"))

            SessionMenu()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .frame(maxWidth: 460)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }

    /// One-line status used by both layouts.
    private var statusLine: String {
        if model.speechProgress != nil { return L("下载中…") }
        guard !model.captions.isEmpty else { return L(model.statusText) }
        return String(format: NSLocalizedString("%d 段", comment: ""), model.captions.count)
    }

    /// Status is a localised key; the segment counter is a separate, formatted
    /// string so both can be translated independently.
    private var statusText: LocalizedStringKey {
        if model.speechProgress != nil {
            return LocalizedStringKey(L("下载识别模型 %d%%"))
        }
        return LocalizedStringKey(model.statusText)
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        Button {
            Task { await model.toggle() }
        } label: {
            ZStack {
                if model.isPreparing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if model.isRunning {
                    // 录音时不要红色底盘，只留一个方块，背景透明
                    // `Color.primary` inside the glass container gets vibrant
                    // blending and turns grey, so use an explicit colour.
                    RoundedRectangle(cornerRadius: 3)
                        .fill(colorScheme == .dark ? Color.white : Color.black)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: isCompact ? 44 : 40, height: isCompact ? 44 : 40)
            .background {
                if !model.isRunning {
                    Circle().fill(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isPreparing)
        .accessibilityLabel(model.isRunning ? L("停止") : L("开始"))
    }
}

struct LanguageMenu: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Menu {
            Picker(L("识别语言"), selection: $model.settings.sourceLanguageID) {
                ForEach(model.speechOptions) { option in
                    Text(option.displayName).tag(option.id)
                }
            }
            Picker(L("翻译成"), selection: $model.settings.targetLanguageID) {
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
        let source = L10n.locale.localizedString(forIdentifier: model.settings.sourceLanguageID)
            ?? model.settings.sourceLanguageID
        let target = L10n.locale.localizedString(forIdentifier: model.settings.targetLanguageID)
            ?? model.settings.targetLanguageID
        return "\(source) → \(target)"
    }
}

struct SessionMenu: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Menu {
            Button {
                Clipboard.copy(model.plainText)
            } label: {
                Label(L("复制全文"), systemImage: "doc.on.doc")
            }

            Button {
                model.exportSourceMarkdown()
            } label: {
                Label(L("导出 Markdown 文件（仅原文）"), systemImage: "square.and.arrow.down")
            }

            Button {
                Clipboard.copy(model.translationMarkdown)
            } label: {
                Label(L("复制为 Markdown"), systemImage: "text.badge.checkmark")
            }

            Divider()

            Button(role: .destructive) {
                model.requestClear()
            } label: {
                Label(L("清空字幕"), systemImage: "trash")
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
