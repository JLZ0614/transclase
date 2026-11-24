import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Binding var showSettings: Bool
    /// On iPhone the toolbar already has a gear, so the row would duplicate it.
    var showsSettingsRow: Bool = true
    /// iPhone gets tap-to-open plus long-press / double-tap multi-selection.
    var supportsSelection: Bool = false

    @State private var isSelecting = false
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            newConversationButton

            HStack(spacing: 4) {
                Text(isSelecting ? L("已选 %d 项").replacingOccurrences(of: "%d", with: "\(selected.count)") : L("工作区"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if isSelecting {
                    Button(L("完成")) { endSelection() }
                        .font(.subheadline)
                } else {
                    Button {
                        model.refreshSessions()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 6)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.sessions) { session in
                        row(for: session)
                    }
                    if model.sessions.isEmpty {
                        Text(L("还没有课堂记录"))
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            if isSelecting {
                selectionBar
            } else {
                Spacer(minLength: 0)
                if showsSettingsRow {
                    Divider()
                    VStack(spacing: 1) {
                        SidebarItem(icon: "slider.horizontal.3", title: L("设置")) { showSettings = true }
                    }
                    .padding(8)
                }
            }
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

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Transclase")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, model.isFullScreen ? 8 : 14)
        .padding(.bottom, model.isFullScreen ? 8 : 12)
    }

    private var newConversationButton: some View {
        Button {
            Task { await model.newConversation() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text(L("新对话"))
                    .font(.body.weight(.medium))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: 11))
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func row(for session: LectureSession) -> some View {
        let isSelected = selected.contains(session.id)
        SessionRow(
            session: session,
            isCurrent: session.id == model.currentSession?.id,
            isSelected: isSelecting ? isSelected : nil
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if supportsSelection { enterSelection(with: session) }
        }
        .onTapGesture {
            if isSelecting {
                toggle(session)
            } else {
                Task { await model.openSession(session) }
            }
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            if supportsSelection { enterSelection(with: session) }
        }
        .contextMenu {
            if !supportsSelection {
                Button(L("打开")) { Task { await model.openSession(session) } }
                Button(L("在访达中显示")) { model.openInFinder(session) }
            }
        }
    }

    private var selectionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                actionButton(icon: "doc.on.doc", title: L("复制")) { copySelected() }
                ShareLink(items: selectedSessions.map(\.url)) {
                    VStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17))
                        Text(L("分享"))
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(selected.isEmpty)
                .opacity(selected.isEmpty ? 0.35 : 1)
                actionButton(icon: "trash", title: L("删除"), role: .destructive) { deleteSelected() }
            }
            .padding(.vertical, 10)
        }
    }

    private func actionButton(
        icon: String,
        title: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(selected.isEmpty)
        .opacity(selected.isEmpty ? 0.35 : 1)
    }

    // MARK: - Selection

    private var selectedSessions: [LectureSession] {
        model.sessions.filter { selected.contains($0.id) }
    }

    private func enterSelection(with session: LectureSession) {
        guard supportsSelection else { return }
        isSelecting = true
        selected.insert(session.id)
    }

    private func toggle(_ session: LectureSession) {
        if selected.contains(session.id) {
            selected.remove(session.id)
            if selected.isEmpty { isSelecting = false }
        } else {
            selected.insert(session.id)
        }
    }

    private func endSelection() {
        isSelecting = false
        selected.removeAll()
    }

    private func copySelected() {
        let text = selectedSessions
            .map { model.markdown(for: $0) }
            .joined(separator: "\n\n---\n\n")
        Clipboard.copy(text)
        endSelection()
    }

    private func deleteSelected() {
        let victims = selectedSessions
        endSelection()
        model.deleteSessions(victims)
    }
}

private struct SessionRow: View {
    let session: LectureSession
    let isCurrent: Bool
    /// `nil` when not in selection mode.
    let isSelected: Bool?

    private var relative: String {
        let seconds = Date().timeIntervalSince(session.createdAt)
        if seconds < 60 { return L("刚刚") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: session.createdAt, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 10) {
            if let isSelected {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: 16))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }

            Text(session.displayName)
                .font(.body)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(relative)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            isCurrent || (isSelected == true) ? Color.primary.opacity(0.07) : Color.clear,
            in: .rect(cornerRadius: 9)
        )
    }
}

private struct SidebarItem: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 18)
                Text(title)
                    .font(.body)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
