import SwiftUI

/// Right-hand assistant rail: timed key points, one-click summary, and Q&A over
/// the current transcript. Mirrors the right rail of a chat app rather than a
/// modal sheet, so it never blocks the captions.
struct AssistantPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    /// The sheet already has a navigation title; don't repeat it in the header.
    var showsTitle: Bool = true
    /// Inside a sheet the system material should show through, matching the
    /// workspace sheet instead of painting the solid app backdrop.
    var translucent: Bool = false
    @State private var question = ""

    var body: some View {
        ZStack {
            if translucent {
                Color.black.opacity(colorScheme == .dark ? 0.38 : 0.02)
            } else {
                AppBackdrop()
            }
            content
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.summaries) { block in
                        summaryCard(block)
                    }
                    if model.summaries.isEmpty && model.chat.isEmpty {
                        placeholder
                    }
                    ForEach(model.chat) { turn in
                        chatBubble(turn)
                    }
                }
                .padding(12)
            }

            if let error = model.assistantError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            Divider()
            HStack(spacing: 6) {
                TextField(L("问一下这节课…"), text: $question)
                    .textFieldStyle(.plain)
                    .onSubmit { submit() }
                Button {
                    submit()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || model.assistantBusy)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
    }

    private var header: some View {
        return HStack(spacing: 10) {
            AIOrb(size: 26)

            if showsTitle {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("翻译助手"))
                        .font(.subheadline.weight(.semibold))
                    Text(L("要点总结 · 课堂问答"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
            Menu {
                Picker(L("总结间隔"), selection: $model.settings.summaryIntervalMinutes) {
                    ForEach(Array(stride(from: 1, through: 10, by: 1)), id: \.self) { m in
                        Text(String(format: NSLocalizedString("每 %d 分钟", comment: ""), m)).tag(m)
                    }
                }
                Toggle(L("自动总结"), isOn: $model.settings.assistantEnabled)
            } label: {
                Image(systemName: "clock")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L("自动总结间隔"))

            Button {
                Task { await model.summarizeNow() }
            } label: {
                if model.assistantBusy {
                    ProgressView().controlSize(.mini).tint(.white)
                } else {
                    Label(L("总结"), systemImage: "sparkles")
                        .font(.footnote.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 4)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.42, green: 0.39, blue: 0.95))
            .controlSize(.small)
            .disabled(model.assistantBusy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, model.isFullScreen ? 6 : 9)
    }

    private func summaryCard(_ block: SummaryBlock) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(block.range)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(block.createdAt, style: .time)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Text(LocalizedStringKey(block.markdown))
                .font(.system(size: 12))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 9))
    }

    private func chatBubble(_ turn: AssistantTurn) -> some View {
        HStack {
            if turn.isUser { Spacer(minLength: 20) }
            Text(turn.text)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .padding(9)
                .background(
                    turn.isUser ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05),
                    in: .rect(cornerRadius: 9)
                )
            if !turn.isUser { Spacer(minLength: 20) }
        }
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                AIOrb(size: 64)
                Spacer()
            }
            .padding(.top, 12)
            .padding(.bottom, 4)

            Text(L("要点会出现在这里"))
                .font(.headline)
            Text(L("上课时点「总结」，或打开自动总结（1–10 分钟）。"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(L("也可以直接在下面提问。"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 16)
    }

    private func submit() {
        let text = question
        question = ""
        Task { await model.ask(text) }
    }
}


/// Glowing orb used as the assistant's identity: a soft gradient ring around a
/// sparkles glyph, in the spirit of Apple Intelligence's mark.
struct AIOrb: View {
    var size: CGFloat = 32

    private var gradient: AngularGradient {
        AngularGradient(
            colors: [
                Color(red: 0.36, green: 0.55, blue: 1.00),
                Color(red: 0.62, green: 0.40, blue: 0.98),
                Color(red: 0.98, green: 0.44, blue: 0.72),
                Color(red: 0.98, green: 0.66, blue: 0.42),
                Color(red: 0.36, green: 0.55, blue: 1.00),
            ],
            center: .center
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(gradient)
                .blur(radius: size * 0.12)
                .opacity(0.6)

            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(gradient, lineWidth: size * 0.06))

            Image(systemName: "sparkles")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(gradient)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
