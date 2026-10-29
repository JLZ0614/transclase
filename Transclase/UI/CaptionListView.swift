import SwiftUI

struct CaptionListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var userIsScrolling = false
    private let bottomID = "caption-bottom"

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        ForEach(model.captions) { caption in
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
                .onScrollPhaseChange { _, newPhase in
                    userIsScrolling = (newPhase == .interacting || newPhase == .tracking)
                }
                .onScrollGeometryChange(for: Bool.self) { scrollGeometry in
                    let distance = scrollGeometry.contentSize.height
                        - scrollGeometry.contentOffset.y
                        - scrollGeometry.containerSize.height
                    return distance < 90
                } action: { _, atBottom in
                    // Only a real drag may unpin the list. Letting content growth
                    // unpin it would race with the auto-scroll above and stop
                    // following the speaker forever.
                    if atBottom {
                        model.isPinnedToBottom = true
                    } else if userIsScrolling {
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
                        .accessibilityLabel("回到最新")
                    }
                }
            }
        }
    }
}

struct CaptionRow: View {
    let caption: Caption
    @EnvironmentObject private var model: AppModel

    private var isTranslating: Bool {
        caption.isFinal && caption.state == .pending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.settings.showOriginal {
                Text(caption.source)
                    .font(.system(size: model.settings.fontSize * 0.72))
                    .foregroundStyle(.secondary)
                    .opacity(caption.isFinal ? 1 : 0.75)
            }

            if let target = caption.target, !target.isEmpty {
                Text(target)
                    .font(.system(size: model.settings.fontSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .opacity(caption.state == .draft ? 0.45 : 1)
                    .contentTransition(.opacity)
            } else if isTranslating {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("翻译中…")
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
