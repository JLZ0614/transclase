import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Transclase")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, model.isFullScreen ? 8 : 14)
            .padding(.bottom, model.isFullScreen ? 8 : 12)

            Button {
                Task { await model.newConversation() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text(L("新对话"))
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: 9))
            .padding(.horizontal, 12)

            HStack(spacing: 4) {
                Text(L("工作区"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.refreshSessions()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(L("刷新"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 6)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(model.sessions) { session in
                        SessionRow(
                            session: session,
                            isCurrent: session.id == model.currentSession?.id
                        )
                        .onTapGesture(count: 2) { model.openInFinder(session) }
                        .onTapGesture { Task { await model.openSession(session) } }
                        .contextMenu {
                            Button(L("打开")) { Task { await model.openSession(session) } }
                            Button(L("在访达中显示")) { model.openInFinder(session) }
                        }
                    }
                    if model.sessions.isEmpty {
                        Text(L("还没有课堂记录"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            Spacer(minLength: 0)

            Divider()
            VStack(spacing: 1) {
                SidebarItem(icon: "slider.horizontal.3", title: L("设置")) { showSettings = true }
            }
            .padding(8)
        }
        .background {
            // A touch of transparent black, not a grey plate.
            Color.black.opacity(colorScheme == .dark ? 0.38 : 0.06)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.10))
                .frame(width: 1)
        }
    }
}

private struct SessionRow: View {
    let session: LectureSession
    let isCurrent: Bool

    private var relative: String {
        let seconds = Date().timeIntervalSince(session.createdAt)
        if seconds < 60 { return L("刚刚") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: session.createdAt, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            Text(session.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(relative)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(
            isCurrent ? Color.primary.opacity(0.07) : Color.clear,
            in: .rect(cornerRadius: 7)
        )
    }
}

private struct SidebarItem: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(LocalizedStringKey(title))
                    .font(.system(size: 12))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
