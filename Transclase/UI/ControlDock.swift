import SwiftUI

/// Floating glass control surface pinned to the bottom edge — one single row,
/// deliberately thin so it never eats caption space.
struct ControlDock: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme

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

                // Full language names already fill the capsule; the segment
                // counter lives in the session menu instead.
                Spacer(minLength: 2)

                if let url = model.shareFileURL {
                    ShareLink(item: url) {
                        DockIcon(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                } else {
                    DockIcon(systemName: "square.and.arrow.up")
                        .opacity(0.35)
                }

                SessionMenu()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .capsule)
            .overlay {
                Capsule().strokeBorder(
                    Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08),
                    lineWidth: 0.5
                )
            }

            StartStopButton()
                .glassEffect(.regular, in: .circle)
                .overlay {
                    Circle().strokeBorder(
                        Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08),
                        lineWidth: 0.5
                    )
                }
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

            if let url = model.shareFileURL {
                ShareLink(item: url) {
                    DockIcon(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("导出逐字稿"))
            } else {
                DockIcon(systemName: "square.and.arrow.up")
                    .opacity(0.35)
            }

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
            Task {
                if model.needsDownloads, !model.isRunning {
                    await model.prepareOfflinePack()
                } else {
                    await model.toggle()
                }
            }
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
                } else if model.needsDownloads {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: isCompact ? 52 : 40, height: isCompact ? 52 : 40)
            .background {
                if !model.isRunning {
                    Circle().fill(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isPreparing)
        .accessibilityLabel(model.isRunning ? L("停止") : (model.needsDownloads ? L("下载") : L("开始")))
    }
}

struct LanguageMenu: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        // Two separate menus: tapping the left half changes what is being
        // recognised, the right half changes the target language.
        HStack(spacing: 0) {
            languageMenu(
                title: L("识别语言"),
                selection: $model.settings.sourceLanguageID,
                options: model.speechOptions,
                label: displayName(for: model.settings.sourceLanguageID)
            )

            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 2)

            languageMenu(
                title: L("翻译成"),
                selection: $model.settings.targetLanguageID,
                options: model.translationOptions,
                label: displayName(for: model.settings.targetLanguageID)
            )
        }
        .disabled(model.isRunning || model.isPreparing)
        .opacity(model.isRunning ? 0.55 : 1)
    }

    private func displayName(for identifier: String) -> String {
        let full = L10n.locale.localizedString(forIdentifier: identifier) ?? identifier
        guard isCompact else { return full }
        // "Englisch (Vereinigte Staaten)" would eat the whole capsule on a phone.
        let shortened = full.replacingOccurrences(
            of: #"\s*\([^)]*\)"#,
            with: "",
            options: .regularExpression
        )
        return shortened.isEmpty ? full : shortened
    }

    private func languageMenu(
        title: String,
        selection: Binding<String>,
        options: [LanguageOption],
        label: String
    ) -> some View {
        Menu {
            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(option.displayName).tag(option.id)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(label)
                .font(isCompact ? .footnote : .subheadline)
                .lineLimit(isCompact ? 2 : 1)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
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
