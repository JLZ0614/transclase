import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Binding var showSettings: Bool
    /// On iPhone the toolbar already has a gear, so the row would duplicate it.
    var showsSettingsRow: Bool = true
    /// Unused on iPad/phone now; kept so call sites stay readable.
    var supportsSelection: Bool = true
    /// When shown as a floating card the panel provides its own material.
    var floating: Bool = false

    @State private var isSelecting = false
    @State private var selected: Set<String> = []
    @State private var renamingURL: URL?
    @State private var renameDraft = ""
    @State private var showNewFolder = false
    @State private var newFolderName = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            newConversationButton
            workspaceHeader

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.folders) { folder in
                        folderRow(folder)
                    }
                    ForEach(model.sessions) { session in
                        sessionRow(session)
                    }
                    if model.folders.isEmpty, model.sessions.isEmpty {
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
            } else if showsSettingsRow {
                Spacer(minLength: 0)
                Divider()
                VStack(spacing: 1) {
                    SidebarItem(icon: "slider.horizontal.3", title: L("设置")) { showSettings = true }
                }
                .padding(8)
            }
        }
        .background {
            if !floating {
                Color.black.opacity(colorScheme == .dark ? 0.38 : 0.06)
            }
        }
        .overlay(alignment: .trailing) {
            if !floating {
                Rectangle()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.10))
                    .frame(width: 1)
            }
        }
        #if os(iOS)
        .sheet(item: $model.pendingShare) { payload in
            ShareSheet(items: [payload.url])
        }
        #endif
        .alert(L("重命名"), isPresented: Binding(
            get: { renamingURL != nil },
            set: { if !$0 { renamingURL = nil } }
        )) {
            TextField(L("名称"), text: $renameDraft)
            Button(L("取消"), role: .cancel) { renamingURL = nil }
            Button(L("确定")) {
                if let url = renamingURL { model.renameItem(url, to: renameDraft) }
                renamingURL = nil
            }
        }
        .alert(L("新建文件夹"), isPresented: $showNewFolder) {
            TextField(L("名称"), text: $newFolderName)
            Button(L("取消"), role: .cancel) { newFolderName = "" }
            Button(L("创建")) {
                _ = model.newFolder(named: newFolderName)
                newFolderName = ""
                model.refreshSessions()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            BrandGlyph(size: 18)
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

    private var workspaceHeader: some View {
        HStack(spacing: 6) {
            if !model.workspacePath.isEmpty {
                Button {
                    model.goUp()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
            }

            Text(model.workspacePath.last ?? L("工作区"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if isSelecting {
                Button(L("完成")) { endSelection() }
                    .font(.subheadline)
            } else {
                HStack(spacing: 12) {
                    Button {
                        newFolderName = ""
                        showNewFolder = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .help(L("新建文件夹"))
                    .accessibilityLabel(L("新建文件夹"))

                    Menu {
                        Button {
                            newFolderName = ""
                            showNewFolder = true
                        } label: {
                            Label(L("新建文件夹"), systemImage: "folder.badge.plus")
                        }
                        Button {
                            isSelecting = true
                        } label: {
                            Label(L("批量删除"), systemImage: "checkmark.circle")
                        }
                        Divider()
                        Button {
                            model.refreshSessions()
                        } label: {
                            Label(L("刷新"), systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    // MARK: - Rows

    @ViewBuilder
    private func folderRow(_ folder: WorkspaceFolder) -> some View {
        let isSelected = selected.contains(folder.id)
        HStack(spacing: 10) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            } else {
                Image(systemName: "folder")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            Text(folder.id)
                .font(.body)
                .lineLimit(1)
            Spacer(minLength: 4)
            if !isSelecting {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(isSelected ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: 9))
        .onTapGesture {
            if isSelecting {
                toggle(folder.id)
            } else {
                model.enter(folder)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.move(urls, to: folder.url)
            return true
        }
        .contextMenu {
            Button { model.enter(folder) } label: { Label(L("打开"), systemImage: "folder") }
            moveMenu(for: folder.url)

            Button {
                renamingURL = folder.url
                renameDraft = folder.id
            } label: {
                Label(L("重命名"), systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                model.deleteItems([folder.url])
            } label: {
                Label(L("删除"), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: LectureSession) -> some View {
        let isSelected = selected.contains(session.id)
        SessionRow(
            session: session,
            isCurrent: session.id == model.currentSession?.id,
            isSelected: isSelecting ? isSelected : nil
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                toggle(session.id)
            } else {
                Task { await model.openSession(session) }
            }
        }
        .draggable(session.url)
        .contextMenu {
            Button {
                Task { await model.resumeRecording(session) }
            } label: {
                Label(L("打开并继续录音"), systemImage: "mic.badge.plus")
            }

            Button {
                model.copySourceText(of: session)
            } label: {
                Label(L("复制语音文本"), systemImage: "doc.on.doc")
            }

            Button {
                model.requestExport(of: session, sourceOnly: false)
            } label: {
                Label(L("导出（原文 + 翻译 + 总结）"), systemImage: "square.and.arrow.up")
            }

            Button {
                model.requestExport(of: session, sourceOnly: true)
            } label: {
                Label(L("导出纯语音文本"), systemImage: "text.alignleft")
            }

            moveMenu(for: session.url)

            Button {
                renamingURL = session.url
                renameDraft = session.id
            } label: {
                Label(L("重命名"), systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                model.deleteItems([session.url])
            } label: {
                Label(L("删除"), systemImage: "trash")
            }

            #if os(macOS)
            Divider()
            Button(L("在访达中显示")) { model.openInFinder(session) }
            #endif
        }
    }

    /// Submenu listing every folder that is not the item's current home.
    @ViewBuilder
    private func moveMenu(for url: URL) -> some View {
        Menu {
            let current = url.deletingLastPathComponent().standardizedFileURL
            Button {
                model.move([url], to: SessionStore.directory)
            } label: {
                Label(L("工作区（根目录）"), systemImage: "house")
            }
            .disabled(current.path == SessionStore.directory.standardizedFileURL.path)

            ForEach(model.allFolders.filter {
                $0.standardizedFileURL.path != current.path
                    && !$0.standardizedFileURL.path.hasPrefix(url.standardizedFileURL.path)
            }, id: \.self) { folder in
                Button {
                    model.move([url], to: folder)
                } label: {
                    Label(relativeName(of: folder), systemImage: "folder")
                }
            }
        } label: {
            Label(L("移动到…"), systemImage: "folder.badge.minus")
        }
    }

    private func relativeName(of url: URL) -> String {
        let rootPath = SessionStore.directory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        let tail = String(path.dropFirst(rootPath.count))
        return tail.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private var selectionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text(String(format: NSLocalizedString("已选 %d 项", comment: ""), selected.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    deleteSelection()
                } label: {
                    Label(L("删除"), systemImage: "trash")
                }
                .disabled(selected.isEmpty)
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Selection

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func endSelection() {
        isSelecting = false
        selected.removeAll()
    }

    private func deleteSelection() {
        var urls: [URL] = []
        urls += model.folders.filter { selected.contains($0.id) }.map(\.url)
        urls += model.sessions.filter { selected.contains($0.id) }.map(\.url)
        endSelection()
        model.deleteItems(urls)
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

            Text(session.id)
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
