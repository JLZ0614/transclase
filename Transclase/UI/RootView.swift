import SwiftUI
import Translation

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

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
            .navigationTitle("课堂同传")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
            }
            .safeAreaInset(edge: .bottom) {
                ControlDock()
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 520)
        #endif
        .animation(.snappy(duration: 0.25), value: model.errorMessage)
        .translationTask(model.translationConfiguration) { session in
            model.adoptTranslationSession(session)
        }
        .task {
            if AppModel.wantsSelfTest {
                await model.bootstrap()
                await model.runSelfTest()
                return
            }
            if AppModel.wantsDemo, model.captions.isEmpty {
                // Demo mode is an explicit switch, so auto-play on launch — and
                // do not make it wait for capability discovery.
                await model.start()
                await model.bootstrap()
                return
            }
            await model.bootstrap()
        }
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
        .onChange(of: scenePhase) { _, phase in
            // Without a background-audio entitlement the capture session dies
            // when iOS suspends us, so shut down cleanly instead of leaving a
            // half-dead pipeline behind.
            #if os(iOS)
            if phase == .background, model.isRunning {
                Task { await model.stop() }
            }
            #endif
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(model)
        }
        .confirmationDialog(
            "清空全部字幕？",
            isPresented: $model.pendingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空", role: .destructive) { model.clear() }
            Button("取消", role: .cancel) { model.pendingClearConfirmation = false }
        } message: {
            Text("当前 \(model.captions.count) 段内容会被删除，且无法恢复。想留档的话先导出。")
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
            .accessibilityLabel("关闭提示")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

struct EmptyStateView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tint)
                .frame(width: 96, height: 96)
                .glassEffect(.regular, in: .circle)

            VStack(spacing: 8) {
                Text("把设备放在桌上，点开始")
                    .font(.title3.weight(.semibold))
                Text("声音只在本机处理。识别用系统语音模型，翻译用系统离线语言包。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            if model.settings.demoMode {
                Label("演示模式：会播放一段模拟讲座", systemImage: "play.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.isBootstrapping {
                ProgressView("正在检查本机语言能力…")
                    .font(.caption)
            } else if model.speechOptions.isEmpty {
                Label("这台设备没有可用的系统语音识别，可以先试试演示模式", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await model.start() }
                } label: {
                    Label("开始听课", systemImage: "mic.fill")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                Button {
                    Task { await model.playDemo() }
                } label: {
                    Text("看演示")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }

            Spacer()
        }
        .padding(28)
    }
}
