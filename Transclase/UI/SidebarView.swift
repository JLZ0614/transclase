import SwiftUI

/// Sidebar built on the system list style, so selection, hover, vibrancy and
/// keyboard navigation behave like every other Mac app.
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Binding var showSettings: Bool
    @State private var selection: LectureSession.ID?

    var body: some View {
        List(selection: $selection) {
            Section {
                Button {
                    Task { await model.newConversation() }
                } label: {
                    Label(L("新对话"), systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }

            Section(L("工作区")) {
                ForEach(model.sessions) { session in
                    SessionRow(session: session, isCurrent: session.id == model.currentSession?.id)
                        .tag(session.id)
                        .contextMenu {
                            Button(L("打开")) { Task { await model.openSession(session) } }
                            Button(L("在访达中显示")) { model.openInFinder(session) }
                        }
                }
            }

            Section {
                Button {
                    showSettings = true
                } label: {
                    Label(L("设置"), systemImage: "gearshape")
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        // The system sidebar material samples whatever is behind the window; this
        // app is deliberately one solid colour, so paint it instead.
        .background(Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.03))
        .navigationTitle("Transclase")
        .onChange(of: selection) { _, newValue in
            guard let newValue,
                  newValue != model.currentSession?.id,
                  let session = model.sessions.first(where: { $0.id == newValue })
            else { return }
            Task { await model.openSession(session) }
        }
        .onChange(of: model.currentSession) { _, newValue in
            selection = newValue?.id
        }
        .onAppear { selection = model.currentSession?.id }
        .overlay {
            if model.sessions.isEmpty {
                ContentUnavailableView(
                    L("还没有课堂记录"),
                    systemImage: "doc.text",
                    description: Text(L("点「新对话」开始第一节课"))
                )
                .allowsHitTesting(false)
            }
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
        Label {
            HStack(spacing: 6) {
                Text(session.displayName)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } icon: {
            Image(systemName: isCurrent ? "doc.text.fill" : "doc.text")
        }
    }
}
