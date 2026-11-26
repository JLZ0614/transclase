import SwiftUI
import Translation

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSettings = false
    @State private var showAssistant = false
    @State private var showSidebar = true
    @State private var showSessions = false

    var body: some View {
        #if os(iOS)
        if isRegularWidth { tabletBody } else { phoneBody }
        #else
        desktopBody
        #endif
    }

    #if os(iOS)
    private var isRegularWidth: Bool { sizeClass == .regular }
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// iPad: the transcript keeps the full width and the two side panels float
    /// above it instead of pushing it into a narrow column.
    private var tabletBody: some View {
        ZStack {
            AppBackdrop()

            NavigationStack {
                mainColumn
                    .navigationTitle(model.currentSession?.displayName ?? "Transclase")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(L("工作区")) {
                                withAnimation(.snappy(duration: 0.22)) { showSessions.toggle() }
                            }
                        }
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button {
                                withAnimation(.snappy(duration: 0.22)) { showAssistant.toggle() }
                            } label: { BrandGlyph(size: 22) }
                            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        }
                    }
            }
            .preferredColorScheme(model.settings.appearance.colorScheme)
            .id(model.localizationToken)
            .translationTask(model.translationConfiguration) { session in
                model.adoptTranslationSession(session)
            }
            .task { await bootstrapOnce() }

            if showSessions {
                floatingPanel(width: 300, alignment: .leading, dismiss: { showSessions = false }) {
                    SidebarView(showSettings: $showSettings, showsSettingsRow: false,
                                supportsSelection: true, floating: true)
                }
            }

            if showAssistant {
                floatingPanel(width: 340, alignment: .trailing, dismiss: { showAssistant = false }) {
                    AssistantPanel(showsTitle: false, translucent: true)
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet().environmentObject(model) }
        .sheet(item: $model.pendingShare) { payload in
            ShareSheet(items: [payload.url])
        }
    }

    /// Rounded card pinned to one side, with a tap-anywhere backdrop to close it.
    private func floatingPanel<Content: View>(
        width: CGFloat,
        alignment: HorizontalAlignment,
        dismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(.snappy(duration: 0.2)) { dismiss() } }

            HStack(spacing: 0) {
                if alignment == .trailing { Spacer(minLength: 0) }
                content()
                    .frame(width: width)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
                    .padding(16)
                    .transition(.move(edge: alignment == .leading ? .leading : .trailing)
                        .combined(with: .opacity))
                if alignment == .leading { Spacer(minLength: 0) }
            }
        }
        .environmentObject(model)
    }

    /// iPhone: a single column with the workspace, assistant and settings behind
    /// sheets, because three panes do not fit.
    private var phoneBody: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()
                mainColumn
            }
            .navigationTitle(model.currentSession?.displayName ?? "Transclase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("工作区")) { showSessions = true }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showAssistant = true } label: { BrandGlyph(size: 24) }
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .preferredColorScheme(model.settings.appearance.colorScheme)
            .id(model.localizationToken)
            .translationTask(model.translationConfiguration) { session in
                model.adoptTranslationSession(session)
            }
            .task { await bootstrapOnce() }
            .overlay {
                // Edge swipes: workspace from the left, assistant from the right.
                HStack(spacing: 0) {
                    edgeSwipe(.leading) { showSessions = true }
                    Spacer(minLength: 0)
                    edgeSwipe(.trailing) { showAssistant = true }
                }
            }
            .sheet(isPresented: $showSessions) {
                NavigationStack {
                    SidebarView(showSettings: $showSettings, showsSettingsRow: false,
                                supportsSelection: true, floating: true)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) {
                            Button(L("完成")) { showSessions = false }
                        } }
                }
                .environmentObject(model)
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showAssistant) {
                NavigationStack {
                    AssistantPanel(showsTitle: false, translucent: true)
                        .navigationTitle(L("翻译助手"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) {
                            Button(L("完成")) { showAssistant = false }
                        } }
                }
                .environmentObject(model)
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSettings) { SettingsSheet().environmentObject(model) }
            .sheet(item: $model.pendingShare) { url in
                ShareSheet(items: [url])
            }
        }
    }
    #endif

    #if os(macOS)
    private var desktopBody: some View {
        ZStack {
            AppBackdrop()
            content
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .windowToolbarFullScreenVisibility(.onHover)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { showSidebar.toggle() }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(L("显示 / 隐藏边栏"))
            }
            ToolbarItem(placement: .primaryAction) {
                // One capsule holding both actions, matching the iOS toolbar.
                HStack(spacing: 4) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { showAssistant.toggle() }
                    } label: {
                        BrandGlyph(size: 16)
                            .frame(width: 26, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("翻译助手"))

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 26, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("设置"))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
            }
        }
        .preferredColorScheme(model.settings.appearance.colorScheme)
        .id(model.localizationToken)
        #if os(macOS)
        .background(WindowSizer().frame(width: 0, height: 0))
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { model.windowSize = geo.size }
                    .onChange(of: geo.size) { _, newValue in model.windowSize = newValue }
            }
        )
        #endif
        .navigationTitle("")
        .animation(.snappy(duration: 0.25), value: model.errorMessage)
        .translationTask(model.translationConfiguration) { session in
            model.adoptTranslationSession(session)
        }
        .task { await bootstrapOnce() }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            model.isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            model.isFullScreen = false
        }
        #endif
        .onChange(of: model.settings.sourceLanguageID) { _, _ in
            model.syncTranslationConfiguration()
        }
        .onChange(of: model.settings.targetLanguageID) { _, _ in
            model.syncTranslationConfiguration()
        }
        .onChange(of: model.settings.demoMode) { _, _ in
            model.syncTranslationConfiguration()
        }
        .onChange(of: model.settings) { _, _ in
            model.saveSettings()
        }
        .onChange(of: model.settings.assistantEnabled) { _, _ in
            if model.isRunning { model.startSummaryTimer() } else { model.stopSummaryTimer() }
        }
        .onChange(of: model.settings.summaryIntervalMinutes) { _, _ in
            model.refreshSummaryTimer()
        }
        .confirmationDialog(
            L("清空全部字幕？"),
            isPresented: Binding(
                get: { model.pendingClearConfirmation },
                set: { model.pendingClearConfirmation = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button(L("清空"), role: .destructive) { model.clear() }
            Button(L("取消"), role: .cancel) { model.pendingClearConfirmation = false }
        } message: {
            Text(String(format: NSLocalizedString("当前 %d 段内容会被删除，且无法恢复。想留档的话先导出。", comment: ""), model.captions.count))
        }
        .fileExporter(
            isPresented: Binding(
                get: { model.isExporting },
                set: { model.isExporting = $0 }
            ),
            document: model.exportDocument,
            contentType: .markdownText,
            defaultFilename: model.exportFilename
        ) { _ in
            model.exportDocument = nil
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet().environmentObject(model)
        }
        #if os(iOS)
        .sheet(item: $model.pendingShare) { payload in
            ShareSheet(items: [payload.url])
        }
        #endif
    }

    #endif

    private var content: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                if showSidebar {
                    SidebarView(showSettings: $showSettings, showsSettingsRow: false)
                        .frame(width: 270)
                    Divider()
                }

                mainColumn
            }

            if showAssistant {
                AssistantPanel(translucent: true)
                    .environmentObject(model)
                    .frame(width: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
                    .padding(.trailing, 16)
                    .padding(.vertical, 16)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: showAssistant)
    }

    private var mainColumn: some View {
        ZStack {
            Color.clear

            VStack(spacing: 0) {
                if let message = model.errorMessage {
                    ErrorBanner(message: message) {
                        model.errorMessage = nil
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if model.captions.isEmpty {
                    EmptyStateView()
                } else {
                    CaptionListView()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ControlDock()
        }
    }

    /// A narrow invisible strip that only reacts to horizontal drags, so it can
    /// live on top of scrolling content without stealing vertical gestures.
    private func edgeSwipe(_ edge: HorizontalEdge, action: @escaping () -> Void) -> some View {
        Color.clear
            .frame(width: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 15)
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) > abs(dy) * 1.5 else { return }
                        if edge == .leading, dx > 40 { action() }
                        if edge == .trailing, dx < -40 { action() }
                    }
            )
    }

    private func bootstrapOnce() async {
        await model.bootstrap()
        model.refreshSessions()
        if AppModel.wantsSelfTest {
            await model.runSelfTest()
        } else if AppModel.wantsDemo, model.captions.isEmpty {
            await model.start()
        }
    }
}

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("关闭提示"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

struct EmptyStateView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            BrandGlyph(size: 96)

            VStack(spacing: 7) {
                Text(L("点「新对话」开始一节课"))
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340)
                Text(L("或者直接点下面的麦克风。声音只在本机处理。"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            if model.settings.demoMode {
                Label(L("演示模式：会播放一段模拟讲座"), systemImage: "play.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            } else if model.isBootstrapping {
                ProgressView(L("正在检查本机语言能力…"))
                    .font(.caption)
            } else if model.speechOptions.isEmpty {
                Label(L("这台设备没有可用的系统语音识别"), systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                readinessCard
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        if model.needsDownloads {
                            await model.prepareOfflinePack()
                        } else {
                            await model.startLecture()
                        }
                    }
                } label: {
                    Group {
                        if model.isPreparingPack {
                            Label(L("下载中…"), systemImage: "arrow.down.circle")
                        } else if model.needsDownloads {
                            Label(L("开始下载"), systemImage: "arrow.down.circle")
                        } else {
                            Label(L("开始听课"), systemImage: "mic.fill")
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(model.isPreparingPack)

                Button {
                    Task { await model.startVoiceNotes() }
                } label: {
                    Text(L("语音笔记")).padding(.horizontal, 6)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(model.isPreparing)
            }

            Spacer()
        }
        .padding(28)
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            ReadinessRow(title: L("识别模型"), detail: model.sourceName, ready: model.isSpeechModelInstalled)
            ReadinessRow(title: L("翻译语言包"), detail: model.pairLabel, ready: model.isTranslationPackInstalled)

            if let progress = model.speechProgress {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: progress).progressViewStyle(.linear)
                    Text(String(format: NSLocalizedString("下载识别模型 %d%%", comment: ""), Int(progress * 100)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            } else if !model.isReadyOffline {
                Text(L("首次使用需要联网下载一次，约 400 MB。装好后上课全程离线。"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 380)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

private struct ReadinessRow: View {
    let title: String
    let detail: String
    let ready: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 13))
                .foregroundStyle(ready ? Color.green : Color.secondary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(ready ? L("已就绪") : L("待下载"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

/// Forces the first window to a 1200×860 content size (DSH proportions) and
/// keeps a sensible minimum, regardless of any remembered frame.
#if os(macOS)
private struct WindowSizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            // No window/sheet restoration: a restored sheet would greet the user
            // with a dialog they never opened.
            window.isRestorable = false
            // Let the window's own backdrop show through the titlebar / full-screen
            // toolbar strip instead of AppKit drawing a grey material there.
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            // In full screen AppKit paints the toolbar strip with the window
            // background colour, which reads as a grey band above the black
            // content. Match it to the backdrop instead.
            window.backgroundColor = NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? .black
                    : .underPageBackgroundColor
            }
            window.minSize = NSSize(width: 960, height: 560)

            // A window restored from an older build can be narrower than the
            // three-column minimum; widen it once so the layout is not cramped.
            if window.frame.width < 960 {
                var frame = window.frame
                frame.size = NSSize(width: 1180, height: max(frame.height, 760))
                window.setFrame(frame, display: true)
                window.center()
            }
            if !context.coordinator.didSize {
                context.coordinator.didSize = true
                // About a quarter of the screen: half the width, half the height.
                let visible = (window.screen ?? NSScreen.main)?.visibleFrame
                    ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
                let target = NSSize(
                    width: max(720, visible.width * 0.5),
                    height: max(480, visible.height * 0.52)
                )
                window.setContentSize(target)
                window.center()
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var didSize = false
        var observers: [NSObjectProtocol] = []
    }
}
#endif
