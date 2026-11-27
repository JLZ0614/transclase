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
        return HStack(spacing: 8) {
            if showsTitle {
                Text(L("翻译助手"))
                    .font(.system(size: 12, weight: .semibold))
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
                    ProgressView().controlSize(.mini)
                } else {
                    Text(L("总结")).font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.borderedProminent)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(L("使用翻译助手需要先添加模型 API"))
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                step(1, L("打开「设置 → 翻译模型」"))
                step(2, L("点「添加模型供应商」"))
                step(3, L("选择厂商（如 DeepSeek）并填入 API Key"))
                step(4, L("点「测试 API 连接」确认成功后完成"))
            }

            Text(L("完成后即可在此总结要点、提问课堂内容。"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(.top, 16)
    }

    private func step(_ index: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(index).")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func submit() {
        let text = question
        question = ""
        Task { await model.ask(text) }
    }
}
