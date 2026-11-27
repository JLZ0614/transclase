import SwiftUI

struct CaptionListView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var transcript: TranscriptStore
    @State private var userIsScrolling = false
    @State private var lastUserScroll = Date.distantPast
    private let bottomID = "caption-bottom"

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        ForEach(transcript.captions) { caption in
                            CaptionRow(caption: caption)
                                .id(caption.id)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    // Anchor short transcripts to the bottom edge so the newest
                    // line always sits at the same reading position.
                    .frame(minHeight: geometry.size.height, alignment: .bottom)
                }
                .onChange(of: model.scrollGeneration) { _, _ in
                    guard model.isPinnedToBottom, model.settings.autoScroll else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
                .mask(alignment: .top) {
                    // Fade the first visible line out under the title bar instead
                    // of letting it collide with the toolbar.
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.55), location: 0.035),
                            .init(color: .black, location: 0.06),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .onScrollPhaseChange { _, newPhase in
                    let dragging = (newPhase == .interacting || newPhase == .tracking)
                    userIsScrolling = dragging
                    if dragging { lastUserScroll = Date() }
                }
                .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                    ScrollMetrics(
                        distance: geometry.contentSize.height
                            - geometry.contentOffset.y
                            - geometry.containerSize.height
                    )
                } action: { _, metrics in
                    // Content growth also changes `distance`; only a *recent user
                    // gesture* may unpin, otherwise a full page stops following.
                    if metrics.distance < 90 {
                        model.isPinnedToBottom = true
                    } else if Date().timeIntervalSince(lastUserScroll) < 1.5,
                              metrics.distance > 240 {
                        model.isPinnedToBottom = false
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !model.isPinnedToBottom {
                        Button {
                            model.isPinnedToBottom = true
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(bottomID, anchor: .bottom)
                            }
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 38, height: 38)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                        .buttonStyle(.plain)
                        .padding(18)
                        .accessibilityLabel(L("回到最新"))
                    }
                }
            }
        }
    }
}

struct CaptionRow: View {
    let caption: Caption
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// iPhone 上按系统 App 的观感放大：正文约 22pt，原文约 15pt。
    private var scale: Double { sizeClass == .compact ? 1.4 : 1.0 }

    private var isTranslating: Bool {
        caption.isFinal && caption.state == .pending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.settings.showOriginal {
                Text(caption.source)
                    .font(.system(size: model.settings.fontSize * 0.72 * scale))
                    .foregroundStyle(colorScheme == .dark ? AnyShapeStyle(.secondary)
                                                          : AnyShapeStyle(Color.primary.opacity(0.62)))
                    .opacity(caption.isFinal ? 1 : 0.75)
            }

            if let target = caption.target, !target.isEmpty {
                Text(target)
                    .font(.system(size: model.settings.fontSize * scale, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .opacity(caption.state == .draft ? 0.45 : 1)
                    .contentTransition(.opacity)
            } else if case .failed = caption.state {
                Button {
                    model.retranslate(caption)
                } label: {
                    Label(L("翻译失败，点按重试"), systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else if isTranslating {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(L("翻译中…"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .opacity(caption.isFinal ? 1 : 0.85)
        .animation(.easeOut(duration: 0.16), value: caption.target)
        .animation(.easeOut(duration: 0.16), value: caption.isFinal)
    }
}


private struct ScrollMetrics: Equatable {
    let distance: CGFloat
}
